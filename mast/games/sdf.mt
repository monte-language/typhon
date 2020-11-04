import "lib/asdl" =~ [=> buildASDLModule]
import "lib/colors" =~ [=> makeColor]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/samplers" =~ [=> samplerConfig]
import "lib/vectors" =~ [=> V, => glsl]
import "fun/png" =~ [=> makePNG]
exports (main)

def ["ASTBuilder" => CSG :DeepFrozen] | _ := eval(buildASDLModule(`
solid = Sphere(double radius, material)
      | Box(double width, double height, double depth, material)
      | Cube(double length, material)
      | Cylinder(double height, double radius, material)
      | Cone(double radius, double height, material)
      | InfiniteCylindricalCross(double xradius, double yradius, double zradius,
                                 material)
      | Translation(solid shape, double dx, double dy, double dz)
      | Rotation(solid shape, double theta, double ux, double uy, double uz)
      | Scaling(solid shape, double factor)
      | Displacement(solid shape, displacement d, double amplitude)
      | OrthorhombicClamp(solid repetend, double period, double width,
                          double height, double depth)
      | OrthorhombicCrystal(solid repetend, double width, double height,
                            double depth)
      | CubicMirror(solid repetend)
      | Intersection(solid shape, solid* shapes)
      | Union(solid shape, solid* shapes)
      | Difference(solid minuend, solid subtrahend)
displacement = Sines(double lx, double ly, double lz)
             | Noise(double lx, double ly, double lz, int octaves)
             | Dimples(double lx, double ly, double lz)
material = Lambert(color flat, color ambient)
         | Phong(color specular, color diffuse, color ambient,
                 double shininess)
color = Color(double red, double green, double blue)
      | Normal
      | Depth
      | Gradient
      | Checker
      | Marble(double red, double green, double blue)
`, "csg"), safeScope)(null)

# http://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/
# https://erleuchtet.org/~cupe/permanent/enhanced_sphere_tracing.pdf
# https://www.cs.williams.edu/~morgan/cs371-f14/reading/implicit.pdf

# Signed distance functions, or SDFs, are objects with a .run/1 which sends 3D
# vectors of Doubles to a single Double. The interpretation is that the
# object is some geometry, and the return value is the signed distance from
# the argument point to the nearest point on the geometry, with negative
# distance indicating that the point is within the geometry.

# https://en.wikipedia.org/wiki/Constructive_solid_geometry

# Constructed solids are built from geometric primitives and some basic
# set-theoretic operations. There is a functor CSG -> SDF which assigns each
# shape a function that can determine distances to that shape. This will be
# our main insight for interacting with our constructed geometry.

def one :DeepFrozen := V(1.0, 1.0, 1.0)
def zero :DeepFrozen := one * 0.0

def sumPlus(x, y) as DeepFrozen { return x + y }
def sumDouble :DeepFrozen := V.makeFold(0.0, sumPlus)
def sumRow :DeepFrozen := V.makeFold(one * 0.0, sumPlus)

def maxPlus(x, y) as DeepFrozen { return x.max(y) }
def max :DeepFrozen := V.makeFold(-Infinity, maxPlus)

def PI :Double := 1.0.arcSine() * 2

# Cheap normal estimation. Pick a small epsilon and evaluate the two-sided
# derivative:
# (f(p + e) - f(p - e)) / 2e
# Since e is the same for all three axes, and we want to return a unit vector,
# we don't have to divide at the end.
# https://commons.wikimedia.org/wiki/File:AbsoluteErrorNumericalDifferentiationExample.png
# This epsilon balances all of our concerns when used with the hack below.
def epsilon :Double := 0.000_1
def epsilonX :DeepFrozen := V(epsilon, 0.0, 0.0)
def epsilonY :DeepFrozen := V(0.0, epsilon, 0.0)
def epsilonZ :DeepFrozen := V(0.0, 0.0, epsilon)
def estimateNormal(sdf, p) as DeepFrozen:
    # Hack: Get a much better epsilon by pre-scaling with the (norm of) the
    # zero, see https://en.wikipedia.org/wiki/Numerical_differentiation
    def scale := glsl.length(p)
    return glsl.normalize(V(
        sdf(p + epsilonX * scale)[0] - sdf(p - epsilonX * scale)[0],
        sdf(p + epsilonY * scale)[0] - sdf(p - epsilonY * scale)[0],
        sdf(p + epsilonZ * scale)[0] - sdf(p - epsilonZ * scale)[0],
    ))

