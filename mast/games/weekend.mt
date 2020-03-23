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
            to _makeIterator():
                return [x, y, z]._makeIterator()

            to _printOn(out):
                out.print(`vec3($x, $y, $z)`)

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

            to product():
                return x * y * z

            to dot(other):
                return (vec3 * other).sum()

            to cross(via (makeV3.un) [ox, oy, oz]):
                return makeV3(
                    y * oz - z * oy,
                    z * ox - x * oz,
                    x * oy - y * ox,
                )

            to op__cmp(via (makeV3.un) [ox, oy, oz]):
                def cx := x.op__cmp(ox)
                return if (cx.isZero()) {
                    def cy := y.op__cmp(oy)
                    if (cy.isZero()) { z.op__cmp(oz) } else { cy }
                } else { cx }

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

def makeAABB(min, max) as DeepFrozen:
    return object axiallyAlignedBoundingBox:
        to min():
            return min

        to max():
            return max

        to volume():
            return (max - min).product()

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def invD := ray.direction().reciprocal()
            def t0 := (min - origin) * invD
            def t1 := (max - origin) * invD
            # Vector operations. Our true/false is encoded as whether
            # tMax - tMin > 0.0. We need to swap this around whenever invD < 0.0.
            # This can be encoded as sign parity; invD is negative, our values are
            # true when positive, and multiplication by invD will swap signs
            # precisely when it swaps truth values.
            def signs := (t1.min(tMax) - t0.max(tMin)) * invD
            for sign in (signs):
                if (sign.atMostZero()) { return false }
            return true

def makeSphere(center :DeepFrozen, radius :Double, material) as DeepFrozen:
    return object sphere:
        to boundingBox(_t0 :Double, _t1 :Double):
            def corner := makeV3(radius, radius, radius)
            return makeAABB(center - corner, center + corner)

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def direction := ray.direction()
            def oc := origin - center
            def a := direction.dot(direction)
            def b := 2.0 * oc.dot(direction)
            def c := oc.dot(oc) - radius ** 2
            def discriminant := b ** 2 - 4.0 * a * c
            # Don't we have any roots?
            if (discriminant.belowZero()) { return null }
            var t := (-b - discriminant.squareRoot()) / (2.0 * a)
            if (t > tMax || t < tMin):
                t := (-b + discriminant.squareRoot()) / (2.0 * a)
            # Do we actually have a hit in range?
            if (t > tMax || t < tMin) { return null }
            # Point from origin along direction by amount t.
            def p := ray.pointAtParameter(t)
            return [t, p, ((center - p) / -radius).unit(), material]

def makeMovingSphere(startCenter, stopCenter, startTime :Double,
                     stopTime :Double, radius :Double, material) as DeepFrozen:
    def pathCenter := stopCenter - startCenter
    def duration := stopTime - startTime
    def centerAtTime(t :Double):
        return startCenter + pathCenter * ((t - startTime) / duration)

    return object movingSphere:
        to boundingBox(t0 :Double, t1 :Double):
            def corner := makeV3(radius, radius, radius)
            def center0 := centerAtTime(t0)
            def center1 := centerAtTime(t1)
            return makeAABB(center0.min(center1) - corner,
                            center1.max(center0) + corner)

        to hit(ray, tMin :Double, tMax :Double):
            def center := centerAtTime(ray.time())
            return makeSphere(center, radius, material).hit(ray, tMin, tMax)

