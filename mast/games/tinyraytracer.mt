import "fun/ppm" =~ [=> makePPM]
import "lib/colors" =~ [=> makeColor]
import "lib/vectors" =~ [=> V]
exports (main, render, makeSphere, spheres, lights)

# https://github.com/ssloy/tinyraytracer/wiki/Part-1:-understandable-raytracing

# We'll need some trigonometric tools.

# By definition. This is one of two useful ways to extract the platform's
# underlying value for pi. (And yes, I've hand-checked that this is as
# accurate as hard-coding it.)
def PI :Double := 0.0.arcCosine() * 2

# XXX common code with games/sdf
def sumPlus(x, y) as DeepFrozen { return x + y }
def sumDouble :DeepFrozen := V.makeFold(0.0, sumPlus)

def dot(u, v) as DeepFrozen:
    return sumDouble(u * v)

def norm(v) as DeepFrozen:
    def u := sumDouble(v ** 2).squareRoot()
    return v * u.reciprocal()

def unitVector(source, dest) as DeepFrozen:
    "The unit vector pointing from `source` towards `dest`."
    def delta := dest - source
    return norm(delta)

def reflect(I, N) as DeepFrozen:
    def d := 2.0 * dot(I, N)
    return N * d - I

def perturb(point, N, dir) as DeepFrozen:
    def eps := N * 1e-3
    return if (dot(dir, N).belowZero()) {
        point - eps
    } else { point + eps }

# "Classes" for our various "types" of object.

def makeMaterial(refractiveIndex :Double,
                 [diffuseAlbedo :Double, specularAlbedo :Double,
                  reflectiveAlbedo :Double, refractiveAlbedo :Double],
                 diffuseColor :DeepFrozen,
                 specularExponent :Double) as DeepFrozen:
    return object material as DeepFrozen:
        to refract(I, var N):
            var cosi := dot(I, N).min(1.0).max(-1.0)
            def eta := if (cosi.belowZero()) {
                N := -N
                cosi := -cosi
                refractiveIndex
            } else {
                1 / refractiveIndex
            }
            def k := 1 - eta * eta * (1 - cosi * cosi)
            return if (k.atLeastZero()) {
                I * eta + N * (eta * cosi - k.squareRoot())
            }

        to shade(diffuseLightIntensity, specularLightIntensity, reflectColor,
                 refractColor):
            def spec := specularLightIntensity * specularAlbedo
            return (diffuseColor * diffuseLightIntensity * diffuseAlbedo +
                 spec +
                 reflectColor * reflectiveAlbedo +
                 refractColor * refractiveAlbedo)

        to specularExponent():
            return specularExponent

def makeLight(position :DeepFrozen, intensity :Double) as DeepFrozen:
    # https://en.wikipedia.org/wiki/Phong_reflection_model#Description
    # N is our unit normal at the point
    # v is our unit vector from the point to the camera
    return object light as DeepFrozen:
        to shadow(point, N):
            def Lm := unitVector(position, point)
            def lightDistance := norm(position - point)
            def eps := N * 1e-3
            def shadowOrigin := perturb(point, N, Lm)
            return [shadowOrigin, unitVector(point, position), lightDistance]

        to illuminate(v, point, N, exp):
            # Lm is our unit vector from the point to the light
            def Lm := unitVector(position, point)
            # Rm is our unit vector physically reflected from the point
            def Rm := reflect(Lm, N)
            def diff := intensity * dot(Lm, N).max(0.0)
            def spec := intensity * dot(Rm, v).max(0.0) ** exp
            return [diff, spec]

def makeSphere(center :DeepFrozen, radius :(Double > 0.0),
               material :DeepFrozen) as DeepFrozen:
    def r2 :Double := radius * radius
    return object sphere as DeepFrozen:
        to material():
            return material

        to normal(v):
            return unitVector(center, v)

        to rayIntersect(orig, dir):
            def L := center - orig
            def tca := dot(L, dir)
            def d2 := dot(L, L) - tca * tca
            # We need to try to take a square root, so we need this quantity to be
            # positive.
            def thcs := r2 - d2
            if (thcs.belowZero()) { return [false, null] }
            def thc := thcs.squareRoot()
            return if (thc < tca) {
                [true, thc - tca]
            } else if (thc < -tca) {
                [true, thc + tca]
            } else { [false, null] }

