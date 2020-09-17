import "lib/colors" =~ [=> makeColor]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/samplers" =~ [=> samplerConfig]
import "lib/vectors" =~ [=> V, => glsl]
import "fun/png" =~ [=> makePNG]
exports (main)

# https://www.realtimerendering.com/raytracing/Ray%20Tracing%20in%20a%20Weekend.pdf

def randomUnit(entropy) as DeepFrozen:
    "A random unit vector."
    def [x, y, z] := [for coord in (entropy.nextSphere(2)) {
        if (entropy.nextBool()) { -coord } else { coord }
    }]
    return V(x, y, z)

# XXX common code not yet factored to lib/vectors
def productTimes(x, y) as DeepFrozen { return x * y }
def productDouble :DeepFrozen := V.makeFold(1.0, productTimes)

def zero :DeepFrozen := V(0.0, 0.0, 0.0)
def one :DeepFrozen := V(1.0, 1.0, 1.0)

def makeAABB(min, max) as DeepFrozen:
    return object axiallyAlignedBoundingBox:
        to min():
            return min

        to max():
            return max

        to volume():
            return productDouble(max - min)

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

def flipN(hittable) as DeepFrozen:
    return object flippedNormals:
        to boundingBox(t0 :Double, t1 :Double):
            return hittable.boundingBox(t0, t1)

        to hit(ray, tMin :Double, tMax :Double):
            return if (hittable.hit(ray, tMin, tMax) =~ [t, u, v, p, N, m]):
                [t, u, v, p, -N, m]

def HALF_PI :Double := 1.0.arcSine()

def makeSphere(center :DeepFrozen, radius :Double, material) as DeepFrozen:
    return object sphere:
        to boundingBox(_t0 :Double, _t1 :Double):
            def corner := V(radius, radius, radius)
            return makeAABB(center - corner, center + corner)

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def direction := ray.direction()
            def oc := origin - center
            def a := glsl.dot(direction, direction)
            def b := 2.0 * glsl.dot(oc, direction)
            def c := glsl.dot(oc, oc) - radius ** 2
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
            def N := glsl.normalize((p - center) / radius)
            # Compute u and v based on the normal, which is on the unit
            # sphere.
            def [x, y, z] := V.un(N, null)
            def phi := z.arcTangent(x)
            def theta := y.arcSine()
            def u := (phi + 2 * HALF_PI) / (4 * HALF_PI)
            def v := (theta + HALF_PI) / (2 * HALF_PI)
            return [t, u, v, p, N, material]

# I *guess* we're duplicating this three times.

def makeXYRect(x0 :Double, x1 :Double, y0 :Double, y1 :Double, k :Double,
               material) as DeepFrozen:
    return object XYRect:
        to boundingBox(_t0 :Double, _t1 :Double):
            return makeAABB(V(x0, y0, k - 0.001), V(x1, y1, k + 0.001))

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def direction := ray.direction()
            def t := (k - origin.z()) / direction.z()
            if (t < tMin || t > tMax) { return null }
            def x := origin.x() + t * direction.x()
            if (x < x0 || x > x1) { return null }
            def y := origin.y() + t * direction.y()
            if (y < y0 || y > y1) { return null }
            def u := (x - x0) / (x1 - x0)
            def v := (y - y0) / (y1 - y0)
            return [t, u, v, ray.pointAtParameter(t), V(0.0, 0.0, 1.0),
                    material]

def makeXZRect(x0 :Double, x1 :Double, z0 :Double, z1 :Double, k :Double,
               material) as DeepFrozen:
    return object XZRect:
        to boundingBox(_t0 :Double, _t1 :Double):
            return makeAABB(V(x0, k - 0.001, z0), V(x1, k + 0.001, z1))

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def direction := ray.direction()
            def t := (k - origin.y()) / direction.y()
            if (t < tMin || t > tMax) { return null }
            def x := origin.x() + t * direction.x()
            if (x < x0 || x > x1) { return null }
            def z := origin.z() + t * direction.z()
            if (z < z0 || z > z1) { return null }
            def u := (x - x0) / (x1 - x0)
            def v := (z - z0) / (z1 - z0)
            return [t, u, v, ray.pointAtParameter(t), V(0.0, 1.0, 0.0),
                    material]