def makeBVH.fromHittables(entropy, var hs :List, t0 :Double, t1 :Double) as DeepFrozen:
    def make(l, r):
        def lbb := l.boundingBox(t0, t1)
        def rbb := r.boundingBox(t0, t1)
        def aabb := makeAABB(lbb.min().min(rbb.min()),
                             rbb.max().max(lbb.max()))
        return object binaryVolumeHierarchy:
            to boundingBox(_t0 :Double, _t1 :Double):
                return aabb

            to hit(ray, tMin :Double, tMax :Double):
                # Quick reject if the ray doesn't hit this box.
                if (!aabb.hit(ray, tMin, tMax)) { return null }
                def lv := l.hit(ray, tMin, tMax)
                def rv := r.hit(ray, tMin, tMax)
                if (lv == null) { return rv }
                if (rv == null) { return lv }
                # Pick the hit with smaller t, since it happens sooner.
                return (lv[0] < rv[0]).pick(lv, rv)

            # NB: The book has something simpler.
            # We define a simple score, based on volume. Smaller is better,
            # including children.
            to score():
                def volume := aabb.volume()
                def sl := try { l.score() } catch _ { lbb.volume() }
                def sr := try { l.score() } catch _ { rbb.volume() }
                return volume + sl + sr

    # Build the tree using basic binary partioning on a list.
    def go(xs):
        return switch (xs) {
            match [x] { x }
            match [x, y] { make(x, y) }
            match _ {
                def end := xs.size()
                def split := end // 2
                make(go(xs.slice(0, split)), go(xs.slice(split, end)))
            }
        }

    def end := hs.size() - 1
    var bvh := go(hs)
    var score := bvh.score()
    # Randomly attempt to make a better BVH, using the above score as a
    # guideline for how good the current BVH is. Empirically, this is worth
    # spending a long time on; a minute spent in these loops can be worth
    # about 30min of tracing later.
    # First, try shuffling the entire list. We'll do better this way for the
    # first few iterations.
    for _ in (0..!1000):
        def shuffled := entropy.shuffle(hs)
        def candidate := go(shuffled)
        def s := candidate.score()
        if (s < score):
            # traceln(`Improvement: $score to $s (shuffled)`)
            bvh := candidate
            score := s
            hs := shuffled
    # Then, take smaller numbers of swaps. We want to step down in increments
    # matching the slow approach towards a reasonable minimum, but TBH it's
    # simpler and just as effective to sample from the exponential
    # distribution for a while.
    for _ in (0..!1000):
        def l := hs.diverge()
        # Take some number of Fisher-Yates steps.
        def swaps := entropy.nextExponential(0.5).floor() + 1
        for _ in (0..!swaps):
            def i := entropy.nextInt(end)
            def j := entropy.nextInt(end)
            def t := l[i]
            l[i] := l[j]
            l[j] := t
        # And see whether it's better.
        def shuffled := l.snapshot()
        def candidate := go(shuffled)
        def s := candidate.score()
        if (s < score):
            # traceln(`Improvement: $score to $s ($swaps swaps)`)
            bvh := candidate
            score := s
            hs := shuffled
    return bvh

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

def makeConstantTexture(color) as DeepFrozen:
    return def constantTexture.value(_u, _v, _p):
        return color

def makeCheckerTexture(even, odd) as DeepFrozen:
    return def checkerTexture.value(u, v, p):
        def sines := (p * 10.0).sine().product()
        return (sines.belowZero()).pick(odd, even).value(u, v, p)

def makeLambertian(entropy, texture) as DeepFrozen:
    return def lambertian.scatter(ray, p, N):
        def [rx, ry, rz] := entropy.nextBall(3)
        def target := (N + makeV3(rx, ry, rz)).unit()
        return [makeRay(p, target, ray.time()), texture.value(0.0, 0.0, p)]

def reflect(v, n) as DeepFrozen:
    def uv := v.unit()
    return uv - n * (2.0 * uv.dot(n))

