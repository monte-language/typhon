import "lib/asdl" =~ [=> buildASDLModule]
import "lib/colors" =~ [=> makeColor]
import "lib/welford" =~ [=> makeWelford]
import "lib/vectors" =~ [=> V]
exports (samplerConfig, costOfConfig, makeDiscreteSampler)

def ["ASTBuilder" => samplerConfig] | _ := eval(buildASDLModule(`
sampler = Center
        | Quincunx
        | QuasirandomMonteCarlo(int count)
        | TTest(sampler, double quality, int minimumCount, int maximumCount)
`, "samplers"), safeScope)(null)

# Pixel area: 4 / (w * h)
# Pixel radius: √(area / pi) = 2 / √(w * h * pi) = (2 / √pi) / √(w * h)
# This constant is the first half of that.
def R :Double := 2.0 / (0.0.arcCosine() * 2.0).squareRoot()

# The plastic constant. This nice definition is exact for our Doubles.
def plastic :Double := {
    def s := 69.0.squareRoot()
    def f(x) { return (x / 18) ** (1 / 3) }
    f(9 + s) + f(9 - s)
}
def frac(x) as DeepFrozen:
    return x - x.floor()

def averageColor(colors :List) as DeepFrozen:
    # NB: Work in linear RGB!
    var channels := [0.0] * 4
    for color in (colors):
        channels := [for i => chan in (color.RGB()) channels[i] + chan]
    def scale := colors.size().asDouble().reciprocal()
    # NB: lib/colors does a premultiply here; I think we're *not*
    # premultiplied, so that this is correct.
    return M.call(makeColor, "RGB", [for chan in (channels) chan * scale],
                  [].asMap())

def cumulativeT(t :Double, v :Int) :Double as DeepFrozen:
    "The CDF for Student's t-distribution with `v` degrees of freedom."

    def x := v / (t * t + v)
    return 1.0 - x.cumulativeBeta(v * 0.5, 0.5)

def quantileT(y :Double, v :Int) :Double as DeepFrozen:
    "The quantile function for Student's t-distribution with `v` degrees of freedom."

    def x := (1.0 - y).quantileBeta(v * 0.5, 0.5)
    return ((v / x) - v).squareRoot()

def cumulativeChi2(x :Double, k :Int) :Double as DeepFrozen:
    "The CDF for the χ2 distribution with `k` degrees of freedom."

    return (x * 0.5).cumulativeGamma(k * 0.5)

def sumPlus(x, y) as DeepFrozen { return x + y }
def sum :DeepFrozen := V.makeFold(0.0, sumPlus)

# NB: We adaptively need far fewer than this; keep this at about 5x the
# recommended ceiling. However, we *must* have at least 2 samples, and each
# additional minimum sample raises the quality floor tremendously.
# At 50% CI, we need 2-3 samples.
# At 90% CI, we need 2-5 samples.
# At 95% CI, we need 8-10 samples.
# At 99% CI, we need 20-45 samples.
# At 99.9% CI, we need 500-2000 samples.
def minSamples :Int := 3
def maxSamples :Int := 1_000

def needsMoreSamples(samplers :List, qualityCutoff :Double) as DeepFrozen:
    # They should all have the same count!
    def N := samplers[0].count()
    # Unconditionally take one sample, because we were going to need at least
    # one sample.
    if (N < minSamples) { return true }
    if (N > maxSamples) { return false }

    # Recall that t-tests ask for N-1 degrees of freedom.
    def tValue := quantileT(qualityCutoff, N - 1)
    def variances := M.call(V, "run", [for s in (samplers) s.variance()],
                            [].asMap())
    def tTests := (variances / N).squareRoot()
    def pValues := tTests * tValue
    # https://en.wikipedia.org/wiki/Fisher's_method
    def fTest := sum(pValues.logarithm()) * -2
    # This f-test has 3 degrees of freedom, so we compare it
    # to the chi-squared table for 6 degrees.
    def probability := cumulativeChi2(fTest, 6)
    if (N % 100 == 0):
        traceln(`N=$N t=$tTests p=$pValues f=$fTest prob=$probability`)
    # Quality is in nines, probability is 1 - nines. We want an improbably
    # high-quality sample, so we want to flip probability around.
    return 1.0 - probability > qualityCutoff

object costOfConfig as DeepFrozen:
    "
    How many samples a given sampler configuration is expected to consume
    per fragment.
    "

    to Center() :Int:
        return 1

    to Quincunx() :Int:
        return 5

    to QuasirandomMonteCarlo(count :Int) :Int:
        return count

    to TTest(sampler, quality :Double, minimumCount :Int, maximumCount :Int) :Int:
        # q% of the time, we'll be unsatisfied with the typical pixel. But
        # the typical pixel will be typical most of the time. Using an old
        # statistics rule of thumb for normal distributions, "most" is 2/3.
        return 3 * sampler * (quality * maximumCount + (1.0 - quality) * minimumCount).floor()