def maxSteps :Int := 100

def shortestDistanceToSurface(sdf, eye, direction, end :Double,
                              pixelRadius :Double) as DeepFrozen:
    var depth := 0.0
    # Track signs, based on where we've started.
    # XXX Typhon should give Doubles a method for checking the sign bit!
    def sign := sdf(eye)[0].belowZero().pick(-1.0, 1.0)
    # Best candidate for a hit, if there's been one.
    var best := null
    var bestError :Double := pixelRadius
    for i in (0..!maxSteps):
        def step := eye + direction * depth
        def [distance, texture] := sdf(step)
        def signedDistance := distance * sign
        # traceln(`$i: sdf($eye, $direction, $depth) -> sdf($step) -> $signedDistance`)

        # If we took a step and ended up inside the geometry, but we took the
        # step size based on the geometry's SDF, then we must conclude that
        # there is numerical instability inside the SDF. This happens all the
        # time; it's not wrong or weird, but it does mean that this guess was
        # actually extremely good and we should treat the remaining negative
        # offset as numerical error.
        if (signedDistance.belowZero()):
            return [depth, i, 0.0, texture]

        # We can and should leave as soon as the first hit happens which is
        # close enough to reasonably occlude the pixel.
        # NB: In the paper's original algorithm, there's some additional
        # machinery for checking candidate values, but we go with either the
        # first hit or nothing.
        def error := signedDistance.abs() / depth
        if (error < bestError):
            # traceln(`$i: error $error, threshold $bestError`)
            best := [depth, i, error, texture]
            bestError := error

        # Did we hit the back wall?
        if (depth >= end):
            return if (best == null) { [end, i, bestError, null] } else { best }

        depth += signedDistance

    # We ran out of steps. Return the best hit we got, if we got one.
    return if (best == null) { [end, maxSteps, bestError, null] } else { best }

def makeRayDirection(fieldOfView :Double) as DeepFrozen:
    "
    Fix a field of view for casting rays in a given direction.

    The field of view should be given as the angle in radians from the center
    of the camera to its edge; pi / 8 or pi / 6 are common choices.
    "

    # The tangent of the FOV angle gives how fast one half of the screen
    # expands; doubling it gives the full screen ratio.
    def fovr :Double := fieldOfView.tangent() * 2.0

    return def rayDirection(u :Double, v :Double, aspectRatio :Double) as DeepFrozen:
        def x := (u - 0.5) * fovr * aspectRatio
        def y := (v - 0.5) * fovr
        def rv := glsl.normalize(V(x, y, -1.0))
        # traceln(`rayDirection($fieldOfView, $u, $v, $aspectRatio) -> $rv`)
        return rv

def viewMatrix(eye :DeepFrozen, center, up) as DeepFrozen:
    # https://www.khronos.org/registry/OpenGL-Refpages/gl2.1/xhtml/gluLookAt.xml
    def f :DeepFrozen := glsl.normalize(center - eye)
    def s :DeepFrozen := glsl.normalize(glsl.cross(f, up))
    def u :DeepFrozen := glsl.cross(s, f)
    # traceln(`viewMatrix($eye, $center, $up) -> $s $u ${-f}`)
    return def moveCamera(dir) as DeepFrozen:
        def rv := sumRow(V(s, u, -f) * dir)
        # traceln(`moveCamera($dir) -> $rv`)
        return rv

def maxDepth :Double := 500.0

# Do a couple rounds of gradient descent in order to polish an estimated hit.
# This works about as well as you might expect: After two rounds, the hit is
# accurate to 1 in 1 million, and three rounds is almost always enough.
# The error comes from:
# https://static.aminer.org/pdf/PDF/000/593/434/efficient_antialiased_rendering_of_d_linear_fractals.pdf
# But it is just the pixel area over the distance traveled!
def refineEstimate(sdf, eye, dir, distance :Double, pixelRadius :Double) as DeepFrozen:
    def pixelArea := PI * pixelRadius ** 2
    # We're only taking two steps, and they're short when unrolled.
    def firstErr := sdf(eye + dir * distance)[0] - pixelArea / distance
    def t := distance + firstErr
    def secondErr := sdf(eye + dir * t)[0] - pixelArea / t
    # It is quite possible that we're not improving the estimate; that is,
    # that we are numerically unstable near a divergent fixed point. So return
    # whichever is better.
    return (secondErr.abs() > firstErr.abs()).pick(distance, t)

