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

# Usually only a few dozen bounces at most, but certain critical angles on
# dielectric or metal surfaces can cause this to skyrocket.
def maxDepth :Int := 200

# NB: Returns not just the color, but also the depth that we needed to go to
# to examine the color.
def color(entropy, ray, world, depth) as DeepFrozen:
    def direction := ray.direction()
    # Set minimum t in order to avoid shadow acne.
    def hit := world.hit(ray, 1.0e-5, Infinity)
    return if (hit =~ [_, p, N, mat]) {
        if (depth < maxDepth && mat.scatter(ray, p, N) =~ [scattered, attenuation]) {
            def [c, d] := color(entropy, scattered, world, depth + 1)
            [attenuation * c, d]
        } else { [zero, depth] }
    } else {
        def t := 0.5 * (direction.unit().y() + 1.0)
        [blueSky * t + one * (1.0 - t), depth]
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
# http://www.davidmlane.com/hyperstat/t_table.html
# 99.9% two-sided CI
def tTable :List[Double] := ([
    636.6, 31.60, 12.92, 8.610, 6.869, 5.959, 5.408, 5.041, 4.781, 4.587,
    4.437, 4.318, 4.221, 4.140, 4.073, 4.015, 3.965, 3.922, 3.883, 3.850,
    3.819, 3.792, 3.767, 3.745, 3.725, 3.707, 3.690, 3.674, 3.659, 3.646,
] + [3.551] * 10 + [3.496] * 10 + [3.460] * 10 +
    [3.416] * 20 + [3.390] * 20 + [3.373] * 20)
def tFinal :Double := 3.291
# 99% two-sided CI
# def tTable :List[Double] := [
#     63.66, 9.925, 5.841, 4.604, 4.032, 3.707, 3.499, 3.355, 3.250, 3.169,
#     3.106, 3.055, 3.012, 2.977, 2.947, 2.921, 2.898, 2.878, 2.861, 2.845,
#     2.831, 2.819, 2.807, 2.797, 2.787, 2.779, 2.771, 2.763, 2.756, 2.750,
#     2.744, 2.738, 2.733, 2.728, 2.723, 2.719, 2.715, 2.711, 2.707, 2.704,
#     2.701, 2.698, 2.695, 2.692, 2.689, 2.687, 2.684, 2.682, 2.680, 2.677,
#     2.675, 2.673, 2.671, 2.670, 2.668, 2.666, 2.664, 2.663, 2.661, 2.660,
#     2.658, 2.657, 2.656, 2.654, 2.653, 2.652, 2.651, 2.650, 2.649, 2.647,
#     2.646, 2.645, 2.644, 2.643, 2.643, 2.642, 2.641, 2.640, 2.639, 2.638,
#     2.637, 2.637, 2.636, 2.635, 2.634, 2.634, 2.633, 2.632, 2.632, 2.631,
#     2.630, 2.630, 2.629, 2.629, 2.628, 2.628, 2.627, 2.626, 2.626, 2.625,
# ]
# def tFinal :Double := 2.576

def chiTable := [
    0.5 => 5.35,
    0.7 => 7.23,
    0.8 => 8.56,
    0.9 => 10.64,
    0.95 => 12.59,
    0.99 => 16.81,
    0.999 => 22.46,
]
def qualityCutoff :Double := chiTable[0.999]

# NB: We adaptively need far fewer than this; keep this at about 5x the
# recommended ceiling. However, we *must* have at least 2 samples, and each
# additional minimum sample raises the quality floor tremendously.
# At 50% CI, we need 2-3 samples.
# At 90% CI, we need 2-5 samples.
# At 95% CI, we need 8-10 samples.
# At 99% CI, we need 20-45 samples.
# At 99.9% CI, we need 500-2000 samples.
def minSamples :Int := 2
def maxSamples :Int := 5_000

def makeWelfordTracker(zero) as DeepFrozen:
    # https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
    # We will track the number of samples, the mean, and the sum of squares of
    # offsets from the mean. When it comes time to output, we will emit the
    # mean as in traditional supersampling.
    var N := 0

    # NB: To ensure that vectors are allowed here, we not only pass in the
    # zero, but carefully keep M1 & M2 on the left and scalars on the right
    # for operations.
    var M1 := zero
    var M2 := zero

    return object welfordTracker:
        "
        Estimate a value by taking samples online.

        The update takes constant time.
        "

        to count():
            return N

        to mean():
            return M1

        to variance():
            return M2 / (N - 1)

        to standardDeviation():
            return welfordTracker.variance().squareRoot()

        to run(sample):
            # Welford's algorithm for observations. First, update the count.
            N += 1
            # Then, update the mean. We'll need to save the old mean too.
            def mean := M1
            def delta := sample - mean
            M1 += delta / N
            # Finally, the component M2 of variance.
            M2 += delta * (sample - M1)

def makeSampleCounter() as DeepFrozen:
    var samplesTaken := 0
    var countersMade := 0
    var countersMaxed := 0

    var depthTracker := makeWelfordTracker(0.0)

    return object sampleCounter:
        to stats():
            return [
                => samplesTaken,
                => countersMade,
                => countersMaxed,
            ]

        to run():
            var sampleTracker := makeWelfordTracker(zero)
            countersMade += 1

            return object sampler:
                to count():
                    return sampleTracker.count()

                to value():
                    return sampleTracker.mean()

                to observe(sample, depth):
                    sampleTracker(sample)
                    depthTracker(depth)
                    samplesTaken += 1
                    if (sampleTracker.count() == maxSamples):
                        countersMaxed += 1

                to needsMore():
                    def N := sampleTracker.count()
                    if (N < minSamples) { return true }
                    if (N > maxSamples) { return false }

                    # This fencepost is correct; -1 comes from Student's
                    # t-distribution and degrees of freedom, and -1 comes from
                    # 0-indexing vs 1-indexing.
                    def tValue := if (N - 2 < tTable.size()) { tTable[N - 2] } else { tFinal }
                    def tTest := (sampleTracker.variance() / N).squareRoot()
                    def pValue := tTest * tValue
                    # https://en.wikipedia.org/wiki/Fisher's_method
                    def fTest := pValue.logarithm().sum() * -2
                    # if (N % 100 == 0):
                    #     traceln(`N=$N t=$tTest p=$pValue f=$fTest q=$qualityCutoff`)
                    # This f-test has 3 degrees of freedom, so we compare it
                    # to the chi-squared table for 6 degrees.
                    return fTest < qualityCutoff

def makeDrawable(entropy, aspectRatio) as DeepFrozen:
    # Which way is up? This way.
    def up := makeV3(0.0, 1.0, 0.0)

    # What are we looking at?
    def lookAt := zero

    # Weekend scene. Big and slow.
    # def world := randomScene(entropy)

    # Study of single sphere above larger floor sphere.
    def world := sphereStudy(entropy)

    def lookFrom := makeV3(4.0, 3.0, 3.0)
    def distToFocus := (lookFrom - lookAt).norm()
    # NB: Aspect ratio is fixed, and we ignore the requested ratio.
    def camera := makeCamera(entropy, lookFrom, lookAt, up, 90.0, aspectRatio,
                             1.0, distToFocus, 0.0, 1.0)
    def counter := makeSampleCounter()
    def drawable.drawAt(u :Double, var v :Double):
        # Rendering is upside-down WRT Monte conventions.
        v := 1.0 - v
        def sampler := counter()
        def depthEstimator := makeWelfordTracker(0.0)
        while (sampler.needsMore()):
            # Important: These must be two uncorrelated random offsets.
            def du := u + (entropy.nextDouble() / 1_000.0)
            def dv := v + (entropy.nextDouble() / 1_000.0)
            def ray := camera.getRay(du, dv)
            def [sample, depth] := color(entropy, ray, world, 0)
            sampler.observe(sample, depth)
            depthEstimator(depth)
        # For funsies: Tint red based on number of samples required; tint
        # green based on average depth of samples. Red ranges from minSamples
        # to maxSamples. Green ranges from no reflections (0) to maxDepth. I
        # say "tint" but I've just done it with a lerp.
        def red := (sampler.count() - minSamples) / maxSamples
        def green := depthEstimator.mean() / maxDepth
        def tint := makeV3(red, green, 0.0)
        def sample := sampler.value()
        return (sample + (-sample + 1.0) * tint).asColor()
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
        def start := Timer.unsafeNow()
        while (true):
            if (i % 200 == 0):
                def [
                    => samplesTaken,
                    => countersMade,
                    => countersMaxed,
                ] | _ := counter.stats()
                def samplesPerSecond := samplesTaken / (Timer.unsafeNow() - start)
                def samplesPerCounter := samplesTaken / countersMade
                traceln(`Status: ${percent(countersMade)} ($samplesPerSecond samples/s) ($samplesPerCounter samples/px) (${percent(countersMaxed)} maxed)`)
            i += 1
            drawer.next(__break)
        def ppm := drawer.finish()
        when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
