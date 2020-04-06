import "games/csg" =~ ["ASTBuilder" => CSG]
import "lib/colors" =~ [=> makeColor]
import "lib/vectors" =~ [=> V]
import "fun/ppm" =~ [=> makePPM]
exports (main)

# http://jamie-wong.com/2016/07/15/ray-marching-signed-distance-functions/

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

def sumPlus(x, y) as DeepFrozen { return x + y }
def sumDouble :DeepFrozen := V.makeFold(0.0, sumPlus)
def sumRow :DeepFrozen := V.makeFold(one * 0.0, sumPlus)

def maxPlus(x, y) as DeepFrozen { return x.max(y) }
def max :DeepFrozen := V.makeFold(-Infinity, maxPlus)

def norm(v) as DeepFrozen:
    return sumDouble(v ** 2).squareRoot()

def unit(v) as DeepFrozen:
    return v * norm(v).reciprocal()

def dot(u, v) as DeepFrozen:
    return sumDouble(u * v)

# https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/mod.xhtml
def mod(x, y) as DeepFrozen:
    return x - y * (x / y).floor()

# https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/mix.xhtml
def mix(x, y, a :Double) as DeepFrozen:
    return x * (1.0 - a) + y * a

# https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/cross.xhtml
def cross(x, y) as DeepFrozen:
    def [x0, x1, x2] := V.un(x, null)
    def [y0, y1, y2] := V.un(y, null)
    return V(
        x1 * y2 - y1 * x2,
        x2 * y0 - y2 * x0,
        x0 * y1 - y0 * x1,
    )

# https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/reflect.xhtml
def reflect(I, N) as DeepFrozen:
    return I - N * (2.0 * dot(I, N))

def PI :Double := 1.0.arcSine() * 2

def epsilon :Double := 0.000_000_1

def maxSteps :Int := 100

def epsilonX :DeepFrozen := V(epsilon, 0.0, 0.0)
def epsilonY :DeepFrozen := V(0.0, epsilon, 0.0)
def epsilonZ :DeepFrozen := V(0.0, 0.0, epsilon)

def estimateNormal(sdf, p) as DeepFrozen:
    return unit(V(
        sdf(p + epsilonX) - sdf(p - epsilonX),
        sdf(p + epsilonY) - sdf(p - epsilonY),
        sdf(p + epsilonZ) - sdf(p - epsilonZ),
    ))

# https://en.wikipedia.org/wiki/Phong_reflection_model
def phongContribForLight(sdf, kd, ks, alpha :Double, p, eye, lightPos,
                         lightIntensity) as DeepFrozen:
    def N := estimateNormal(sdf, p)
    def L := unit(lightPos - p)
    def R := unit(reflect(-L, N))

    def diff := dot(L, N)

    if (diff.belowZero()):
        return V(0.0, 0.0, 0.0)

    def base := dot(R, unit(eye - p))
    def spec := if (base.belowZero()) { 0.0 } else { ks * base ** alpha }
    return lightIntensity * (kd * diff + ks * spec)

def fov :Double := (PI / 16).tangent()
def eye :DeepFrozen := V(8.0, 5.0, 7.0)

def phongIllumination(sdf, ka, kd, ks, alpha :Double, p, eye) as DeepFrozen:
    def ambientLight := V(0.5, 0.5, 0.5)
    var color := ambientLight * ka

    def lights := [
        V(0.0, 2.0, 4.0),
        V(-4.0, 2.0, 0.0),
        V(0.74, 0.0, 2.0),
        V(0.0, -0.74, 2.0),
        # Put a light behind the camera.
        eye - one,
    ]

    for pos in (lights):
        def intensity := V(0.4, 0.4, 0.4)
        def contribution := phongContribForLight(sdf, kd, ks, alpha, p, eye,
                                                 pos, intensity)
        color += contribution

    return color

