import "lib/colors" =~ [=> makeColor]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "fun/ppm" =~ [=> makePPM]
exports (main)

# https://www.realtimerendering.com/raytracing/Ray%20Tracing%20in%20a%20Weekend.pdf

object makeV3 as DeepFrozen:
    to un(specimen, ej):
        def [==makeV3, =="run", args, _] exit ej := specimen._uncall()
        return args

    to run(x :Double, y :Double, z :Double):
        return object vec3 as DeepFrozen:
            to _uncall():
                return [makeV3, "run", [x, y, z], [].asMap()]

            to x():
                return x

            to y():
                return y

            to z():
                return z

            to asColor():
                return makeColor.sRGB(x, y, z, 1.0)

            to norm() :Double:
                return x ** 2 + y ** 2 + z ** 2

            to unit():
                def k := vec3.norm().squareRoot().reciprocal()
                return vec3 * k

            to sum():
                return x + y + z

            to dot(other):
                return (vec3 * other).sum()

            to cross(via (makeV3.un) [ox, oy, oz]):
                return makeV3(
                    y * oz - z * oy,
                    z * ox - x * oz,
                    x * oy - y * ox,
                )

            # Vector operations.
            match [verb, [via (makeV3.un) [p, q, r]], namedArgs]:
                makeV3(
                    M.call(x, verb, [p], namedArgs),
                    M.call(y, verb, [q], namedArgs),
                    M.call(z, verb, [r], namedArgs),
                )

            # Scalar operations.
            match message:
                makeV3(
                    M.callWithMessage(x, message),
                    M.callWithMessage(y, message),
                    M.callWithMessage(z, message),
                )

def zero :DeepFrozen := makeV3(0.0, 0.0, 0.0)
def one :DeepFrozen := makeV3(1.0, 1.0, 1.0)

def makeSphere(center :DeepFrozen, radius :Double, material) as DeepFrozen:
    return def sphere.hit(ray, tMin :Double, tMax :Double, ej):
        def origin := ray.origin()
        def direction := ray.direction()
        def oc := origin - center
        def a := direction.dot(direction)
        def b := 2.0 * oc.dot(direction)
        def c := oc.dot(oc) - radius ** 2
        def discriminant := b ** 2 - 4.0 * a * c
        if (discriminant < 0):
            throw.eject(ej, "no roots")
        var t := (-b - discriminant.squareRoot()) / (2.0 * a)
        if (t > tMax || t < tMin):
            t := (-b + discriminant.squareRoot()) / (2.0 * a)
        if (t > tMax || t < tMin):
            throw.eject(ej, "no hit in range")
        # Point from origin along direction by amount t.
        def p := ray.pointAtParameter(t)
        return [t, p, ((center - p) / -radius).unit(), material]

def makeMovingSphere(startCenter, stopCenter, startTime :Double,
                     stopTime :Double, radius :Double, material) as DeepFrozen:
    def pathCenter := stopCenter - startCenter
    def duration := stopTime - startTime
    return def movingSphere.hit(ray, tMin :Double, tMax :Double, ej):
        def center := startCenter + pathCenter * ((ray.time() - startTime) / duration)
        return makeSphere(center, radius, material).hit(ray, tMin, tMax, ej)

def makeHittables(hs :List) as DeepFrozen:
    return def hittables.hit(ray, tMin :Double, tMax :Double, ej):
        var rv := null
        var closestSoFar := tMax
        for h in (hs):
            def [t, _, _, _] := rv := h.hit(ray, tMin, closestSoFar,
                                            __continue)
            closestSoFar := t
        if (rv == null):
            throw.eject(ej, "no hits")
        return rv

def makeRay(origin, direction, time :Double) as DeepFrozen:
    return object ray:
        to origin():
            return origin

        to direction():
            return direction

        to time():
            return time

        to pointAtParameter(t :Double):
            return origin + direction * t

