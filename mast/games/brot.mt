import "lib/colors" =~ [=> makeColor]
import "lib/samplers" =~ [=> samplerConfig]
import "fun/png" =~ [=> makePNG]
exports (burningShip, mandelbrot, countBrot, makeBrot, main)

# NB: Complex numbers are represented as pairs of Doubles; each x in C is
# represented as xr in R and xi in R.

def complexSquare(r :Double, i :Double) as DeepFrozen:
    return [r * r - i * i, r * i * 2.0]

def burningShip(zr :Double, zi :Double, cr :Double, ci :Double) as DeepFrozen:
    def [sr, si] := complexSquare(zr.abs(), zi.abs())
    return [sr + cr, si + ci]

def mandelbrot(zr :Double, zi :Double, cr :Double, ci :Double) as DeepFrozen:
    def [sr, si] := complexSquare(zr, zi)
    return [sr + cr, si + ci]

def maxIterations :Int := 255
def threshold :Double := 2.0

def countBrot(k :DeepFrozen, ar :Double, ai :Double) :Int as DeepFrozen:
    "
    The number of iterations of `a` under `k` until it passes `threshold`.

    Iteration is capped at `maxIterations`.
    "

    var xr := 0.0
    var xi := 0.0
    for i in (0..!maxIterations):
        def [kr, ki] := k(xr, xi, ar, ai)
        xr := kr
        xi := ki
        if (xr.euclidean(xi) >= threshold):
            return i
    return maxIterations

# A basic psychedelic palette.
# Make escaped samples transparent. Require a minimum count. If we max out,
# use black.
def phi := (5.0.squareRoot() + 1) / 2
def palette :List[DeepFrozen] := [makeColor.clear()] + [for i in (1..!maxIterations) {
    makeColor.HCL(phi * i, 0.9, 0.9, 1.0)
}] + [makeColor.black()]

def makeBrot(fractal :DeepFrozen, xc :Double, yc :Double, height :Double) as DeepFrozen:
    return def draw.drawAt(x :Double, y :Double, => aspectRatio :Double):
        # [0, 1] -> [xc - width/2, xc + width/2]
        def xr := xc + (height * aspectRatio * (x - 0.5))
        def yr := yc + (height * (y - 0.5))
        def count := countBrot(fractal, xr, yr)
        return palette[count]

def main(_argv, => makeFileResource, => Timer) as DeepFrozen:
    def w := 1280
    def h := 720
    def big := makeBrot(mandelbrot, -0.5, 0.0, 5/2)
    def small := makeBrot(burningShip, -1.753, -0.024, 1/20)
    # NB: For smoother rendering, increase this number of samples per
    # pixel. It will take longer, of course.
    # def config := samplerConfig.QuasirandomMonteCarlo(25)
    # Three samples minimum, 100 samples maximum.
    def config := samplerConfig.TTest(samplerConfig.QuasirandomMonteCarlo(1),
                                      0.999, 3, 100)
    def go(drawable):
        def drawer := makePNG.drawingFrom(drawable, config)(w, h)
        var i := 0
        def start := Timer.unsafeNow()
        while (true):
            i += 1
            if (i % 5000 == 0):
                def duration := Timer.unsafeNow() - start
                def pixelsPerSecond := i / duration
                def timeRemaining := ((w * h) - i) / pixelsPerSecond
                traceln(`Status: ${(i * 100) / (w * h)}% ($pixelsPerSecond px/s) (${timeRemaining}s left)`)
            drawer.next(__break)
        return drawer.finish()
    def bigPNG := go(big)
    def smallPNG := go(small)
    return when (makeFileResource("brot-big.png")<-setContents(bigPNG),
                 makeFileResource("brot-small.png")<-setContents(smallPNG)) -> { 0 }