def sky :DeepFrozen := V(0.2, 0.7, 0.8)

def castRay(orig, dir, spheres, lights, => depth := 0) as DeepFrozen:
    if (depth > 4) { return sky }

    var spheresDist := Infinity
    var best := null
    for sphere in (spheres):
        def [intersects, dist] := sphere.rayIntersect(orig, dir)
        if (intersects && dist < spheresDist):
            spheresDist := dist
            best := sphere
    return if (best == null) { sky } else {
        def mat := best.material()
        def exp := mat.specularExponent()
        def hit := orig + dir * spheresDist
        def N := best.normal(hit)

        def reflectDir := reflect(dir, N)
        def reflectOrig := perturb(hit, N, reflectDir)
        def reflectColor := castRay(reflectOrig, reflectDir, spheres, lights,
                                    "depth" => depth + 1)

        def refractColor := {
            def refractDir := mat.refract(dir, N)
            if (refractDir == null) { V(0.0, 0.0, 0.0) } else {
                def refractOrig := perturb(hit, N, refractDir)
                castRay(refractOrig, refractDir, spheres, lights,
                        "depth" => depth + 1)
            }
        }

        var diffuse := 0.0
        var specular := 0.0
        for light in (lights) {
            # Checking if the point lies in the shadow of this light.
            # Construct a new origin and consider whether we run into any
            # spheres while trying to trace a ray back to this light.
            def [shadowOrigin, lightDir, lightDistance] := light.shadow(hit, N)

            def skipThisLight := __continue
            for sphere in (spheres) {
                def [intersects, dist] := sphere.rayIntersect(shadowOrigin, lightDir)
                if (intersects && dist < lightDistance) { skipThisLight() }
            }

            # Accumulate this light.
            def [d, s] := light.illuminate(dir, hit, N, exp)
            diffuse += d
            specular += s
        }
        mat.shade(diffuse, specular, reflectColor, refractColor)
    }

def ORIGIN :DeepFrozen := V(0.0, 0.0, 0.0)

def fov :Double := (PI / 6).tangent()

def render(spheres, lights) as DeepFrozen:
    return def draw.drawAt(x :Double, y :Double, => aspectRatio :Double := 1.0):
        def xr := (x - 0.5) * 2.0 * fov * aspectRatio
        def yr := (y - 0.5) * 2.0 * fov
        def rgb := castRay(ORIGIN, norm(V(xr, yr, -1.0)), spheres, lights)
        # NB: min() to clamp away HDR.
        def [r, g, b] := _makeList.fromIterable(rgb.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def spheres() as DeepFrozen:
    def ivory := makeMaterial(1.0, [0.6, 0.3, 0.1, 0.0], V(0.4, 0.4, 0.3), 50.0)
    def glass := makeMaterial(1.5, [0.0, 0.5, 0.1, 0.8], V(0.6, 0.7, 0.8), 125.0)
    def redRubber := makeMaterial(1.0, [0.9, 0.1, 0.0, 0.0], V(0.3, 0.1, 0.1), 10.0)
    # NB: GL traditionally caps specular exponent at 128.0
    def mirror := makeMaterial(1.0, [0.0, 10.0, 0.8, 0.0], V(1.0, 1.0, 1.0), 1425.0)
    return [
        makeSphere(V(-3.0, 0.0, -16.0), 2.0, ivory),
        makeSphere(V(-1.0, -1.5, -12.0), 2.0, glass),
        makeSphere(V(1.5, -0.5, -18.0), 3.0, redRubber),
        makeSphere(V(7.0, 5.0, -18.0), 4.0, mirror),
    ]

def lights() as DeepFrozen:
    return [
        makeLight(V(-20.0, 20.0, 20.0), 1.5),
        makeLight(V(30.0, 50.0, -25.0), 1.8),
        makeLight(V(30.0, 20.0, 30.0), 1.7),
    ]

def main(_argv, => makeFileResource, => Timer) as DeepFrozen:
    def w := 320
    def h := 180
    def drawable := render(spheres(), lights())
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
    return when (makeFileResource("tiny.ppm")<-setContents(ppm)) -> { 0 }
