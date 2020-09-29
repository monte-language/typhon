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
      | InfiniteCylindricalCross(double xradius, double yradius, double zradius,
                                 material)
      | Translation(solid shape, double dx, double dy, double dz)
      | Scaling(solid shape, double factor)
      | Displacement(solid shape, displacement d, double amplitude)
      | OrthorhombicClamp(solid repetend, double period, double width,
                          double height, double depth)
      | OrthorhombicCrystal(solid repetend, double width, double height,
                            double depth)
      | Intersection(solid shape, solid* shapes)
      | Union(solid shape, solid* shapes)
      | Difference(solid minuend, solid subtrahend)
displacement = Sines(double lx, double ly, double lz)
             | Noise(double lx, double ly, double lz, int octaves)
material = Lambert(color flat, color ambient)
         | Phong(color specular, color diffuse, color ambient,
                 double shininess)
color = Color(double red, double green, double blue)
      | Normal
      | Gradient
      | Checker
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

def anyOr(x, y) as DeepFrozen { return x || y }
def any :DeepFrozen := V.makeFold(false, anyOr)

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

def shortestDistanceToSurface(sdf, eye, direction, start :Double,
                              end :Double, pixelRadius :Double) as DeepFrozen:
    var depth := start
    # Track signs, based on where we've started.
    # XXX Typhon should give Doubles a method for checking the sign bit!
    def sign := sdf(eye)[0].belowZero().pick(-1.0, 1.0)
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
            return [depth, i, texture]

        # We can and should leave as soon as the first hit happens which is
        # close enough to reasonably occlude the pixel.
        # NB: In the paper's original algorithm, there's some additional
        # machinery for checking candidate values, but we go with either the
        # first hit or nothing.
        def error := signedDistance.abs() / depth
        # traceln(`$i: error $error, threshold $pixelRadius`)
        if (error < pixelRadius):
            return [depth, i, texture]

        # No hits.
        if (depth >= end):
            return [end, i, null]

        depth += signedDistance

    # No hits.
    return [end, maxSteps, null]

def hardShadow(sdf, light, direction, end :Double) :Double as DeepFrozen:
    "How much `sdf` contributes to self-occlusion of `light` from `direction`."

    # https://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
    # Very much like computing hits, but with a penumbra instead of a pixel
    # radius. So, if confused, review the standard hit computation first.

    var depth := 0.0
    for _ in (0..!maxSteps):
        if (depth >= end):
            break
        def [distance, _] := sdf(light + direction * depth)
        if (distance < 0.000_000_1):
            return 0.0
        depth += distance
    return 1.0

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

def maxDepth :Double := 20.0

