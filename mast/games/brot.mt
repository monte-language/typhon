import "lib/complex" =~ [=> Complex, => makeComplex]
import "lib/colors" =~ [=> makeColor]
exports (burningShip, mandelbrot, countBrot, makeBrot)

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

def maxIterations :Int := 255

# -0.25, -0.4, (1/2)
# -1.7529296875, -0.025, (1/32)

def makeBrot(xc :Double, yc :Double, height :Double) as DeepFrozen:
    return def draw.drawAt(x :Double, y :Double, => aspectRatio :Double):
        # [0, 1] -> [xc - width/2, xc + width/2]
        def xr := xc + (height * aspectRatio * (x - 0.5))
        def yr := yc + (height * (y - 0.5))
        escape ej:
            def count := countBrot(burningShip, makeComplex(xr, yr), ej, => maxIterations)
            # Lerp from white to purple, modulating everything by intensity.
            return makeColor.RGB(
                1.0,
                1.0 - (count / maxIterations),
                1.0,
                1.0,
            )
        catch _:
            # Probably in the set.
            return makeColor.clear()