def makeYZRect(y0 :Double, y1 :Double, z0 :Double, z1 :Double, k :Double,
               material) as DeepFrozen:
    return object YZRect:
        to boundingBox(_t0 :Double, _t1 :Double):
            return makeAABB(V(k - 0.001, y0, z0), V(k + 0.001, y1, z1))

        to hit(ray, tMin :Double, tMax :Double):
            def origin := ray.origin()
            def direction := ray.direction()
            def t := (k - origin.x()) / direction.x()
            if (t < tMin || t > tMax) { return null }
            def y := origin.y() + t * direction.y()
            if (y < y0 || y > y1) { return null }
            def z := origin.z() + t * direction.z()
            if (z < z0 || z > z1) { return null }
            def u := (y - y0) / (y1 - y0)
            def v := (z - z0) / (z1 - z0)
            return [t, u, v, ray.pointAtParameter(t), V(1.0, 0.0, 0.0),
                    material]

def makeBox(p0, p1, material) as DeepFrozen:
    return [
        makeXYRect(p0.x(), p1.x(), p0.y(), p1.y(), p1.z(), material),
        flipN(makeXYRect(p0.x(), p1.x(), p0.y(), p1.y(), p0.z(), material)),
        makeXZRect(p0.x(), p1.x(), p0.z(), p1.z(), p1.y(), material),
        flipN(makeXZRect(p0.x(), p1.x(), p0.z(), p1.z(), p0.y(), material)),
        makeYZRect(p0.y(), p1.y(), p0.z(), p1.z(), p1.x(), material),
        flipN(makeYZRect(p0.y(), p1.y(), p0.z(), p1.z(), p0.x(), material)),
    ]

def makeMovingSphere(startCenter, stopCenter, startTime :Double,
                     stopTime :Double, radius :Double, material) as DeepFrozen:
    def pathCenter := stopCenter - startCenter
    def duration := stopTime - startTime
    def centerAtTime(t :Double):
        return startCenter + pathCenter * ((t - startTime) / duration)

    return object movingSphere:
        to boundingBox(t0 :Double, t1 :Double):
            def corner := V(radius, radius, radius)
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
        def sines := productDouble((p * 10.0).sine())
        return (sines.belowZero()).pick(odd, even).value(u, v, p)

def makeIsotropic(entropy, texture) as DeepFrozen:
    return object isotropic:
        to scatter(ray, p, _N):
            def target := randomUnit(entropy)
            return [makeRay(p, target, ray.time()), texture.value(0.0, 0.0, p)]

        to emitted(_u, _v, _p):
            return zero

def makeConstantMedium(entropy, boundary, density :Double, texture) as DeepFrozen:
    def phaseFunction := makeIsotropic(entropy, texture)

    return object constantMedium:
        to boundingBox(t0 :Double, t1 :Double):
            return boundary.boundingBox(t0, t1)

        to hit(ray, tMin :Double, tMax :Double):
            return if (boundary.hit(ray, -Infinity, Infinity) =~
                       [t1, u1, v1, p1, N1, m1]) {
                if (boundary.hit(ray, t1 + 0.0001, Infinity) =~
                    [t2, u2, v2, p2, N2, m2]) {
                    def r1t := t1.max(tMin)
                    def r2t := t2.min(tMax)
                    if (r1t >= r2t) { return null }
                    def length := glsl.length(ray.direction())
                    def distanceInsideBoundary := (r2t - r1t) * length
                    def hitDistance := entropy.nextExponential(density)
                    if (hitDistance < distanceInsideBoundary) {
                        def t := r1t + hitDistance / length
                        def N := randomUnit(entropy)
                        [t, 0.0, 0.0, ray.pointAtParameter(t), N,
                         phaseFunction]
                    }
                }
            }

def makeMarbleTexture(noise) as DeepFrozen:
    def scale := 0.5
    return def noisyTexture.value(_u, _v, p):
        def [_, _, z] := V.un(p, null)
        def grey := (z * scale + noise.turbulence(p, 7) * 10.0).sine()
        # Scale from [-1,1] to [0,1].
        def scaled := 0.5 * (1.0 + grey)
        # Scoop greens and blues in the mid range to create a rosy red marble.
        def scooped := scaled ** 2
        # And amplify the red to give some vibrancy.
        return V(scooped, scaled.squareRoot(), scooped)