# Do a couple rounds of gradient descent in order to polish an estimated hit.
# This works about as well as you might expect: After two rounds, the hit is
# accurate to 1 in 1 million, and three rounds is almost always enough.
# The error comes from:
# https://static.aminer.org/pdf/PDF/000/593/434/efficient_antialiased_rendering_of_d_linear_fractals.pdf
# But it is just the pixel area over the distance traveled!
def refineEstimate(sdf, eye, dir, distance :Double, pixelRadius :Double) as DeepFrozen:
    def pixelArea := PI * pixelRadius ** 2
    var t := distance
    var err := Infinity
    for _i in (0..!3):
        def newErr := sdf(eye + dir * t)[0] - pixelArea / t
        # It is quite possible that we're not improving the estimate; that is,
        # that we are numerically unstable near a divergent fixed point. If
        # that's the case, then give up to avoid making things worse.
        if (newErr.abs() > err.abs()) { break }
        # traceln(`refine $i: sdf($eye + $dir * $t) -> $newErr`)
        err := newErr
        t += err
    return t

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

        def [estimate, steps, texture] := shortestDistanceToSurface(sdf, eye,
                                                                    worldDir,
                                                                    0.0,
                                                                    maxDepth,
                                                                    pixelRadius)
        # Clearly show where we aren't taking enough steps by highlighting
        # with magenta.
        if (steps >= maxSteps) { return makeColor.RGB(1.0, 0.0, 1.0, 1.0) }
        # Clearly show where there is nothing.
        if (estimate >= maxDepth) { return makeColor.clear() }

        def distance := refineEstimate(sdf, eye, worldDir, estimate,
                                       pixelRadius)
        # traceln(`hit u=$u v=$v estimate=$estimate distance=$distance steps=$steps`)

        # The actual location of the hit after traveling the distance.
        def p := eye + worldDir * distance
        # The normal at the point of intersection. Note that, since the
        # intersection is approximate, the normal is also approximate.
        def N := estimateNormal(sdf, p)
        # The partial derivatives in screen space at the point of
        # intersection.
        def glance := distance * glsl.dot(worldDir, N)
        def dx := (worldDirPX / glsl.dot(worldDirPX, N) -
                   worldDirNX / glsl.dot(worldDirNX, N)) * glance
        def dy := (worldDirPY / glsl.dot(worldDirPY, N) -
                   worldDirNY / glsl.dot(worldDirNY, N)) * glance

        def lights := [
            # Behind the camera, a spotlight.
            (eye + one) => one * 0.4,
            # From the right, a fill.
            V(13.0, 10.0, -5.0) => one * 0.4,
            # From the left, another fill.
            V(-8.0, 10.0, 10.0) => one * 0.4,
            # From far above, a gentle ambient light.
            V(-100.0, 1_000.0, 100.0) => one * 0.1,
        ]
        # The color of the SDF at the distance. This is a function of
        # illuminating the SDF with each light.
        var color := texture.ambient(p, N, dx, dy)
        for light => lightColor in (lights):
            # Let's find out how much this light contributes when pointed at
            # the known intersection point. The maximum distance to travel is
            # to just within a hair of the hit, to avoid acne.
            def v := p - light
            def intensity := hardShadow(sdf, light, glsl.normalize(v),
                                        glsl.length(v) - 0.000_000_1)
            # The light might be blocked entirely; only compute materials if
            # the point isn't in shade.
            if (intensity.aboveZero()):
                color += texture(eye, light, p, N, dx, dy) * lightColor * intensity

        # HDR: We wait until the last moment to clamp, but we *do* clamp.
        def [r, g, b] := _makeList.fromIterable(color.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def frac(x) as DeepFrozen:
    return x - x.floor()

def mod(x :Double, y :Double) :Double as DeepFrozen:
    return x - y * (x / y).floor()

# XXX common code not yet factored to lib/vectors
def productTimes(x, y) as DeepFrozen { return x * y }
def productDouble :DeepFrozen := V.makeFold(1.0, productTimes)

# See https://iquilezles.org/www/articles/distfunctions/distfunctions.htm for
# many implementation examples, as well as other primitives not listed here.
# http://mercury.sexy/hg_sdf/ is another possible source of implementations.

def asSDF(entropy) as DeepFrozen:
    "Compile a CSG expression to its corresponding SDF."

    return object compileSDF:
        to Color(red, green, blue):
            def color := V(red, green, blue)
            return fn _p, _N, _dx, _dy { color }

        to Normal():
            # Convert the normal, which is in [-1, 1], to be in [0, 1].
            return fn _p, N, _dx, _dy { N * 0.5 + 0.5 }

        to Gradient():
            return fn _p, _N, dx, dy {
                (V(max(dx.abs()), max(dy.abs()), 0.0) * 4.0).min(1.0).max(0.0)
            }

        to Checker():
            # https://www.iquilezles.org/www/articles/filterableprocedurals/filterableprocedurals.htm
            # XXX improved filter could be used from
            # https://www.iquilezles.org/www/articles/morecheckerfiltering/morecheckerfiltering.htm
            return fn p, _N, dx, dy {
                def fwidth := dx.abs().max(dy.abs()) * 0.5
                def i := ((frac((p - fwidth) * 0.5) - 0.5).abs() -
                          (frac((p + fwidth) * 0.5) - 0.5).abs()) / fwidth
                one * 0.5 * (1.0 - productDouble(i))
            }

        to Lambert(flat, ambient):
            # https://en.wikipedia.org/wiki/Lambertian_reflectance
            return object lambertShader {
                to ambient(p, N, dx, dy) { return ambient(p, N, dx, dy) }
                to run(_eye, light, p, N, dx, dy) {
                    def L := glsl.normalize(light - p)
                    def diff := glsl.dot(L, N)
                    return if (diff.belowZero()) { zero } else {
                        flat(p, N, dx, dy) * diff
                    }
                }
            }

        to Phong(specular, diffuse, ambient, shininess):
            # https://en.wikipedia.org/wiki/Phong_reflection_model
            return object phongShader {
                to ambient(p, N, dx, dy) { return ambient(p, N, dx, dy) }
                to run(eye, light, p, N, dx, dy) {
                    def L := glsl.normalize(light - p)
                    def diff := glsl.dot(L, N)

                    return if (diff.belowZero()) { zero } else {
                        def ks := specular(p, N, dx, dy)
                        def kd := diffuse(p, N, dx, dy)
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

        to Cube(length :Double, material):
            return compileSDF.Box(length, length, length, material)

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

        to Scaling(shape, factor :Double):
            return fn p { shape(p / factor) * factor }

        to Displacement(shape, displacement, scale :Double):
            # return fn p { shape(p) + displacement(p) * scale }
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
            def kappa := scale * 1.5
            return fn p {
                def x := shape(p)
                if (x > kappa) { x - delta } else { x + displacement(p) * scale }
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
def green :DeepFrozen := CSG.Color(0.04, 0.7, 0.04)
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

# Debugging spheres, good for testing shadows.
def boxes :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Sphere(1.0, debugNormal),
                                                 5.0, 5.0, 5.0)
# Sphere study.
def material := CSG.Lambert(CSG.Checker(), CSG.Color(0.1, 0.1, 0.1))
def study :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(10_000.0, checker), 0.0, -10_000.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0, debugGradient), 0.0, 2.0, 0.0),
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
def sines :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0, debugNormal),
    CSG.Sines(5.0, 5.0, 5.0), 3.0)