# https://erleuchtet.org/~cupe/permanent/enhanced_sphere_tracing.pdf
# The over-relaxation logic is omitted because it provoked constant
# misrendering for only a 10% speedup. (I probably implemented it wrong.)
def shortestDistanceToSurface(sdf, eye, direction, start :Double,
                              end :Double, pixelRadius :Double) as DeepFrozen:
    var depth := start
    # Track signs, based on where we've started.
    def sign := sdf(eye).belowZero().pick(-1.0, 1.0)
    for i in (0..!maxSteps):
        def step := eye + direction * depth
        def signedDistance := sdf(step) * sign
        def distance := signedDistance.abs()
        # traceln(`$i: sdf($eye, $direction, $depth) -> sdf($step) -> $signedDistance`)

        # We can and should leave as soon as the first hit happens which is
        # close enough to reasonably occlude the pixel.
        # NB: In the paper's original algorithm, there's some additional
        # machinery for checking candidate values, but we go with either the
        # first hit or nothing.
        def error := distance / depth
        # traceln(`$i: error $error, threshold $pixelRadius`)
        if (error < pixelRadius):
            return [depth, i]

        # No hits.
        if (depth >= end):
            return [end, i]

        # Step and iterate.
        depth += signedDistance

    # No hits.
    return [end, maxSteps]

def rayDirection(fieldOfView :Double, u :Double, v :Double,
                 aspectRatio :Double) as DeepFrozen:
    def fovr := fieldOfView * 2.0
    def x := (u - 0.5) * fovr * aspectRatio
    def y := (v - 0.5) * fovr
    def rv := unit(V(x, y, -1.0))
    # traceln(`rayDirection($fieldOfView, $u, $v, $aspectRatio) -> $rv`)
    return rv

def viewMatrix(eye :DeepFrozen, center, up) as DeepFrozen:
    # https://www.khronos.org/registry/OpenGL-Refpages/gl2.1/xhtml/gluLookAt.xml
    def f :DeepFrozen := unit(center - eye)
    def s :DeepFrozen := unit(cross(f, up))
    def u :DeepFrozen := cross(s, f)
    # traceln(`viewMatrix($eye, $center, $up) -> $s $u ${-f}`)
    return def moveCamera(dir) as DeepFrozen:
        def rv := sumRow(V(s, u, -f) * dir)
        # traceln(`moveCamera($dir) -> $rv`)
        return rv

def maxDepth :Double := 50.0

# Do a couple rounds of gradient descent in order to polish an estimated hit.
# This works about as well as you might expect: After two rounds, the hit is
# accurate to 1 in 1 million, and three rounds is almost always enough.
# The error comes from:
# https://static.aminer.org/pdf/PDF/000/593/434/efficient_antialiased_rendering_of_d_linear_fractals.pdf
# But it is just the pixel area over the distance traveled!
def refineEstimate(sdf, eye, dir, distance :Double, pixelRadius :Double) as DeepFrozen:
    def pixelArea := PI * pixelRadius ** 2
    var t := distance
    for i in (0..!3):
        def f := sdf(eye + dir * t)
        # traceln(`$i: t $t f(t) $f`)
        t += f - pixelArea / t
    return t

# Super-sample towards the "corners" of the pixel, were it square. Since our
# output device has square-ish pixels, this will look better than doing just
# the axes.
def superSamplingOffsets :List[List[Double]] := [
    [0.0, 0.0],
    [1.0, 1.0],
    [-1.0, -1.0],
    [1.0, -1.0],
    [-1.0, 1.0],
]

