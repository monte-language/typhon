import "fun/ppm" =~ [=> makePPM]
import "lib/colors" =~ [=> makeColor]
import "lib/samplers" =~ [=> samplerConfig]
import "lib/vectors" =~ [=> V, => glsl]
exports (main, render, makeSphere, spheres, lights)

# https://github.com/ssloy/tinyraytracer/wiki/Part-1:-understandable-raytracing

# We'll need some trigonometric tools.

# By definition. This is one of two useful ways to extract the platform's
# underlying value for pi. (And yes, I've hand-checked that this is as
# accurate as hard-coding it.)
def PI :Double := 0.0.arcCosine() * 2

def perturb(point, N, dir) as DeepFrozen:
    def eps := N * (1e-3 * glsl.dot(dir, N).belowZero().pick(-1.0, 1.0))
    return point + eps

# "Classes" for our various "types" of object.

def makeGlassy(refractiveIndex :Double,
               [diffuseAlbedo :Double, specularAlbedo :Double,
                reflectiveAlbedo :Double, refractiveAlbedo :Double],
               diffuseColor :DeepFrozen,
               specularExponent :Double) as DeepFrozen:
    return object material as DeepFrozen:
        to refract(I, N):
            # Check the direction of the refraction, and flip if necessary.
            return if (glsl.dot(I, N).belowZero()) {
                glsl.refract(I, -N, refractiveIndex)
            } else { glsl.refract(I, N, refractiveIndex.reciprocal()) }

        to shade(diffuseLightIntensity :Double,
                 specularLightIntensity, reflectColor, refractColor):
            return (diffuseColor * (diffuseLightIntensity * diffuseAlbedo) +
                 specularLightIntensity * specularAlbedo +
                 reflectColor * reflectiveAlbedo +
                 refractColor * refractiveAlbedo)

        to specularExponent():
            return specularExponent

def makeMatte([diffuseAlbedo :Double, specularAlbedo :Double,
               reflectiveAlbedo :Double],
              diffuseColor :DeepFrozen,
              specularExponent :Double) as DeepFrozen:
    return object material as DeepFrozen:
        to refract(_I, _N):
            return null

        to shade(diffuseLightIntensity :Double,
                 specularLightIntensity, reflectColor, _refractColor):
            return (diffuseColor * (diffuseLightIntensity * diffuseAlbedo) +
                 specularLightIntensity * specularAlbedo +
                 reflectColor * reflectiveAlbedo)

        to specularExponent():
            return specularExponent


def makeLight(position :DeepFrozen, intensity :Double) as DeepFrozen:
    # https://en.wikipedia.org/wiki/Phong_reflection_model#Description
    # N is our unit normal at the point
    # v is our unit vector from the point to the camera
    return object light as DeepFrozen:
        to shadow(point, N):
            def offset := position - point
            def lightDistance := glsl.length(offset)
            # NB: Lm := unit(position - point)
            def Lm := offset * lightDistance.reciprocal()
            def shadowOrigin := perturb(point, N, -Lm)
            return [shadowOrigin, Lm, lightDistance]

        to illuminate(v, point, N, exp):
            # Lm is our unit vector from the point to the light
            def Lm := glsl.normalize(position - point)
            def diff := intensity * glsl.dot(Lm, N).max(0.0)
            # Rm is our unit vector physically reflected from the point
            def Rm := glsl.reflect(-Lm, N)
            # NB: Because we allow very large specular exponents, we may
            # overflow here. In this case, we'll use a large but fixed
            # specular value.
            def spec := try {
                intensity * glsl.dot(Rm, v).max(0.0) ** exp
            } catch _ { 2.0 ** 1000 }
            return [diff, spec]

def makeSphere(center :DeepFrozen, radius :(Double > 0.0),
               material :DeepFrozen) as DeepFrozen:
    def r2 :Double := radius * radius
    return object sphere as DeepFrozen:
        to material():
            return material

        to normal(v):
            return glsl.normalize(v - center)

        to rayIntersect(orig, dir):
            def L := center - orig
            def tca := glsl.dot(L, dir)
            def d2 := glsl.dot(L, L) - tca * tca
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
def zero :DeepFrozen := V(0.0, 0.0, 0.0)

def castRay(orig, dir, spheres, lights, => depth := 0) as DeepFrozen:
    # traceln(`castRay($orig, $dir, "depth" => $depth)`)
    if (depth > 5) { return sky }

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

        def reflectDir := glsl.reflect(dir, N)
        def reflectOrig := perturb(hit, N, reflectDir)
        def reflectColor := castRay(reflectOrig, reflectDir, spheres, lights,
                                    "depth" => depth + 1)

        def refractColor := {
            def refractDir := mat.refract(dir, N)
            if (refractDir != null) {
                def refractOrig := perturb(hit, N, refractDir)
                castRay(refractOrig, refractDir, spheres, lights,
                        "depth" => depth + 1)
            } else { zero }
        }

        # traceln(`hit $hit N $N reflect $reflectColor refract $refractColor`)

        var diffuse := 0.0
        var specular := zero
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
            # traceln(`illuminate exp $exp diffuse $d specular $s`)
            diffuse += d
            specular += s
        }
        def color := mat.shade(diffuse, specular, reflectColor, refractColor)
        # traceln(`diffuse $diffuse specular $specular color $color`)
        color
    }

def ORIGIN :DeepFrozen := zero

def fov :Double := (PI / 6).tangent()

def render(spheres, lights) as DeepFrozen:
    return def draw.drawAt(x :Double, y :Double, => aspectRatio :Double := 1.0):
        def xr := (x - 0.5) * 2.0 * fov * aspectRatio
        # NB: Flip vertical.
        def yr := (0.5 - y) * 2.0 * fov
        def rgb := castRay(ORIGIN, glsl.normalize(V(xr, yr, -1.0)), spheres, lights)
        # NB: min() to clamp away HDR.
        def [r, g, b] := _makeList.fromIterable(rgb.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def spheres() as DeepFrozen:
    def ivory := makeMatte([0.6, 0.3, 0.1], V(0.4, 0.4, 0.3), 50.0)
    def glass := makeGlassy(1.5, [0.0, 0.5, 0.1, 0.8], V(0.6, 0.7, 0.8), 125.0)
    def redRubber := makeMatte([0.9, 0.1, 0.0], V(0.3, 0.1, 0.1), 10.0)
    def greenRubber := makeMatte([0.9, 0.1, 0.0], V(0.3, 0.9, 0.3), 10.0)
    # NB: This specular exponent is quite large. GL traditionally caps
    # the specular exponent at 128.0.
    def mirror := makeGlassy(1.0, [0.0, 10.0, 0.8, 0.0], V(1.0, 1.0, 1.0), 1425.0)
    return [
        makeSphere(V(-3.0, 0.0, -16.0), 2.0, ivory),
        makeSphere(V(-1.0, -1.5, -12.0), 2.0, glass),
        makeSphere(V(1.5, -0.5, -18.0), 3.0, redRubber),
        makeSphere(V(7.0, 5.0, -18.0), 4.0, mirror),
        makeSphere(V(0.0, -110.0, 0.0), 100.0, greenRubber),
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
    def ss := spheres()
    def ls := lights()
    traceln(`Spheres: $ss`)
    traceln(`Lights: $ls`)
    def drawable := render(ss, ls)
    # drawable.drawAt(0.5, 0.5, "aspectRatio" => 1.618, "pixelRadius" => 0.000_020)
    # throw("yay?")
    def config := samplerConfig.Center()
    def drawer := makePPM.drawingFrom(drawable, config)(w, h)
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
