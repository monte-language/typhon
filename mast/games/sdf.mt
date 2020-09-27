import "lib/asdl" =~ [=> buildASDLModule]
import "lib/colors" =~ [=> makeColor]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/samplers" =~ [=> samplerConfig]
import "lib/vectors" =~ [=> V, => glsl]
import "fun/png" =~ [=> makePNG]
exports (main)

def ["ASTBuilder" => CSG :DeepFrozen] | _ := eval(buildASDLModule(`
solid = Sphere(double radius)
      | Box(double width, double height, double depth)
      | Cube(double length)
      | InfiniteCylindricalCross(double xradius, double yradius, double zradius)
      | Translation(solid shape, double dx, double dy, double dz)
      | Scaling(solid shape, double factor)
      | Displacement(solid shape, displacement d, double amplitude)
      | OrthorhombicCrystal(solid repetend, double width, double height, double depth)
      | Intersection(solid shape, solid* shapes)
      | Union(solid shape, solid* shapes)
      | Difference(solid minuend, solid subtrahend)
displacement = Sines(double lx, double ly, double lz)
             | Noise(double lx, double ly, double lz, int octaves)
material = Phong(color specular, color diffuse, color ambient,
                 double shininess)
color = Color(double red, double green, double blue)
      | Normal
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
        sdf(p + epsilonX * scale) - sdf(p - epsilonX * scale),
        sdf(p + epsilonY * scale) - sdf(p - epsilonY * scale),
        sdf(p + epsilonZ * scale) - sdf(p - epsilonZ * scale),
    ))

def maxSteps :Int := 100

def shortestDistanceToSurface(sdf, eye, direction, start :Double,
                              end :Double, pixelRadius :Double) as DeepFrozen:
    var depth := start
    # Track signs, based on where we've started.
    # XXX Typhon should give Doubles a method for checking the sign bit!
    def sign := sdf(eye).belowZero().pick(-1.0, 1.0)
    for i in (0..!maxSteps):
        def step := eye + direction * depth
        def signedDistance := sdf(step) * sign
        # traceln(`$i: sdf($eye, $direction, $depth) -> sdf($step) -> $signedDistance`)

        # If we took a step and ended up inside the geometry, but we took the
        # step size based on the geometry's SDF, then we must conclude that
        # there is numerical instability inside the SDF. This happens all the
        # time; it's not wrong or weird, but it does mean that this guess was
        # actually extremely good and we should treat the remaining negative
        # offset as numerical error.
        if (signedDistance.belowZero()):
            return [depth, i]

        # We can and should leave as soon as the first hit happens which is
        # close enough to reasonably occlude the pixel.
        # NB: In the paper's original algorithm, there's some additional
        # machinery for checking candidate values, but we go with either the
        # first hit or nothing.
        def error := signedDistance.abs() / depth
        # traceln(`$i: error $error, threshold $pixelRadius`)
        if (error < pixelRadius):
            return [depth, i]

        # No hits.
        if (depth >= end):
            return [end, i]

        depth += signedDistance

    # No hits.
    return [end, maxSteps]

def hardShadow(sdf, light, direction, start :Double, end :Double) :Double as DeepFrozen:
    "How much `sdf` contributes to self-occlusion of `light` from `direction`."

    # https://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
    # Very much like computing hits, but with a penumbra instead of a pixel
    # radius. So, if confused, review the standard hit computation first.

    var depth := start
    for _ in (0..!maxSteps):
        if (depth >= end):
            break
        def distance := sdf(light + direction * depth)
        if (distance.atMostZero()):
            return 0.0
        depth += distance
    return 1.0

def softShadow(k :Double) as DeepFrozen:
    "
    Build a soft shadow finder.

    `k` controls fuzziness of the resulting penumbra. As `k` grows, the
    penumbra becomes asymptotically sharper; values over 100 are like hard
    shadows, while values below 2 are like parallel large sources of light.

    `k` cannot go to zero or infinity, but at zero, the light source is
    infinitely far, while at infinity, the light source is a nearby laser.
    "

    return def goSoftly(sdf, light, direction, start :Double, end :Double) :Double as DeepFrozen:
        # https://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
        # Similar to hard shadows, but with a fuzzy adjustment to the penumbra.

        var depth := start
        var shade := 1.0
        var ph := 1e20
        for _ in (0..!maxSteps):
            if (depth >= end):
                break

            def distance := sdf(light + direction * depth)

            # No sign tracking. As soon as we're negative, including immediately,
            # we'll bail with zero. Indeed, we actually have to bail out sooner
            # than that; too close to epsilon and we get numerical instability and
            # NaNs in the following square root.
            if (distance.atMostZero()):
                return 0.0

            # Aaltonen's technique: Search for darkest parts of the penumbra,
            # using the prior step to refine where to search.
            def hh := distance * distance
            def y := hh * 0.5 / ph
            # Numerical instability can cause this invariant to fail, in which
            # case we definitely intersected and are in full shade.
            if (y >= distance):
                return 0.0
            # Always safe because distance > y.
            def d := (hh - y * y).squareRoot()
            shade min= (k * d / 0.0.max(depth - y))
            # traceln("distance", distance, "depth", depth, "hh", hh, "y", y, "d",
            #         d, "shade", shade)

            ph := distance
            depth += distance

        # How fuzzy did we get?
        return shade

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
        def newErr := sdf(eye + dir * t) - pixelArea / t
        # It is quite possible that we're not improving the estimate; that is,
        # that we are numerically unstable near a divergent fixed point. If
        # that's the case, then give up to avoid making things worse.
        if (newErr.abs() > err.abs()) { break }
        # traceln(`refine $i: sdf($eye + $dir * $t) -> $newErr`)
        err := newErr
        t += err
    return t

def drawSignedDistanceFunction(sdf, tf) as DeepFrozen:
    "Draw signed distance function `sdf` with associated texture function `tf`."

    def eye :DeepFrozen := V(8.0, 5.0, 7.0)
    def fov :Double := PI / 8
    def viewToWorld := viewMatrix(eye, zero, V(0.0, 1.0, 0.0))
    def rayDirection := makeRayDirection(fov)

    return def drawable.drawAt(u :Double, v :Double, => aspectRatio :Double,
                               => pixelRadius :Double):
        # NB: Flip vertical axis.
        def viewDir := rayDirection(u, 1.0 - v, aspectRatio)
        def worldDir := viewToWorld(viewDir)

        def [estimate, steps] := shortestDistanceToSurface(sdf, eye, worldDir,
                                                           0.0, maxDepth,
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

        def lights := [
            # Behind the camera, a spotlight.
            (eye - one) => [one * 0.2, hardShadow],
            # From the front, a fill.
            V(20.0, 2.0, 2.0) => [one * 0.7, softShadow(4.0)],
            # From far above, a bright ambient light.
            V(-5.0, 100.0, -5.0) => [one, softShadow(2.0)],
        ]
        # The color of the SDF at the distance. This is a function of
        # illuminating the SDF with each light.
        var color := tf.ambient(p, N)
        for light => [lightColor, shadow] in (lights):
            # Let's find out how much this light contributes when pointed at
            # the known intersection point. The maximum distance to travel is
            # to just within a hair of the hit, to avoid acne.
            def v := p - light
            def intensity := shadow(sdf, light, glsl.normalize(v), 0.0,
                                    glsl.length(v) - 0.001)
            # The light might be blocked entirely; only compute materials if
            # the point isn't in shade.
            if (intensity.aboveZero()):
                color += tf(eye, light, p, N) * lightColor * intensity

        # HDR: We wait until the last moment to clamp, but we *do* clamp.
        def [r, g, b] := _makeList.fromIterable(color.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def asTF() as DeepFrozen:
    "Compile a CSG material to its corresponding texture function."

    # It would be nice if colors didn't need p and N, but they do. Indeed,
    # right now I've left p out, and just use N, but that won't do for proper
    # texturing later.

    return object compileTF:
        to Color(red, green, blue):
            def color := V(red, green, blue)
            return fn _N { color }

        to Normal():
            # Convert the normal, which is in [-1, 1], to be in [0, 1].
            return fn N { N * 0.5 + 0.5 }

        to Phong(specular, diffuse, ambient, shininess):
            # https://en.wikipedia.org/wiki/Phong_reflection_model
            return object phongShader {
                to ambient(p, N) {
                    # XXX ambient light is V(0.5, 0.5, 0.5)
                    return ambient(N) * 0.5
                }
                to run(eye, light, p, N) {
                    def L := glsl.normalize(light - p)
                    def diff := glsl.dot(L, N)

                    return if (diff.belowZero()) { zero } else {
                        def ks := specular(N)
                        def kd := diffuse(N)
                        def R := glsl.normalize(glsl.reflect(-L, N))
                        def base := glsl.dot(R, glsl.normalize(eye - p))
                        def spec := if (base.belowZero()) { 0.0 } else {
                            ks * base ** shininess
                        }
                        kd * diff + ks * spec
                    }
                }
            }

# See https://iquilezles.org/www/articles/distfunctions/distfunctions.htm for
# many implementation examples, as well as other primitives not listed here.
# http://mercury.sexy/hg_sdf/ is another possible source of implementations.

def asSDF(entropy) as DeepFrozen:
    "Compile a CSG expression to its corresponding SDF."

    return object compileSDF:
        to Sphere(radius :Double):
            return fn p { glsl.length(p) - radius }

        to Box(height :Double, width :Double, depth :Double):
            def b := V(height, width, depth)
            return fn p {
                def q := p.abs() - b
                glsl.length(q.max(0.0)) + max(q).min(0.0)
            }

        to Cube(length :Double):
            return compileSDF.Box(length, length, length)

        to InfiniteCylindricalCross(cx :Double, cy :Double, cz :Double):
            "
            The cross of infinite cylinders centered at the origin and with radius `c`
            in each axis.
            "

            return fn p {
                def [px, py, pz] := V.un(p, null)
                (px.euclidean(py) - cz).min(
                 py.euclidean(pz) - cx).min(
                 pz.euclidean(px) - cy)
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

        to OrthorhombicCrystal(shape, cx :Double, cy :Double, cz :Double):
            def c := V(cx, cy, cz)
            def half := c * 0.5
            return fn p { shape(glsl.mod(p + half, c) - half) }

        to Intersection(shape, shapes :List):
            return fn p {
                var rv := shape(p)
                for s in (shapes) { rv max= (s(p)) }
                rv
            }

        to Union(shape, shapes :List):
            return fn p {
                var rv := shape(p)
                for s in (shapes) { rv min= (s(p)) }
                rv
            }

        to Difference(minuend, subtrahend):
            return fn p { minuend(p).max(-(subtrahend(p))) }

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
def debugNormal :DeepFrozen := CSG.Phong(
    CSG.Color(0.1, 0.1, 0.1),
    CSG.Normal(),
    CSG.Normal(),
    10.0,
)
# A basic rubber material.
def rubber(color) as DeepFrozen:
    return CSG.Phong(
        CSG.Color(0.1, 0.1, 0.1),
        CSG.Color(0.9, 0.9, 0.9),
        color,
        10.0,
    )
def green :DeepFrozen := CSG.Color(0.3, 0.9, 0.3)
def material :DeepFrozen := rubber(green)
traceln(`Defined material: $material`)

# Debugging spheres, good for testing shadows.
def boxes :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Sphere(1.0), 5.0, 5.0, 5.0)
# Sphere study.
def study :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(10_000.0), 0.0, -10_000.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0), 0.0, 2.0, 0.0),
])
# Holey beads in a lattice.
def crystal :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Difference(
    CSG.Intersection(CSG.Sphere(1.2), [CSG.Cube(1.0)]),
    CSG.InfiniteCylindricalCross(0.5, 0.5, 0.5),
) , 3.0, 5.0, 4.0)
# Imitation tinykaboom.
def kaboom :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0),
    CSG.Noise(3.4, 3.4, 3.4, 5), 3.0)
# More imitation tinykaboom, but deterministic and faster.
def sines :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0),
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
    def tf := material(asTF())
    def drawable := drawSignedDistanceFunction(sdf, tf)
    # drawable.drawAt(0.5, 0.5, "aspectRatio" => 1.618, "pixelRadius" => 0.000_020)
    # drawable.drawAt(0.5, 0.45, "aspectRatio" => 1.618, "pixelRadius" => 0.000_020)
    # throw("yay?")
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
