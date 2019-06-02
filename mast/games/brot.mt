import "lib/complex" =~ [=> Complex, => makeComplex]
import "fun/ppm" =~ [=> makePPM]
exports (burningShip, mandelbrot,
    countBrot, makeBrot)

def burningShip(z :Complex, c :Complex) :Complex as DeepFrozen:
    def a := makeComplex(z.real().abs(), z.imag().abs())
    return a * a + c

def mandelbrot(z :Complex, c :Complex) :Complex as DeepFrozen:
    return z * z + c

def countBrot(k :DeepFrozen, a :Complex, ej, => threshold :Double := 2.0,
              => maxIterations :Int := 42) :Int as DeepFrozen:
    "
    The number of iterations of `a` under `k` until it passes `threshold`.

    Iteration is capped at `maxIterations`.
    "

    var rv := makeComplex(0.0, 0.0)
    for i in (0..!maxIterations):
        if (rv.abs() >= threshold):
            return i
        rv := k(rv, a)
    throw.eject(ej, "Out of iterations")

def fixingViewport(x :Double, _) :Double as DeepFrozen:
    return 4.0 * x - 2.0

def maxIterations :Int := 255

def makeBrot() as DeepFrozen:
    def draw(via (fixingViewport) x :Double, via (fixingViewport) y :Double,
             => aspectRatio :Double):
        escape ej:
            def count := countBrot(mandelbrot, makeComplex(x * aspectRatio, y), ej, => maxIterations)
            # Lerp from white to purple to blue, modulating everything by intensity.
            return [
                1.0 - (count / maxIterations),
                1.0 - (count / maxIterations / 2),
                1.0,
            ]
        catch _:
            # Probably in the set.
            return [0.0] * 3
    return makePPM.drawingFrom(draw)