def drawSignedDistanceFunction(sdf) as DeepFrozen:
    "Draw signed distance function `sdf`."

    def eye :DeepFrozen := V(8.0, 5.0, 7.0)
    def fov :Double := PI / 8
    def viewToWorld := viewMatrix(eye, zero, V(0.0, 1.0, 0.0))
    def rayDirection := makeRayDirection(fov)

    return def drawable.drawAt(u :Double, var v :Double,
                               => aspectRatio :Double,
                               => pixelRadius :Double):
        # NB: Flip vertical axis.
        v := 1.0 - v
        # Take our central ray, and also take four rays at edges of the pixel;
        # we'll need them for estimating partial derivatives later.
        def worldDir := viewToWorld(rayDirection(u, v, aspectRatio))
        def worldDirPX := viewToWorld(rayDirection(u + pixelRadius, v, aspectRatio))
        def worldDirNX := viewToWorld(rayDirection(u - pixelRadius, v, aspectRatio))
        def worldDirPY := viewToWorld(rayDirection(u, v + pixelRadius, aspectRatio))
        def worldDirNY := viewToWorld(rayDirection(u, v - pixelRadius, aspectRatio))

        def [estimate, steps, error, texture] := shortestDistanceToSurface(sdf, eye,
                                                                           worldDir,
                                                                           maxDepth,
                                                                           pixelRadius)
        # Clearly show where there is nothing.
        if (estimate >= maxDepth) { return makeColor.clear() }
        # XXX refineEstimate() could compute coverage-to-alpha information by
        # returning the error.
        # def distance := refineEstimate(sdf, eye, worldDir, estimate,
        #                                pixelRadius)
        def distance := if (steps >= maxSteps) {
            # Clearly show where we aren't taking enough steps by highlighting
            # with magenta.
            return makeColor.RGB(1.0, 0.0, 1.0, 1.0)
            # Refine the estimate using Newton's method; maybe it's alright.
            refineEstimate(sdf, eye, worldDir, estimate, pixelRadius)
        } else { estimate }

        # traceln(`hit u=$u v=$v estimate=$estimate distance=$distance steps=$steps`)

        # The actual location of the hit after traveling the distance.
        def p := eye + worldDir * distance
        # The normal at the point of intersection. Note that, since the
        # intersection is approximate, the normal is also approximate.
        def N := estimateNormal(sdf, p)
        # The depth at the point of intersection, with 0 at the camera and 1
        # at the back wall implied by maxDepth.
        def Z := zero * (distance / maxDepth)
        # The partial derivatives in screen space at the point of
        # intersection.
        def glance := distance * glsl.dot(worldDir, N)
        def dx := (worldDirPX / glsl.dot(worldDirPX, N) -
                   worldDirNX / glsl.dot(worldDirNX, N)) * glance
        def dy := (worldDirPY / glsl.dot(worldDirPY, N) -
                   worldDirNY / glsl.dot(worldDirNY, N)) * glance
        # The amount of the pixel which the object occludes, in [0,1].
        def coverage := ((pixelRadius - error) / pixelRadius) ** 2

        def lights := [
            # Behind the camera, a spotlight.
            (eye + one) => one * 0.5,
            # From the right, a fill.
            V(13.0, 10.0, -5.0) => one * 0.5,
            # From the left, another fill.
            V(-8.0, 10.0, 10.0) => one * 0.5,
            # From far above, a gentle ambient light.
            V(-100.0, 1_000.0, 100.0) => one * 0.2,
        ]
        # The color of the SDF at the distance. This is a function of
        # illuminating the SDF with each light.
        var color := texture.ambient(p, N, Z, dx, dy)
        for light => lightColor in (lights):
            # Let's find out how much this light contributes when pointed at
            # the known intersection point. The maximum distance to travel is
            # to just within a hair of the hit, to avoid acne.
            def v := p - light
            def lightEnd := glsl.length(v) - 0.000_000_1
            def [lightDistance, _, lightError, _] := shortestDistanceToSurface(sdf,
                light, glsl.normalize(v), maxDepth, pixelRadius)
            # Only compute textures if the light isn't occluded; this means
            # that the distance is not less than what we expected.
            if (lightDistance < lightEnd) { continue }

            def intensity := ((pixelRadius - lightError) / pixelRadius) ** 2
            # Shadow sharpness; [2,128].
            def shadowK := 2.0
            def soft := (intensity * shadowK).min(1.0)
            color += texture(eye, light, p, N, Z, dx, dy) * lightColor * soft

        # HDR: We wait until the last moment to clamp, but we *do* clamp.
        # Also, coverage to alpha! We'll preunmultiply here.
        def [r, g, b] := _makeList.fromIterable((color / coverage).min(1.0))
        return makeColor.RGB(r, g, b, coverage)