def makeLambertian(entropy, texture) as DeepFrozen:
    return object lambertianMaterial:
        to scatter(ray, p, N):
            # NB: The original uses randomness *in* the unit sphere,
            # intentionally; this gives cubic pinching at the corners, though,
            # compared to using unit vectors.
            def target := glsl.normalize(N + randomUnit(entropy))
            return [makeRay(p, target, ray.time()), texture.value(0.0, 0.0, p)]

        to emitted(_u, _v, _p):
            return zero

def makeMetal(entropy, albedo :DeepFrozen, fuzz :(Double <= 1.0)) as DeepFrozen:
    return object metalMaterial:
        to scatter(ray, p, N):
            def reflected := glsl.reflect(glsl.normalize(ray.direction()), N)
            if (glsl.dot(reflected, N).belowZero()) { return null }
            def fuzzed := reflected + randomUnit(entropy) * fuzz
            return [makeRay(p, fuzzed, ray.time()), albedo]

        to emitted(_u, _v, _p):
            return zero

# https://en.wikipedia.org/wiki/Schlick%27s_approximation
def schlick(cosine :Double, refractiveIndex :Double) :Double as DeepFrozen:
    def r0 := ((1.0 - refractiveIndex) / (1.0 + refractiveIndex)) ** 2
    return r0 + (1.0 - r0) * (1.0 - cosine) ** 5

def makeDielectric(entropy, refractiveIndex :Double) as DeepFrozen:
    # NB: The original deliberately destroys the blue channel, but I don't see
    # why that should be done. The blueness of scenes comes from the ambient
    # blue lighting, I think!
    def attenuation :DeepFrozen := V(1.0, 1.0, 1.0)
    return object dielectricMaterial:
        to scatter(ray, p, N):
            def direction := ray.direction()
            def prod := glsl.dot(glsl.normalize(direction), N)
            def [outwardNormal, coeff, cosine] := if (prod > 0) {
                [-N, refractiveIndex, refractiveIndex * prod]
            } else {
                [N, refractiveIndex.reciprocal(), -prod]
            }
            # If we could refract, then use Schlick's approximation to
            # consider whether we will actually refract.
            def refracted := glsl.refract(direction, outwardNormal, coeff)
            return if (refracted != null &&
                       (schlick(glsl.length(cosine / direction), refractiveIndex) >
                        entropy.nextDouble())) {
                [makeRay(p, refracted, ray.time()), attenuation]
            } else {
                [makeRay(p, glsl.reflect(direction, N), ray.time()), attenuation]
            }

        to emitted(_u, _v, _p):
            return zero

def makeDiffuseLight(texture) as DeepFrozen:
    return object diffuselyLitMaterial:
        to scatter(_ray, _p, _N):
            return null

        to emitted(u, v, p):
            return texture.value(u, v, p)

# Usually only a few dozen bounces at most, but certain critical angles on
# dielectric or metal surfaces can cause this to skyrocket.
def maxDepth :Int := 100

# NB: Returns not just the color, but also the depth that we needed to go to
# to examine the color.
def color(entropy, ray, world, depth) as DeepFrozen:
    # def direction := ray.direction()
    # Set minimum t in order to avoid shadow acne.
    def hit := world.hit(ray, 1.0e-5, Infinity)
    return if (hit =~ [_, u, v, p, N, mat]) {
        def emitted := mat.emitted(u, v, p)
        if (depth < maxDepth && mat.scatter(ray, p, N) =~ [scattered, attenuation]) {
            def [c, d] := color(entropy, scattered, world, depth + 1)
            [emitted + attenuation * c, d]
        } else { [emitted, depth] }
    } else {
        # XXX [-1,1] -> [0,1] we should factor out this too
        # def [_, t, _] := V.un((glsl.normalize(direction) + 1.0) * 0.5, null)
        # Whether there is an ambient light.
        if (true) { [one, depth] } else { [zero, depth] }
    }