def makeMetal(entropy, albedo :DeepFrozen, fuzz :(Double <= 1.0)) as DeepFrozen:
    return def metal.scatter(ray, p, N):
        def reflected := reflect(ray.direction().unit(), N)
        if (reflected.dot(N).belowZero()) { return null }
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
    return def dielectric.scatter(ray, p, N):
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
    # Set minimum t in order to avoid shadow acne.
    def hit := world.hit(ray, 1.0e-5, Infinity)
    return if (hit =~ [_, p, N, mat]) {
        if (depth < 50 && mat.scatter(ray, p, N) =~ [scattered, attenuation]) {
            attenuation * color(entropy, scattered, world, depth + 1)
        } else { zero }
    } else {
        def t := 0.5 * (direction.unit().y() + 1.0)
        blueSky * t + one * (1.0 - t)
    }

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
                   makeLambertian(entropy,
                                  makeCheckerTexture(makeConstantTexture(makeV3(0.2, 0.3, 0.1)),
                                                     makeConstantTexture(makeV3(0.9, 0.9, 0.9))))),
        makeSphere(makeV3(0.0, 1.0, 0.0), 1.0,
                   makeDielectric(entropy, 1.5)),
        makeSphere(makeV3(-4.0, 1.0, 0.0), 1.0,
                   makeLambertian(entropy,
                                  makeConstantTexture(makeV3(0.4, 0.2, 0.1)))),
        makeSphere(makeV3(4.0, 1.0, 0.0), 1.0,
                   makeMetal(entropy, makeV3(0.7, 0.6, 0.5), 0.0)),
    ].diverge()
    # XXX limited for speed, is originally -11..11
    def region := -4..4
    for a in (region):
        for b in (region):
            def chooseMat := rand()
            def center := makeV3(a + 0.9 * rand(), 0.2,
                                 b + 0.9 * rand())
            if ((center - makeV3(4.0, 0.0, 2.0)).norm() <= 0.9) { continue }
            def material := if (chooseMat < 0.8) {
                makeLambertian(entropy,
                               makeConstantTexture(makeV3(rand() * rand(),
                                                          rand() * rand(),
                                                          rand() * rand())))
            } else if (chooseMat < 0.95) {
                makeMetal(entropy,
                          makeV3(0.5 * (1.0 + rand()), 0.5 * (1.0 + rand()),
                                 0.5 * (1.0 + rand())),
                          0.5 * rand())
            } else { makeDielectric(entropy, 1.5) }
            def jitter := makeV3(0.0, entropy.nextDouble(), 0.0)
            rv.push(makeMovingSphere(center, center + jitter, 0.0, 1.0, 0.2,
                                     material))
    return makeBVH.fromHittables(entropy, rv.snapshot(), 0.0, 1.0)

def sphereStudy(entropy) as DeepFrozen:
    def checker := makeLambertian(entropy,
                                  makeCheckerTexture(makeConstantTexture(makeV3(0.2, 0.3, 0.1)),
                                                     makeConstantTexture(makeV3(0.9, 0.9, 0.9))))
    def bigSphere := makeSphere(makeV3(0.0, -10_000.0, 0.0), 10_000.0,
                                checker)
    def study := makeSphere(makeV3(0.0, 1.0, 0.0), 1.0,
                            makeDielectric(entropy, 1.5))
    def spheres := [bigSphere, study]
    return makeBVH.fromHittables(entropy, spheres, 0.0, 1.0)

# https://en.wikipedia.org/wiki/Student%27s_t-distribution#Table_of_selected_values
# 99.8% two-sided CI
def tTable :List[Double] := [
    318.3, 22.33, 10.21, 7.173, 5.893, 5.208, 4.785, 4.501, 4.297, 4.144,
    4.025, 3.930, 3.852, 3.787, 3.733, 3.686, 3.646, 3.610, 3.579, 3.552,
    3.527, 3.505, 3.485, 3.467, 3.450, 3.435, 3.421, 3.408, 3.396, 3.385,
]
def tFinal :Double := 3.090
# 90% two-sided CI
# def tTable :List[Double] := [
#     6.314, 2.920, 2.353, 2.132, 2.015, 1.943, 1.895, 1.860, 1.833, 1.812,
#     1.796, 1.782, 1.771, 1.761, 1.753, 1.746, 1.740, 1.734, 1.729, 1.725,
#     1.721, 1.717, 1.714, 1.711, 1.708, 1.706, 1.703, 1.701, 1.699, 1.697,
# ]
# def tFinal :Double := 1.645
# 50% two-sided CI
# def tTable :List[Double] := [
#     1.000, 0.816, 0.765, 0.741, 0.727, 0.718, 0.711, 0.706, 0.703, 0.700,
#     0.697, 0.695, 0.694, 0.692, 0.691, 0.690, 0.689, 0.688, 0.688, 0.687,
# ]
# def tFinal :Double := 0.674

# NB: We adaptively need far fewer than this.
# At 50% CI, blue sky takes only 2 samples; checkerboards take about 30.
# At 90% CI, blue sky takes about 3 samples, checkerboards take about 10.
def maxSamples :Int := 1_000

