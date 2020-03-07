import "lib/colors" =~ [=> makeColor]
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
                return makeColor.RGB(x, y, z, 1.0)

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

def origin :DeepFrozen := makeV3(0.0, 0.0, 0.0)
def lowerLeft :DeepFrozen := makeV3(-2.0, -1.0, -1.0)
def horizontal :DeepFrozen := makeV3(4.0, 0.0, 0.0)
def vertical :DeepFrozen := makeV3(0.0, 2.0, 0.0)

def pointRay(origin, direction, t :Double) as DeepFrozen:
    return origin + direction * t

def makeSphere(center :DeepFrozen, radius :Double) as DeepFrozen:
    return def sphere.hit(origin, direction, tMin :Double, tMax :Double, ej) as DeepFrozen:
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
        def p := pointRay(origin, direction, t)
        return [t, p, ((center - p) / -radius).unit()]

def makeHittables(hs :List[DeepFrozen]) as DeepFrozen:
    return def hittables.hit(origin, direction, tMin :Double, tMax :Double, ej) as DeepFrozen:
        var rv := null
        var closestSoFar :Double := tMax
        for h in (hs):
            def [t, _, _] := rv := h.hit(origin, direction, tMin,
                                         closestSoFar, __continue)
            closestSoFar := t
        if (rv == null):
            throw.eject(ej, "no hits")
        return rv

def world :DeepFrozen := makeHittables([
    makeSphere(makeV3(0.0, 0.0, -1.0), 0.5),
    makeSphere(makeV3(0.0, -100.5, -1.0), 100.0),
])

def chapter5.drawAt(u :Double, v :Double) as DeepFrozen:
    def direction := (lowerLeft + horizontal * u + vertical * (1.0 - v)).unit()
    return escape ej:
        def [_, _, N] := world.hit(origin, direction, 0.0, Infinity, ej)
        ((N + 1.0) * 0.5).asColor()
    catch _:
        def t := 0.5 * (direction.y() + 1.0)
        def lerp := makeV3(0.5, 0.7, 1.0) * t + makeV3(1.0, 1.0, 1.0) * (1.0 - t)
        lerp.asColor()

def main(_argv, => makeFileResource) as DeepFrozen:
    def ppm := makePPM.drawingFrom(chapter5)(400, 200)
    return when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
