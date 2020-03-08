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

def origin :DeepFrozen := zero
def lowerLeft :DeepFrozen := makeV3(-2.0, -1.0, -1.0)
def horizontal :DeepFrozen := makeV3(4.0, 0.0, 0.0)
def vertical :DeepFrozen := makeV3(0.0, 2.0, 0.0)

def makeSphere(center :DeepFrozen, radius :Double, material) as DeepFrozen:
    return def sphere.hit(origin, direction, tMin :Double, tMax :Double, ej):
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
        def p := origin + direction * t
        return [t, p, ((center - p) / -radius).unit(), material]

def makeHittables(hs :List) as DeepFrozen:
    return def hittables.hit(origin, direction, tMin :Double, tMax :Double, ej):
        var rv := null
        var closestSoFar :Double := tMax
        for h in (hs):
            def [t, _, _, _] := rv := h.hit(origin, direction, tMin,
                                            closestSoFar, __continue)
            closestSoFar := t
        if (rv == null):
            throw.eject(ej, "no hits")
        return rv

def makeLambertian(entropy, albedo :DeepFrozen) as DeepFrozen:
    return def lambertian.scatter(origin, _direction, p, N, _ej):
        def [rx, ry, rz] := entropy.nextBall(3)
        # NB: Original does `target := p + ...; color(p, target - p)` but we
        # can avoid a spurious addition/subtraction pair.
        def target := (N + makeV3(rx, ry, rz)).unit()
        return [p, target, albedo]

def reflect(v, n) as DeepFrozen:
    def uv := v.unit()
    return uv - n * (2.0 * uv.dot(n))

def makeMetal(entropy, albedo :DeepFrozen, fuzz :(Double <= 1.0)) as DeepFrozen:
    return def metal.scatter(origin, direction, p, N, ej):
        def reflected := reflect(direction, N)
        if (reflected.dot(N).belowZero()) { throw.eject(ej, "absorbed?") }
        def [fx, fy, fz] := entropy.nextBall(3)
        def fuzzed := reflected + makeV3(fx, fy, fz) * fuzz
        return [p, fuzzed, albedo]

def refract(v, n, coeff :Double, ej) as DeepFrozen:
    def uv := v.unit()
    def dt := uv.dot(n)
    def discriminant := 1.0 - coeff ** 2 * (1.0 - dt ** 2)
    if (discriminant.atMostZero()) { throw.eject(ej, "internally reflected") }
    return (uv - n * dt) * coeff - n * discriminant.squareRoot()

# https://en.wikipedia.org/wiki/Schlick%27s_approximation
def schlick(cosine :Double, refractiveIndex :Double) :Double as DeepFrozen:
    def r0 :Double := ((1.0 - refractiveIndex) / (1.0 + refractiveIndex)) ** 2
    return r0 + (1.0 - r0) * (1.0 - cosine) ** 5

def makeDielectric(entropy, refractiveIndex :Double) as DeepFrozen:
    # XXX should have blue be 0?
    def attenuation :DeepFrozen := makeV3(1.0, 1.0, 1.0)
    return def dielectric.scatter(origin, direction, p, N, _ej):
        def prod := direction.dot(N)
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
                [p, refracted, attenuation]
            } else { [p, reflect(direction, N), attenuation] }
        } catch _ { [p, reflect(direction, N), attenuation] }

def blueSky :DeepFrozen := makeV3(0.5, 0.7, 1.0)

def color(entropy, origin, direction, world, depth) as DeepFrozen:
    if (depth > 50) { return zero }
    return escape miss:
        # Set minimum t in order to avoid shadow acne.
        def [_, p, N, mat] := world.hit(origin, direction, 1.0e-5, Infinity,
                                        miss)
        escape absorbed:
            def [so, sd, attenuation] := mat.scatter(origin, direction, p, N,
                                                     absorbed)
            attenuation * color(entropy, so, sd, world, depth + 1)
        catch _:
            zero
    catch _:
        def t := 0.5 * (direction.y() + 1.0)
        blueSky * t + one * (1.0 - t)

# NB: 100 is possible, but 12 is not visibly better than 5. Runtime increases
# linearly with this number.
def subsamples :Int := 5

def chapter8(entropy) as DeepFrozen:
    def world := makeHittables([
        makeSphere(makeV3(0.0, 0.0, -1.0), 0.5,
                   makeLambertian(entropy, makeV3(0.1, 0.2, 0.5))),
        makeSphere(makeV3(0.0, -100.5, -1.0), 100.0,
                   makeLambertian(entropy, makeV3(0.8, 0.8, 0.0))),
        makeSphere(makeV3(1.0, 0.0, -1.0), 0.5,
                   makeMetal(entropy, makeV3(0.8, 0.6, 0.2), 1.0)),
        makeSphere(makeV3(-1.0, 0.0, -1.0), 0.5,
                   makeDielectric(entropy, 1.5)),
        makeSphere(makeV3(-1.0, 0.0, -1.0), -0.45,
                   makeDielectric(entropy, 1.5)),
    ])

    return def drawable.drawAt(u :Double, v :Double):
        var rv := zero
        for _ in (0..!subsamples):
            # Important: These must be two uncorrelated random offsets.
            def du := u + (entropy.nextDouble() / 100.0)
            def dv := v + (entropy.nextDouble() / 100.0)
            def direction := (lowerLeft + horizontal * du + vertical * (1.0 - dv)).unit()
            rv += color(entropy, origin, direction, world, 0)
        return (rv / subsamples).asColor()

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def drawable := chapter8(entropy)
    def t := Timer.measureTimeTaken(fn { drawable.drawAt(0.5, 0.5) })
    return when (t) ->
        def [_, d] := t
        traceln(`Time per fragment: $d seconds (${d * 200 * 100} seconds total)`)
        def ppm := makePPM.drawingFrom(drawable)(200, 100)
        when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