def makeLambertian(entropy, albedo :DeepFrozen) as DeepFrozen:
    return def lambertian.scatter(ray, p, N, _ej):
        def [rx, ry, rz] := entropy.nextBall(3)
        def target := (N + makeV3(rx, ry, rz)).unit()
        return [makeRay(p, target, ray.time()), albedo]

def reflect(v, n) as DeepFrozen:
    def uv := v.unit()
    return uv - n * (2.0 * uv.dot(n))

def makeMetal(entropy, albedo :DeepFrozen, fuzz :(Double <= 1.0)) as DeepFrozen:
    return def metal.scatter(ray, p, N, ej):
        def reflected := reflect(ray.direction().unit(), N)
        if (reflected.dot(N).belowZero()) { throw.eject(ej, "absorbed?") }
        def [fx, fy, fz] := entropy.nextBall(3)
        def fuzzed := reflected + makeV3(fx, fy, fz) * fuzz
        return [makeRay(p, fuzzed, ray.time()), albedo]

def refract(v, n, coeff :Double, ej) as DeepFrozen:
    def uv := v.unit()
    def dt := uv.dot(n)
    def discriminant := 1.0 - coeff ** 2 * (1.0 - dt ** 2)
    if (discriminant.atMostZero()) { throw.eject(ej, "internally reflected") }
    return (uv - n * dt) * coeff - n * discriminant.squareRoot()

# https://en.wikipedia.org/wiki/Schlick%27s_approximation
def schlick(cosine :Double, refractiveIndex :Double) :Double as DeepFrozen:
    def r0 := ((1.0 - refractiveIndex) / (1.0 + refractiveIndex)) ** 2
    return r0 + (1.0 - r0) * (1.0 - cosine) ** 5

def makeDielectric(entropy, refractiveIndex :Double) as DeepFrozen:
    # NB: The original deliberately destroys the blue channel, but I don't see
    # why that should be done.
    def attenuation :DeepFrozen := makeV3(1.0, 1.0, 1.0)
    return def dielectric.scatter(ray, p, N, _ej):
        def direction := ray.direction()
        def prod := direction.unit().dot(N)
        def [outwardNormal, coeff, cosine] := if (prod > 0) {
            [-N, refractiveIndex, refractiveIndex * prod]
        } else {
            [N, refractiveIndex.reciprocal(), -prod]
        }
        return escape internal {
            def refracted := refract(direction, outwardNormal, coeff,
                                     internal)
            def reflectProb := schlick(cosine / direction.norm(),
                                       refractiveIndex)
            if (entropy.nextDouble() < reflectProb) {
                [makeRay(p, refracted, ray.time()), attenuation]
            } else { internal() }
        } catch _ {
            [makeRay(p, reflect(direction, N), ray.time()), attenuation]
        }

def blueSky :DeepFrozen := makeV3(0.5, 0.7, 1.0)

def color(entropy, ray, world, depth) as DeepFrozen:
    def direction := ray.direction()
    return escape miss:
        # Set minimum t in order to avoid shadow acne.
        def [_, p, N, mat] := world.hit(ray, 1.0e-5, Infinity, miss)
        escape absorbed:
            def [scattered, attenuation] := mat.scatter(ray, p, N, absorbed)
            if (depth < 50) {
                attenuation * color(entropy, scattered, world, depth + 1)
            } else { zero }
        catch _:
            zero
    catch _:
        def t := 0.5 * (direction.unit().y() + 1.0)
        blueSky * t + one * (1.0 - t)

def makeCamera(entropy, lookFrom, lookAt, up, vfov :Double, aspect :Double,
               aperture :Double, focusDist :Double, startTime :Double,
               stopTime :Double) as DeepFrozen:
    def lensRadius := aperture / 2.0
    # Convert from angles to radians.
    def theta := vfov * 0.0.arcCosine() / 90.0
    def halfHeight := (theta / 2.0).tangent()
    def halfWidth := halfHeight * aspect
    def w := (lookFrom - lookAt).unit()
    def u := up.cross(w).unit()
    def v := w.cross(u)
    def lowerLeft := lookFrom - (
        (u * halfWidth + v * halfHeight + w) * focusDist)
    def horizontal := u * (2.0 * halfWidth * focusDist)
    def vertical := v * (2.0 * halfHeight * focusDist)
    def duration := stopTime - startTime

    return def camera.getRay(u :Double, v :Double):
        def [rx, ry] := entropy.nextBall(2)
        def offset := u * rx + v * ry
        def time := startTime + entropy.nextDouble() * duration
        def origin := lookFrom + offset * lensRadius
        def direction := lowerLeft + horizontal * u + vertical * v - origin
        return makeRay(origin, direction, time)