# That's it for the code which uses SDFs. Now, for the code which compiles
# SDFs from CSG descriptions.

def frac(x) as DeepFrozen:
    return x - x.floor()

def mod(x :Double, y :Double) :Double as DeepFrozen:
    return x - y * (x / y).floor()

# XXX common code not yet factored to lib/vectors
def productTimes(x, y) as DeepFrozen { return x * y }
def productDouble :DeepFrozen := V.makeFold(1.0, productTimes)

object expandCSG as DeepFrozen:
    "Expand Cube constructors into Boxes."

    to Cube(x :Double, material):
        return CSG.Box(x, x, x, material)

    match [constructor, args, namedArgs]:
        M.call(CSG, constructor, args, namedArgs)

# See https://iquilezles.org/www/articles/distfunctions/distfunctions.htm for
# many implementation examples, as well as other primitives not listed here.
# http://mercury.sexy/hg_sdf/ is another possible source of implementations.

def asSDF(entropy) as DeepFrozen:
    "Compile a CSG expression to its corresponding SDF."

    return object compileSDF:
        to Color(red, green, blue):
            def color := V(red, green, blue)
            return fn _p, _N, _Z, _dx, _dy { color }

        to Normal():
            # Convert the normal, which is in [-1, 1], to be in [0, 1].
            return fn _p, N, _Z, _dx, _dy { N * 0.5 + 0.5 }

        to Depth():
            return fn _p, _N, Z, _dx, _dy { Z }

        to Gradient():
            return fn _p, _N, _Z, dx, dy {
                (V(max(dx.abs()), max(dy.abs()), 0.0) * 4.0).min(1.0).max(0.0)
            }

        to Checker():
            # https://www.iquilezles.org/www/articles/filterableprocedurals/filterableprocedurals.htm
            # XXX improved filter could be used from
            # https://www.iquilezles.org/www/articles/morecheckerfiltering/morecheckerfiltering.htm
            return fn p, _N, _Z, dx, dy {
                def fwidth := dx.abs().max(dy.abs()) * 0.5
                def i := ((frac((p - fwidth) * 0.5) - 0.5).abs() -
                          (frac((p + fwidth) * 0.5) - 0.5).abs()) / fwidth
                one * 0.5 * (1.0 - productDouble(i))
            }

        to Marble(red, green, blue):
            # XXX noise can be filtered using derivatives; I couldn't get it
            # to look right, though?
            def exponents := V(red, green, blue)
            def noise := makeSimplexNoise(entropy)
            def half := one * 0.5
            return fn p, _N, _Z, dx, dy {
                def [_, _, z] := V.un(p, null)
                def n := noise.turbulence(p, 7) * 10.0
                def grey := (z * 0.5 + n).sine()
                # Scale from [-1,1] to [0,1].
                def scaled := half * (grey + 1.0)
                (one * scaled) ** exponents
            }

        to Lambert(flat, ambient):
            # https://en.wikipedia.org/wiki/Lambertian_reflectance
            return object lambertShader {
                to ambient(p, N, Z, dx, dy) { return ambient(p, N, Z, dx, dy) }
                to run(_eye, light, p, N, Z, dx, dy) {
                    def L := glsl.normalize(light - p)
                    def diff := glsl.dot(L, N)
                    return if (diff.belowZero()) { zero } else {
                        flat(p, N, Z, dx, dy) * diff
                    }
                }
            }

        to Phong(specular, diffuse, ambient, shininess):
            # https://en.wikipedia.org/wiki/Phong_reflection_model
            return object phongShader {
                to ambient(p, N, Z, dx, dy) { return ambient(p, N, Z, dx, dy) }
                to run(eye, light, p, N, Z, dx, dy) {
                    def L := glsl.normalize(light - p)
                    def diff := glsl.dot(L, N)

                    return if (diff.belowZero()) { zero } else {
                        def ks := specular(p, N, Z, dx, dy)
                        def kd := diffuse(p, N, Z, dx, dy)
                        def R := glsl.normalize(glsl.reflect(-L, N))
                        def base := glsl.dot(R, glsl.normalize(eye - p))
                        def spec := if (base.belowZero()) { 0.0 } else {
                            ks * base ** shininess
                        }
                        kd * diff + ks * spec
                    }
                }
            }

        to Sphere(radius :Double, material):
            return fn p { [glsl.length(p) - radius, material] }

        to Box(height :Double, width :Double, depth :Double, material):
            def b := V(height, width, depth)
            return fn p {
                def q := p.abs() - b
                [glsl.length(q.max(0.0)) + max(q).min(0.0), material]
            }

        to Cylinder(height :Double, radius :Double, material):
            return fn p {
                def [px, py, pz] := V.un(p, null)
                def dx := px.euclidean(pz) - radius
                def dy := py.abs() - height
                [dx.max(dy).min(0.0) + dx.max(0.0).euclidean(dy.max(0.0)), material]
            }

        to Cone(radius :Double, height :Double, material):
            def norm :Double := height.euclidean(radius)
            def mantleDirection := V(height, radius) / norm
            def projectedDirection := V(radius, -height) / norm
            return fn p {
                def [px, py, pz] := V.un(p, null)
                def pnorm := px.euclidean(pz)
                def q := V(pnorm, py)
                def tip := V(pnorm, py - height)
                def mantle := glsl.dot(tip, mantleDirection)
                var d := mantle.max(-py)
                def projected := glsl.dot(tip, projectedDirection)
                # Distance to tip.
                if (py > height && projected.belowZero()) {
                    d max= (glsl.length(tip))
                }
                # Distance to base ring.
                if (pnorm > radius && projected > norm) {
                    d max= (py.euclidean(pnorm - radius))
                }
                [d, material]
            }

        to InfiniteCylindricalCross(cx :Double, cy :Double, cz :Double,
                                    material):
            "
            The cross of infinite cylinders centered at the origin and with radius `c`
            in each axis.
            "

            return fn p {
                def [px, py, pz] := V.un(p, null)
                [(px.euclidean(py) - cz).min(
                  py.euclidean(pz) - cx).min(
                  pz.euclidean(px) - cy), material]
            }

        to Translation(shape, dx :Double, dy :Double, dz :Double):
            def offset := V(dx, dy, dz)
            return fn p { shape(p - offset) }

        to Rotation(shape, ur :Double, ui :Double, uj :Double, uk :Double):
            # https://en.wikipedia.org/wiki/Quaternions_and_spatial_rotation#Quaternion-derived_rotation_matrix
            # XXX wrong!?
            def R := V(
                V(1 - 2 * (uj * uj + uk * uk), 2 * (ui * uj - uk * ur), 2 * (ui * uk + uj * ur)),
                V(2 * (ui * uj + uk * ur), 1 - 2 * (ui * ui + uk * uk), 2 * (uj * uk - ui * ur)),
                V(2 * (ui * uk - uj * ur), 2 * (uj * uk + ui * ur), 1 - 2 * (ui * ui + uj * uj)),
            )
            traceln(`Rotation($ur, $ui, $uj, $uk) -> $R`)
            return fn p { shape(sumRow(R * p)) }

        to Scaling(shape, factor :Double):
            return fn p {
                def [d, material] := shape(p / factor)
                [d * factor, material]
            }

        to Displacement(shape, displacement, scale :Double):
            # return fn p {
            #     def [d, mat] := shape(p)
            #     [d + displacement(p) * scale, mat]
            # }
            # Optimization: Since the shape is not displaced by more than
            # [-scale, scale], consider queries which would be further away
            # than that:
            #
            # 8< - - - - -)  K          D  <         |         >
            # camera      p  kappa  delta  scale   shape   -scale
            #
            # If shape(p) - scale is positive, then computing displacement(p)
            # would be a waste. We'll lie to try to avoid that waste. We set
            # two constants, delta and kappa. Above kappa, we hide the
            # displacement; below it, we will be honest. While we are hiding,
            # we appear to have extra padding delta.
            def delta := scale * 1.000_1
            # Some trigonometry and estimates suggest that kappa needs to be
            # fairly large compared to delta, and indeed we otherwise get
            # artifacts for glancing blows.
            def kappa := scale * 2.0
            return fn p {
                def [x, m] := shape(p)
                def rv := if (x > kappa) { x - delta } else { x + displacement(p) * scale }
                [rv, m]
            }

        to OrthorhombicClamp(shape, c :Double, lx :Double, ly :Double,
                             lz :Double):
            def l := V(lx, ly, lz)
            def rc := c.reciprocal()
            return fn p {
                shape(p - ((p * rc) + 0.5).floor().asDouble().max(-l).min(l) * c)
            }

        to OrthorhombicCrystal(shape, cx :Double, cy :Double, cz :Double):
            def c := V(cx, cy, cz)
            def half := c * 0.5
            return fn p { shape(glsl.mod(p + half, c) - half) }

        to CubicMirror(shape):
            return fn p {
                def [px, py, pz] := V.un(p.abs(), null).sort()
                # Prefer the y-up sextant.
                shape(V(px, pz, py))
            }

        to Intersection(shape, shapes :List):
            return fn p {
                var rv := shape(p)
                for s in (shapes) {
                    def c := s(p)
                    if (c[0] > rv[0]) { rv := c }
                }
                rv
            }

        to Union(shape, shapes :List):
            return fn p {
                var rv := shape(p)
                for s in (shapes) {
                    def c := s(p)
                    if (c[0] < rv[0]) { rv := c }
                }
                rv
            }

        to Difference(minuend, subtrahend):
            return fn p {
                def m := minuend(p)
                def [var sp, sm] := subtrahend(p)
                sp := -sp
                if (m[0] > sp) { m } else { [sp, sm] }
            }

        # The displacement operators are on the same domain as SDFs, but they
        # return values in [-1, 1]. We will rely on this property!

        to Sines(lx :Double, ly :Double, lz :Double):
            def l := V(lx, ly, lz)
            # Since each sine wave is in [-1, 1], the sum is in [-3, 3].
            def scale :Double := 3.0.reciprocal()
            return fn p { sumDouble((p * l).sine()) * scale }

        to Noise(lx :Double, ly :Double, lz :Double, octaves :Int):
            def l := V(lx, ly, lz)
            def noise := makeSimplexNoise(entropy)
            return fn p { noise.turbulence(p * l, octaves) }

        to Dimples(lx :Double, ly :Double, lz :Double):
            def l := V(lx, ly, lz)
            def noise := makeSimplexNoise(entropy)
            return fn p { noise.noise(p * l).abs() * 2.0 - 1.0 }