def solid :DeepFrozen := study
traceln(`Defined solid: $solid`)

def formatBucket([size :Int, count :Int]) :Str as DeepFrozen:
    var d := size.asDouble()
    for s in (["", "Ki", "Mi", "Gi", "Ti", "Pi"]):
        if (d < 256.0):
            return `$count objects ($d ${s}B)`
        d /= 1024.0

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def w := 320
    def h := 180
    # NB: We only need entropy to seed the SDF's noise; we don't need to
    # continually take random numbers while drawing. This is an infelicity in
    # lib/noise's API.
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def sdf := solid(asSDF(entropy))
    def drawable := drawSignedDistanceFunction(sdf)
    # def config := samplerConfig.QuasirandomMonteCarlo(5)
    def config := samplerConfig.Center()
    def drawer := makePNG.drawingFrom(drawable, config)(w, h)
    var i := 0
    def start := Timer.unsafeNow()
    while (true):
        i += 1
        if (i % 500 == 0):
            def duration := Timer.unsafeNow() - start
            def pixelsPerSecond := i / duration
            def timeRemaining := ((w * h) - i) / pixelsPerSecond
            traceln(`Status: ${(i * 100) / (w * h)}% ($pixelsPerSecond px/s) (${timeRemaining}s left)`)
            # def buckets := currentRuntime.getHeapStatistics().getBuckets()
            # def finalSlots := formatBucket(buckets["FinalSlot"])
            # def varSlots := formatBucket(buckets["VarSlot"])
            # traceln(`Memory: FinalSlot $finalSlots VarSlot $varSlots`)
        drawer.next(__break)
    def png := drawer.finish()
    return when (makeFileResource("sdf.png")<-setContents(png)) -> { 0 }