def drawSignedDistanceFunction(sdf) as DeepFrozen:
    def viewToWorld := viewMatrix(eye, one * 0.0, V(0.0, 1.0, 0.0))

    return def drawable.drawAt(u :Double, v :Double, => aspectRatio :Double,
                               => pixelRadius :Double):
        var rv := one * 0.0
        var hits := 0
        for [du, dv] in (superSamplingOffsets):
            def x := u + du * pixelRadius
            # NB: Flip vertical axis.
            def y := (1.0 - v) + dv * pixelRadius
            def viewDir := rayDirection(fov, x, y, aspectRatio)
            def worldDir := viewToWorld(viewDir)

            def [estimate, steps] := shortestDistanceToSurface(sdf, eye, worldDir,
                                                               0.0, maxDepth,
                                                               pixelRadius)
            if (estimate >= maxDepth) { continue }

            def distance := refineEstimate(sdf, eye, worldDir, estimate,
                                           pixelRadius)
            # traceln(`hit $u $v $estimate $distance`)

            def p := eye + worldDir * distance
            # Shade ambient lighting with the normal, scaled up; this looks like
            # colored gels from the three axes.
            def ka := (estimateNormal(sdf, p) * 0.5) + 0.5
            def kd := one
            def ks := one
            def shininess := 10.0

            # Debugging: Shade diffuse material from white to magenta with the
            # number of steps taken; this makes material look pinker as it becomes
            # harder to estimate.
            # def color := mix(one, V(1.0, 0.0, 1.0), steps / maxSteps)
            def color := phongIllumination(sdf, ka, kd, ks, shininess, p, eye)

            rv += color
            hits += 1

        # HDR: We wait until the last moment to clamp, but we *do* clamp.
        def scale := superSamplingOffsets.size()
        def [r, g, b] := _makeList.fromIterable((rv / scale).min(1.0))
        # Coverage to alpha~
        return makeColor.RGB(r, g, b, hits / scale)

# See https://iquilezles.org/www/articles/distfunctions/distfunctions.htm for
# many implementation examples, as well as other primitives not listed here.
# http://mercury.sexy/hg_sdf/ is another possible source of implementations.

object asSDF as DeepFrozen:
    "Compile a CSG expression to its corresponding SDF."

    to Sphere(radius :Double):
        return fn p { norm(p) - radius }

    to Box(height :Double, width :Double, depth :Double):
        def b := V(height, width, depth)
        return fn p {
            def q := p.abs() - b
            norm(q.max(0.0)) + max(q).min(0.0)
        }

    to Cube(length :Double):
        return asSDF.Box(length, length, length)

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
        return fn p { shape(p) - offset }

    to Scaling(shape, factor :Double):
        return fn p { shape(p / factor) * factor }

    to OrthorhombicCrystal(shape, cx :Double, cy :Double, cz :Double):
        def c := V(cx, cy, cz)
        def half := c * 0.5
        return fn p { shape(mod(p + half, c) - half) }

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

def solid :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Difference(
    CSG.Intersection(CSG.Sphere(1.2), [CSG.Cube(1.0)]),
    CSG.InfiniteCylindricalCross(0.5, 0.5, 0.5),
) , 3.0, 5.0, 4.0)
traceln(`Defined solid: $solid`)

def main(_argv, => makeFileResource, => Timer) as DeepFrozen:
    def w := 320
    def h := 180
    def sdf := solid(asSDF)
    def drawable := drawSignedDistanceFunction(sdf)
    # drawable.drawAt(0.5, 0.5, "aspectRatio" => 1.618, "pixelRadius" => 0.000_020)
    # throw("yay?")
    def drawer := makePPM.drawingFrom(drawable)(w, h)
    var i := 0
    def start := Timer.unsafeNow()
    while (true):
        i += 1
        if (i % 500 == 0):
            def duration := Timer.unsafeNow() - start
            def pixelsPerSecond := i / duration
            def timeRemaining := ((w * h) - i) / pixelsPerSecond
            traceln(`Status: ${(i * 100) / (w * h)}% ($pixelsPerSecond px/s) (${timeRemaining}s left)`)
        drawer.next(__break)
    def ppm := drawer.finish()
    return when (makeFileResource("sdf.ppm")<-setContents(ppm)) -> { 0 }