# Use the normal to show the gradient.
def debugNormal :DeepFrozen := CSG.Lambert(CSG.Normal(), CSG.Color(0.1, 0.1, 0.1))
# Use the gradient to show the gradient.
def debugGradient :DeepFrozen := CSG.Lambert(CSG.Gradient(), CSG.Color(0.1, 0.1, 0.1))
# http://devernay.free.fr/cours/opengl/materials.html
# A basic rubber material. Note that, unlike Kilgard's rubber, we put the
# color in the diffuse component instead of specular; rubber *does* absorb
# pigmentation and is naturally white.
def rubber(color) as DeepFrozen:
    return CSG.Phong(
        CSG.Color(0.4, 0.4, 0.4),
        color,
        CSG.Color(0.1, 0.1, 0.1),
        10.0,
    )
def checker :DeepFrozen := CSG.Lambert(CSG.Checker(), CSG.Color(0.1, 0.1, 0.1))
def white :DeepFrozen := CSG.Color(1.0, 1.0, 1.0)
def green :DeepFrozen := CSG.Color(0.04, 0.7, 0.04)
def red :DeepFrozen := CSG.Color(0.7, 0.04, 0.04)
def emerald :DeepFrozen := CSG.Phong(
    CSG.Color(0.633, 0.727811, 0.633),
    CSG.Color(0.07568, 0.61424, 0.07568),
    CSG.Color(0.0215, 0.1745, 0.0215),
    76.8,
)
def jade :DeepFrozen := CSG.Phong(
    CSG.Color(0.316228, 0.316228, 0.316228),
    CSG.Color(0.54, 0.89, 0.63),
    CSG.Color(0.135, 0.2225, 0.1575),
    12.8,
)
# def ivory := makeMatte([0.6, 0.3, 0.1], V(0.4, 0.4, 0.3), 50.0)
def ivory :DeepFrozen := CSG.Phong(
    CSG.Color(0.3, 0.3, 0.3),
    CSG.Color(0.4, 0.4, 0.3),
    CSG.Color(0.1, 0.1, 0.1),
    50.0,
)
# def glass := makeGlassy(1.5, [0.0, 0.5, 0.1, 0.8], V(0.6, 0.7, 0.8), 125.0)
# XXX needs to be glassy
def glass :DeepFrozen := CSG.Phong(
    CSG.Color(0.5, 0.5, 0.5),
    CSG.Color(0.0, 0.0, 0.0),
    CSG.Color(0.1, 0.1, 0.1),
    125.0,
)
# def mirror := makeGlassy(1.0, [0.0, 10.0, 0.8, 0.0], V(1.0, 1.0, 1.0), 1425.0)
# XXX glassy
def mirror :DeepFrozen := CSG.Phong(
    CSG.Color(1.0, 1.0, 1.0),
    CSG.Color(0.0, 0.0, 0.0),
    CSG.Color(0.8, 0.8, 0.8),
    128.0,
)
# Improvised.
def iron :DeepFrozen := CSG.Phong(
    CSG.Color(0.7, 0.7, 0.7),
    CSG.Color(0.56, 0.57, 0.58),
    CSG.Color(0.1, 0.1, 0.1),
    25.0,
)