def makeDiscreteSampler(drawable, config,
                        width :(Int > 0),
                        height :(Int > 0)) as DeepFrozen:
    "
    Turn a continuous `drawable` into a discrete sampling grid. The resulting
    grid can be sampled at values from from (0, 0) to (w-1, h-1).

    Pixel shape is preserved, so that if `width > height`, then `drawable`
    will be sampled at X-values outside [0, 1], creating a wide-screen shot,
    and vice versa for portrait shots. In addition, the grid is not clamped,
    so that sampling outside [0, w) or [0, h) will also take out-of-boundary
    samples on `drawable`.

    `config` should be built from the parent module's `samplerConfig`.
    "

    # How much wider the canvas is than it is tall.
    def aspectRatio :Double := width / height
    # The dimensions of each pixel in canvas space.
    def iw :Double := width.asDouble().reciprocal()
    def ih :Double := height.asDouble().reciprocal()
    def dw :Double := iw * 0.5
    def dh :Double := ih * 0.5
    # See formula for the constant R.
    def pixelRadius :Double := R / (width * height).asDouble().squareRoot()

    object makeSampler:
        to Center():
            return fn x, y {
                drawable.drawAt(dw + x * iw, dh + y * ih, => aspectRatio,
                                => pixelRadius)
            }

        to Quincunx():
            # ⁙
            # We are going to sample on the circular disc, to avoid
            # certain stretching aliasing artifacts. This offset represents
            # taking the angle ⦟ which is half of a right angle ⦜; thanks to
            # symmetry, one offset works for both dimensions.
            def o := pixelRadius * (2.0.squareRoot() / 2)
            def offsets := [
                [dw, dh],
                [dw - o, dh - o],
                [dw + o, dh + o],
                [dw + o, dh - o],
                [dw - o, dh + o],
            ]
            return fn x, y {
                def bx := x * iw
                def by := y * ih
                def colors := [for [dx, dy] in (offsets) {
                    drawable.drawAt(bx + dx, by + dy, => aspectRatio,
                                    => pixelRadius)
                }]
                averageColor(colors)
            }

        to QuasirandomMonteCarlo(count :Int):
            # The two low-discrepancy sequences for 2D coordinates. The idea is that
            # we want some controlled de-correlation across different pixels, in order
            # to not have a tropic pattern from a fixed supersampling pattern mask. It
            # happens that this R2 sequence is optimal when folded back onto itself on
            # a single square, and it should similarly give very evenly-spaced but
            # constantly-shifting offsets.
            var c := frac(V(plastic, plastic ** 2))
            def i := V(iw, ih)

            return fn x, y {
                # b is in the upper-left corner of each pixel. We'll move it
                # around the pixel by adding jitter in (0, 1).
                def b := V(x, y) * i
                def colors := [for _ in (0..!count) {
                    # Jitter the coordinates to achieve quasirandom Monte Carlo.
                    def [jx, jy] := V.un(b + (c * pixelRadius), null)
                    c := frac(c + plastic)
                    drawable.drawAt(jx, jy, => aspectRatio, => pixelRadius)
                }]
                averageColor(colors)
            }

        to TTest(sampler, quality :Double, minimumCount :Int, maximumCount :Int):
            # Take minimum number of samples, perform a t-test; if the test
            # fails, evaluate the maximum number of samples instead.
            # XXX I bet that there's a way to use the result of the t-test to
            # guess how *many* samples we should take.
            return fn x, y {
                def samplers := [makeWelford(), makeWelford(), makeWelford(),
                                 makeWelford()]
                # Blessedly, addition and multiplication are commutative, so
                # we can do multiple samples in any order and Welford's
                # algorithm still works.
                def go() {
                    def color := sampler(x, y)
                    for i => channel in (color.RGB()) { samplers[i](channel) }
                }
                def firstRound := [for _ in (0..!minimumCount) { go() }]
                def secondRound := if (needsMoreSamples(samplers, quality)) {
                    [for _ in (minimumCount..!maximumCount) { go() }]
                } else { [] }
                def [r, g, b, a] := [for s in (samplers) s.mean()]
                makeColor.RGB(r, g, b, a)
            }

    def sampler := config(makeSampler)

    return def discreteDrawable.pixelAt(x :Int, y :Int):
        "Take a filtered sample on a discrete 2D grid."
        return sampler(x, y)
