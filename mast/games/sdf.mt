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

def makeSphere(radius :Double) as DeepFrozen:
    return def sphere(p) as DeepFrozen:
        return norm(p) - radius

def makeBox(b :DeepFrozen) as DeepFrozen:
    return def box(p) as DeepFrozen:
        def q := p.abs() - b
        return norm(q.max(0.0)) + max(q).min(0.0)

def makeCube(length :Double) as DeepFrozen:
    return makeBox(one * length)

def translate(sdf :DeepFrozen, offset :DeepFrozen) as DeepFrozen:
    return def translated(p) as DeepFrozen { return sdf(p - offset) }

def scale(sdf :DeepFrozen, scale :Double) as DeepFrozen:
    return def scaled(p) as DeepFrozen { return sdf(p / scale) * scale }

def intersect(l :DeepFrozen, r :DeepFrozen) as DeepFrozen:
    return def intersected(p) as DeepFrozen { return l(p).max(r(p)) }

def union(l :DeepFrozen, r :DeepFrozen) as DeepFrozen:
    return def unioned(p) as DeepFrozen { return l(p).min(r(p)) }

def difference(l :DeepFrozen, r :DeepFrozen) as DeepFrozen:
    return def subtracted(p) as DeepFrozen { return l(p).max(-(r(p))) }

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

def shortestDistanceToSurface(sdf, eye, direction, start :Double,
                              end :Double) :Double as DeepFrozen:
    var depth := start
    for _ in (0..!maxSteps):
        def step := eye + direction * depth
        def distance := sdf(step)
        # traceln(`sdf($eye, $direction, $depth) -> sdf($step) -> $distance`)
        if (distance < epsilon):
            return depth
        depth += distance
        if (depth >= end):
            break
    return end

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

def drawSignedDistanceFunction(sdf) as DeepFrozen:
    def viewToWorld := viewMatrix(eye, one * 0.0, V(0.0, 1.0, 0.0))

    return def drawable.drawAt(u :Double, v :Double, => aspectRatio :Double):
        # NB: Flip vertical axis.
        def viewDir := rayDirection(fov, u, 1.0 - v, aspectRatio)
        def worldDir := viewToWorld(viewDir)

        def distance := shortestDistanceToSurface(sdf, eye, worldDir, 0.0,
                                                  100.0)
        if (distance >= 100.0) { return makeColor.clear() }
        # traceln(`hit $u $v $distance`)

        def p := eye + worldDir * distance
        def ka := (estimateNormal(sdf, p) * 0.5) + 0.5
        def kd := one * 0.5
        def ks := one
        def shininess := 10.0

        def color := phongIllumination(sdf, ka, kd, ks, shininess, p, eye)
        # HDR: We wait until the last moment to clamp, but we *do* clamp.
        def [r, g, b] := _makeList.fromIterable(color.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def cylinder(c :DeepFrozen) as DeepFrozen:
    "
    The cross of infinite cylinders centered at the origin and with radius `c`
    in each axis.
    "

    def [cx :Double, cy :Double, cz :Double] := V.un(c, null)
    return def cyl(p) as DeepFrozen:
        def [px, py, pz] := V.un(p, null)
        return (px.euclidean(py) - cz).min(
            py.euclidean(pz) - cx).min(
            pz.euclidean(px) - cy)

def repeat(sdf :DeepFrozen, c :DeepFrozen) as DeepFrozen:
    "Repeat `sdf` over orthorhombic lattice `c`."

    def half :DeepFrozen := c * 0.5
    return def repeated(p) as DeepFrozen:
        return sdf(mod(p + half, c) - half)

def sdf :DeepFrozen := repeat(difference(
    intersect(makeSphere(1.2), makeCube(1.0)),
    cylinder(one * 0.5),
), V(3.0, 5.0, 4.0))
# translate(makeSphere(10_000.0), V(0.0, -10_000.0, 0.0))

def main(_argv, => makeFileResource, => Timer) as DeepFrozen:
    # def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def w := 320
    def h := 180
    def drawable := drawSignedDistanceFunction(sdf)
    def drawer := makePPM.drawingFrom(drawable)(w, h)
    # drawable.drawAt(0.0, 0.0, "aspectRatio" => 1.0)
    # drawable.drawAt(0.5, 0.5, "aspectRatio" => 1.0)
    # drawable.drawAt(1.0, 1.0, "aspectRatio" => 1.0)
    # throw("hmm")
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