# Debugging spheres, good for testing shadows.
def boxes :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Sphere(1.0, debugNormal),
                                                 5.0, 5.0, 5.0)
# Sphere study.
# Effective marble should have the color throughout the stone, with a polished
# surface creating a shiny white layer.
def material := CSG.Phong(
    CSG.Color(0.8, 0.8, 0.8),
    CSG.Marble(2.0, 0.5, 2.0),
    CSG.Color(0.1, 0.1, 0.1), 75.0)
def study :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(100.0, checker), 0.0, -100.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0, material), 0.0, 2.0, 0.0),
])
# Holey beads in a lattice.
def crystal :DeepFrozen := CSG.OrthorhombicClamp(CSG.Difference(
    CSG.Intersection(CSG.Sphere(1.2, emerald),
                     [CSG.Cube(1.0, emerald)]),
    CSG.InfiniteCylindricalCross(0.5, 0.5, 0.5, emerald),
), 3.0, 3.0, 5.0, 4.0)
# Imitation tinykaboom.
def kaboom :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0, debugNormal),
    CSG.Noise(3.4, 3.4, 3.4, 5), 3.0)
# More imitation tinykaboom, but deterministic and faster.
def sines :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0, jade),
    CSG.Sines(5.0, 5.0, 5.0), 3.0)