def makeCamera(entropy, lookFrom, lookAt, up, vfov :Double, aspect :Double,
               aperture :Double, focusDist :Double, startTime :Double,
               stopTime :Double) as DeepFrozen:
    def lensRadius := aperture / 2.0
    # Convert from angles to radians.
    def theta := vfov * 0.0.arcCosine() / 90.0
    def halfHeight := (theta / 2.0).tangent()
    def halfWidth := halfHeight * aspect
    def w := glsl.normalize(lookFrom - lookAt)
    def u := glsl.normalize(glsl.cross(up, w))
    def v := glsl.cross(w, u)
    def lowerLeft := lookFrom - (
        (u * halfWidth + v * halfHeight + w) * focusDist)
    def horizontal := u * (2.0 * halfWidth * focusDist)
    def vertical := v * (2.0 * halfHeight * focusDist)
    def duration := stopTime - startTime

    return def camera.getRay(u :Double, v :Double):
        # NB: .nextBall() is right; we want an offset *within* the lens.
        def [rx, ry] := entropy.nextBall(2)
        def offset := u * rx + v * ry
        def time := startTime + entropy.nextDouble() * duration
        def origin := lookFrom + offset * lensRadius
        def direction := lowerLeft + horizontal * u + vertical * v - origin
        return makeRay(origin, direction, time)

def randomScene(entropy) as DeepFrozen:
    def rand := entropy.nextDouble
    def rv := [
        makeSphere(V(0.0, -10_000.0, 0.0), 10_000.0,
                   makeLambertian(entropy,
                                  makeCheckerTexture(makeConstantTexture(V(0.2, 0.3, 0.1)),
                                                     makeConstantTexture(V(0.9, 0.9, 0.9))))),
        makeSphere(V(0.0, 1.0, 0.0), 1.0,
                   makeDielectric(entropy, 1.5)),
        makeSphere(V(-4.0, 1.0, 0.0), 1.0,
                   makeLambertian(entropy,
                                  makeConstantTexture(V(0.4, 0.2, 0.1)))),
        makeSphere(V(4.0, 1.0, 0.0), 1.0,
                   makeMetal(entropy, V(0.7, 0.6, 0.5), 0.0)),
    ].diverge()
    # XXX limited for speed, is originally -11..11
    def region := -3..3
    for a in (region):
        for b in (region):
            def chooseMat := rand()
            def center := V(a + 0.9 * rand(), 0.2, b + 0.9 * rand())
            if (glsl.length((center - V(4.0, 0.0, 2.0))) <= 0.9) { continue }
            def material := if (chooseMat < 0.8) {
                makeLambertian(entropy,
                               makeConstantTexture(V(rand() * rand(),
                                                     rand() * rand(),
                                                     rand() * rand())))
            } else if (chooseMat < 0.95) {
                makeMetal(entropy,
                          V(0.5 * (1.0 + rand()), 0.5 * (1.0 + rand()),
                            0.5 * (1.0 + rand())),
                          0.5 * rand())
            } else { makeDielectric(entropy, 1.5) }
            def jitter := V(0.0, entropy.nextDouble(), 0.0)
            rv.push(makeMovingSphere(center, center + jitter, 0.0, 1.0, 0.2,
                                     material))
    return makeBVH.fromHittables(entropy, rv.snapshot(), 0.0, 1.0)

def sphereStudy(entropy) as DeepFrozen:
    def checker := makeLambertian(entropy,
                                  makeCheckerTexture(makeConstantTexture(V(0.2, 0.3, 0.1)),
                                                     makeConstantTexture(V(0.9, 0.9, 0.9))))
    # https://docs.unrealengine.com/en-US/Engine/Rendering/Materials/PhysicallyBased/index.html
    # def platinum := makeMetal(entropy, V(0.672, 0.637, 0.585), 0.0001)
    # def glass := makeDielectric(entropy, 1.5)
    def marble := makeLambertian(entropy, makeMarbleTexture(makeSimplexNoise(entropy)))
    def bigSphere := makeSphere(V(0.0, -10_000.0, 0.0), 10_000.0,
                                checker)
    def study := makeSphere(V(0.0, 1.0, 0.0), 1.0, marble)
    # def smoke := makeConstantMedium(entropy, study, 0.01,
    #                                 makeMarbleTexture(makeSimplexNoise(entropy)))
    def spheres := [bigSphere, study]
    return makeBVH.fromHittables(entropy, spheres, 0.0, 1.0)