def randomScene(entropy) as DeepFrozen:
    def rand := entropy.nextDouble
    def rv := [
        makeSphere(makeV3(0.0, -10_000.0, 0.0), 10_000.0,
                   makeLambertian(entropy, makeV3(0.5, 0.5, 0.5))),
        makeSphere(makeV3(0.0, 1.0, 0.0), 1.0,
                   makeDielectric(entropy, 1.5)),
        makeSphere(makeV3(-4.0, 1.0, 0.0), 1.0,
                   makeLambertian(entropy, makeV3(0.4, 0.2, 0.1))),
        makeSphere(makeV3(4.0, 1.0, 0.0), 1.0,
                   makeMetal(entropy, makeV3(0.7, 0.6, 0.5), 0.0)),
    ].diverge()
    # XXX limited for speed, is originally -11..11
    def region := -2..2
    for a in (region):
        for b in (region):
            def chooseMat := rand()
            def center := makeV3(a + 0.9 * rand(), 0.2,
                                 b + 0.9 * rand())
            if ((center - makeV3(4.0, 0.0, 2.0)).norm() <= 0.9) { continue }
            def material := if (chooseMat < 0.8) {
                makeLambertian(entropy,
                               makeV3(rand() * rand(), rand() * rand(),
                                      rand() * rand()))
            } else if (chooseMat < 0.95) {
                makeMetal(entropy,
                          makeV3(0.5 * (1.0 + rand()), 0.5 * (1.0 + rand()),
                                 0.5 * (1.0 + rand())),
                          0.5 * rand())
            } else { makeDielectric(entropy, 1.5) }
            def jitter := makeV3(0.0, entropy.nextDouble(), 0.0)
            rv.push(makeMovingSphere(center, center + jitter, 0.0, 1.0, 0.2,
                                     material))
    return makeHittables(rv.snapshot())

# NB: Runtime increases linearly with this number.
def subsamples :Int := 12

def makeDrawable(entropy, aspectRatio) as DeepFrozen:
    # Which way is up? This way.
    def up := makeV3(0.0, 1.0, 0.0)

    # What are we looking at?
    def lookAt := makeV3(4.0, 0.0, 1.0)

    def world := randomScene(entropy)

    def lookFrom := makeV3(6.0, 1.0, 2.0)
    def distToFocus := (lookFrom - lookAt).norm()
    # NB: Aspect ratio is fixed, and we ignore the requested ratio.
    def camera := makeCamera(entropy, lookFrom, lookAt, up, 90.0, aspectRatio,
                             1.0, distToFocus, 0.0, 1.0)
    return def drawable.drawAt(u :Double, var v :Double):
        # Rendering is upside-down WRT Monte conventions.
        v := 1.0 - v
        var rv := zero
        for _ in (0..!subsamples):
            # Important: These must be two uncorrelated random offsets.
            def du := u + (entropy.nextDouble() / 1_000.0)
            def dv := v + (entropy.nextDouble() / 1_000.0)
            def ray := camera.getRay(du, dv)
            rv += color(entropy, ray, world, 0)
        return (rv / subsamples).asColor()

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def w := 160
    def h := 120
    def drawable := makeDrawable(entropy, w / h)
    def t := Timer.measureTimeTaken(fn { drawable.drawAt(0.5, 0.5) })
    return when (t) ->
        def [_, d] := t
        traceln(`Time per fragment: ${d * 1000} milliseconds (${d * w * h} seconds total)`)
        def ppm := makePPM.drawingFrom(drawable)(w, h)
        when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