# tinyraytracer.
def tinytracer :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(100.0, rubber(green)), 0.0, -110.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0, ivory), -7.0, 0.0, -12.0),
    CSG.Translation(CSG.Sphere(2.0, glass), -4.0, -1.5, -9.0),
    CSG.Translation(CSG.Sphere(3.0, rubber(red)), -1.5, -0.5, -15.0),
    CSG.Translation(CSG.Sphere(4.0, mirror), -11.0, 5.0, -11.0),
])
# A morningstar.
def fortyFive :Double := 2.0.squareRoot().reciprocal()
def morningstar :DeepFrozen := {
    # We're going to apply displacement to the entire iron structure, to give
    # it a hammered look.
    def ironBall := CSG.Sphere(2.0, iron)
    def spikedBall := CSG.Union(ironBall, [
        CSG.CubicMirror(CSG.Cone(0.75, 4.0, iron)),
    ])
    def entireIron := CSG.Union(CSG.Box(0.3, 0.3, 5.0, iron), [
        CSG.Translation(spikedBall, 0.0, 0.0, 4.0),
    ])
    def hammered := CSG.Displacement(entireIron, CSG.Dimples(2.0, 2.0, 2.0), 0.02)
    CSG.Translation(CSG.Union(hammered, [
        CSG.Translation(CSG.Sphere(0.7, rubber(CSG.Color(0.7, 0.7, 0.5))), 0.0, 0.0, -5.0),
    ]), 0.0, 0.0, -2.0)
}