def cornellBox(entropy) as DeepFrozen:
    def [red, white, green] := [for color in ([
        V(0.65, 0.05, 0.05),
        one * 0.73,
        V(0.12, 0.45, 0.15),
    ]) makeLambertian(entropy, makeConstantTexture(color))]
    def light := makeDiffuseLight(makeConstantTexture(one * 15.0))
    def walls := [
        flipN(makeYZRect(0.0, 555.0, 0.0, 555.0, 555.0, green)),
        makeYZRect(0.0, 555.0, 0.0, 555.0, 0.0, red),
        makeXZRect(213.0, 343.0, 227.0, 332.0, 554.0, light),
        flipN(makeXZRect(0.0, 555.0, 0.0, 555.0, 555.0, white)),
        makeXZRect(0.0, 555.0, 0.0, 555.0, 0.0, white),
        flipN(makeXYRect(0.0, 555.0, 0.0, 555.0, 555.0, white)),
        # Debugging ball.
        # makeSphere(V(278.0, 278.0, 0.0), 100.0, green),
    ]
    def box1 := makeBox(V(130.0, 0.0, 65.0), V(295.0, 165.0, 230.0),
                        white)
    def box2 := makeBox(V(265.0, 0.0, 295.0), V(430.0, 330.0, 460.0),
                        white)
    def scene := walls + box1 + box2
    return makeBVH.fromHittables(entropy, scene, 0.0, 1.0)

def makeDrawable(entropy, aspectRatio) as DeepFrozen:
    # Which way is up? This way.
    def up := V(0.0, 1.0, 0.0)

    # Weekend scene. Big and slow.
    # def world := randomScene(entropy)
    # Study of single sphere above larger floor sphere.
    def world := sphereStudy(entropy)
    # The Cornell Box.
    # def world := cornellBox(entropy)

    # What are we looking at?
    # def lookAt := V(278.0, 278.0, 0.0)
    # def lookFrom := V(278.0, 278.0, -800.0)

    def lookAt := V(0.0, 1.0, 0.0)
    def lookFrom := V(3.0, 2.0, 4.0)
    # NB: In degrees!
    def fov := 40.0
    def aperture := 0.0005
    def distToFocus := glsl.distance(lookFrom, lookAt)
    # NB: Aspect ratio is fixed, and we ignore the requested ratio.
    def camera := makeCamera(entropy, lookFrom, lookAt, up, fov, aspectRatio,
                             aperture, distToFocus, 0.0, 1.0)
    return def drawable.drawAt(u :Double, v :Double):
        # NB: Rendering is upside-down WRT Monte conventions.
        def ray := camera.getRay(u, 1.0 - v)
        def [sample, _depth] := color(entropy, ray, world, 0)
        # Okay, *now* we clamp.
        def [r, g, b] := _makeList.fromIterable(sample.min(1.0))
        return makeColor.RGB(r, g, b, 1.0)

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def w := 640
    def h := 360
    def p := Timer.measureTimeTaken(fn { makeDrawable(entropy, w / h) })
    return when (p) ->
        def [drawable, dd] := p
        traceln(`Scene prepared in ${dd}s`)
        # The original design. Some number of samples, jittered reasonably
        # around the pixel in a responsible manner. QRMC is a good way to
        # achieve this effect without introducing obvious aliasing or
        # dithering effects. The original starts at 100 and then climbs to
        # 1_000 and eventually 10_000.
        # def config := samplerConfig.QuasirandomMonteCarlo(25)
        # My adaptive take on the original design. Repeated center sampling
        # will jitter due to inherent randomness in the tracing algorithm, so
        # repeat until statistically stable.
        def config := samplerConfig.TTest(samplerConfig.Center(), 0.999, 3, 100)
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
            drawer.next(__break)
        def png := drawer.finish()
        when (makeFileResource("weekend.png")<-setContents(png)) -> { 0 }