def makeSampleCounter() as DeepFrozen:
    var samplesTaken := 0
    var countersMade := 0
    var countersMaxed := 0

    return object sampleCounter:
        to stats():
            return [
                => samplesTaken,
                => countersMade,
                => countersMaxed,
            ]

        to run():
            countersMade += 1

            # https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
            # We will track the number of samples, the mean, and the sum of squares of
            # offsets from the mean. When it comes time to output, we will emit the
            # mean as in traditional supersampling.
            var N := 0
            var M1 := zero
            var M2 := zero

            return object sampler:
                to value():
                    return M1

                to observe(sample):
                    # Welford's algorithm for observations. First, update the count.
                    N += 1
                    # Then, update the mean. We'll need to save the old mean too.
                    def mean := M1
                    def delta := sample - mean
                    M1 += delta / N
                    # Finally, the component M2 of variance.
                    M2 += delta * (sample - M1)

                    samplesTaken += 1
                    if (N == maxSamples):
                        countersMaxed += 1

                to needsMore():
                    if (N < 2) { return true }
                    if (N > maxSamples) { return false }

                    def variance := M2 / (N - 1)
                    # This fencepost is correct; -1 comes from Student's
                    # t-distribution and degrees of freedom, and -1 comes from
                    # 0-indexing vs 1-indexing.
                    def t := if (N - 2 < tTable.size()) { tTable[N - 2] } else { tFinal }
                    # NB: Gain of 256x to change units to numbers of ulps left.
                    # We want to be sure of pixel colors. We have 8 bits of fidelity
                    # in the output, so we should sample to 1 in 256 parts.
                    def interval := (variance / N).squareRoot() * t * 256
                    # if (N % 100 == 0):
                    #     traceln(`N=$N M1=$M1 M2=$M2 interval $interval`)
                    # Are channels roughly below 1.0 ulps of uncertainty?
                    return interval.sum() > 3.0

def makeDrawable(entropy, aspectRatio) as DeepFrozen:
    # Which way is up? This way.
    def up := makeV3(0.0, 1.0, 0.0)

    # What are we looking at?
    def lookAt := makeV3(4.0, 0.0, 1.0)

    # Weekend scene. Big and slow.
    # def world := randomScene(entropy)

    # Study of single sphere above larger floor sphere.
    def world := sphereStudy(entropy)

    def lookFrom := makeV3(6.0, 2.0, 2.0)
    def distToFocus := (lookFrom - lookAt).norm()
    # NB: Aspect ratio is fixed, and we ignore the requested ratio.
    def camera := makeCamera(entropy, lookFrom, lookAt, up, 90.0, aspectRatio,
                             1.0, distToFocus, 0.0, 1.0)
    def counter := makeSampleCounter()
    def drawable.drawAt(u :Double, var v :Double):
        # Rendering is upside-down WRT Monte conventions.
        v := 1.0 - v
        def sampler := counter()
        while (sampler.needsMore()):
            # Important: These must be two uncorrelated random offsets.
            def du := u + (entropy.nextDouble() / 1_000.0)
            def dv := v + (entropy.nextDouble() / 1_000.0)
            def ray := camera.getRay(du, dv)
            def sample := color(entropy, ray, world, 0)
            sampler.observe(sample)
        return sampler.value().asColor()
    return [counter, drawable]

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def w := 160
    def h := 120
    def percent(i) { return `${(i * 100) / (w * h)}%` }
    def p := Timer.measureTimeTaken(fn { makeDrawable(entropy, w / h) })
    return when (p) ->
        def [[counter, drawable], dd] := p
        traceln(`Scene prepared in ${dd}s`)
        def drawer := makePPM.drawingFrom(drawable)(w, h)
        var i := 0
        while (true):
            if (i % 100 == 0):
                def [
                    => samplesTaken,
                    => countersMade,
                    => countersMaxed,
                ] | _ := counter.stats()
                def compensatedSamples := samplesTaken - maxSamples * countersMaxed
                def compensatedCounters := countersMade - countersMaxed
                traceln(`Status: ${percent(countersMade)} (${samplesTaken / countersMade} (${compensatedSamples / compensatedCounters}) samples/pixel) (${percent(countersMaxed)} maxed)`)
            i += 1
            drawer.next(__break)
        def ppm := drawer.finish()
        when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