object costOfConfig as DeepFrozen:
    to Center():
        return 1

    to Quincunx():
        return 5

    to QuasirandomMonteCarlo(count :Int):
        return count

    to TTest(sampler, quality :Double, minimumCount :Int, maximumCount :Int):
        # q% of the time, we'll be unsatisfied with the typical pixel. But
        # the typical pixel will be typical most of the time. Using an old
        # statistics rule of thumb for normal distributions, "most" is 2/3.
        return 3 * sampler * (quality * maximumCount + (1.0 - quality) * minimumCount).floor()

object costOfSolid as DeepFrozen:
    to Color(_, _, _):
        return 1

    to Normal():
        return 1

    to Depth():
        return 1

    to Gradient():
        return 1

    to Checker():
        return 1

    to Marble(_, _, _):
        return 2

    to Lambert(flat, ambient):
        return flat + ambient + 1

    to Phong(specular, diffuse, ambient, _):
        return specular + diffuse + ambient + 1

    to Sphere(_, material):
        return material + 2

    to Box(_, _, _, material):
        return material + 3

    to Cylinder(_, _, material):
        return material + 1

    to Cone(_, _, material):
        return material + 3

    to InfiniteCylindricalCross(_, _, _, material):
        return material + 3

    to Translation(shape, _, _, _):
        return shape + 1

    to Rotation(shape, _, _, _, _):
        return shape + 1

    to Scaling(shape, _):
        return shape + 2

    to Displacement(shape, displacement, _):
        return shape + displacement + 1

    to OrthorhombicClamp(shape, _, _, _, _):
        return shape + 18

    to OrthorhombicCrystal(shape, _, _, _):
        return shape + 9

    to CubicMirror(shape):
        return shape + 1

    to Intersection(shape, shapes :List):
        var rv := shape + 1
        for s in (shapes) { rv += s }
        return rv

    to Union(shape, shapes :List):
        var rv := shape + 1
        for s in (shapes) { rv += s }
        return rv

    to Difference(minuend, subtrahend):
        return minuend + subtrahend + 1

    to Sines(_, _, _):
        return 1

    to Noise(_, _, _, octaves :Int):
        return octaves * 3

    to Dimples(_, _, _):
        return 3

def traceToPNG(Timer, entropy, width :Int, height :Int, solid) as DeepFrozen:
    traceln(`Tracing solid: $solid`)
    traceln(`Cost: ${solid(costOfSolid)}`)
    # NB: We only need entropy to seed the SDF's noise; we don't need to
    # continually take random numbers while drawing. This is an infelicity in
    # lib/noise's API.
    def sdf := solid(asSDF(entropy))
    def drawable := drawSignedDistanceFunction(sdf)
    # def config := samplerConfig.QuasirandomMonteCarlo(3)
    def config := samplerConfig.Center()
    def cost := config(costOfConfig) * solid(costOfSolid) * width * height * maxSteps
    def drawer := makePNG.drawingFrom(drawable, config)(width, height)
    var i := 0
    def start := Timer.unsafeNow()
    while (true):
        i += 1
        if (i % 2000 == 0):
            def duration := Timer.unsafeNow() - start
            def pixelsPerSecond := i / duration
            def timeRemaining := ((width * height) - i) / pixelsPerSecond
            def normPixels := (pixelsPerSecond * cost).logarithm()
            traceln(`Status: ${(i * 100) / (width * height)}% ($pixelsPerSecond px/s) ($normPixels work/s) (${timeRemaining}s left)`)
        drawer.next(__break)
    return drawer.finish()

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def solid := sines(expandCSG)
    def w := 640
    def h := 360
    def png := traceToPNG(Timer, entropy, w, h, solid)
    return when (makeFileResource("sdf.png")<-setContents(png)) -> { 0 }
