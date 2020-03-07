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
                return (vec3 + other).sum()

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

def chapter1.drawAt(u :Double, v :Double) as DeepFrozen:
    return makeColor.RGB(u, 1.0 - v, 0.2, 1.0)

def chapter3.drawAt(u :Double, v :Double) as DeepFrozen:
    # def origin := makeV3(0.0, 0.0, 0.0)
    def lowerLeft := makeV3(-2.0, -1.0, -1.0)
    def horizontal := makeV3(4.0, 0.0, 0.0)
    def vertical := makeV3(0.0, 2.0, 0.0)
    def direction := (lowerLeft + horizontal * u + vertical * (1.0 - v)).unit()
    def t := 0.5 * (direction.y() + 1.0)
    def lerp := makeV3(0.5, 0.7, 1.0) * t + makeV3(1.0, 1.0, 1.0) * (1.0 - t)
    return lerp.asColor()

def main(_argv, => makeFileResource) as DeepFrozen:
    def ppm := makePPM.drawingFrom(chapter3)(200, 100)
    return when (makeFileResource("weekend.ppm")<-setContents(ppm)) -> { 0 }
