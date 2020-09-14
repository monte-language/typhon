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

def countBrot(k :DeepFrozen, ar :Double, ai :Double,
              => threshold :Double := 2.0,
              => maxIterations :Int := 42) :Int as DeepFrozen:
    "
    The number of iterations of `a` under `k` until it passes `threshold`.

    Iteration is capped at `maxIterations`.
    "

    var xr := 0.0
    var xi := 0.0
    for i in (0..!maxIterations):
        if (xr.euclidean(xi) >= threshold):
            return i
        def [kr, ki] := k(xr, xi, ar, ai)
        xr := kr
        xi := ki
    return maxIterations

def maxIterations :Int := 255

def makeBrot(fractal :DeepFrozen, xc :Double, yc :Double, height :Double) as DeepFrozen:
    return def draw.drawAt(x :Double, y :Double, => aspectRatio :Double):
        # [0, 1] -> [xc - width/2, xc + width/2]
        def xr := xc + (height * aspectRatio * (x - 0.5))
        def yr := yc + (height * (y - 0.5))
        def count := countBrot(fractal, xr, yr, => maxIterations)
        # Lerp from white to purple, modulating everything by intensity.
        # Make escaped samples transparent. Require a minimum count.
        return if (count < 3) {
            makeColor.clear()
        } else if (count == maxIterations) {
            # Probably in the set.
            makeColor.black()
        } else {
            def lerp := count / maxIterations
            makeColor.RGB(1.0 - (lerp * 0.5), 1.0 - lerp, 1.0, lerp)
        }

def main(_argv, => makeFileResource, => Timer) as DeepFrozen:
    def w := 640
    def h := 480
    def big := makeBrot(mandelbrot, -0.5, 0.0, 5/2)
    def small := makeBrot(burningShip, -1.753, -0.024, 1/20)
    # NB: For smoother rendering, increase this number of samples per
    # pixel. It will take longer, of course.
    def config := samplerConfig.QuasirandomMonteCarlo(5)
    def go(drawable):
        def drawer := makePNG.drawingFrom(drawable, config)(w, h)
        var i := 0
        def start := Timer.unsafeNow()
        while (true):
            i += 1
            if (i % 1000 == 0):
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
