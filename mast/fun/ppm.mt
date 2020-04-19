import "lib/colors" =~ [=> makeColor]
import "lib/welford" =~ [=> makeWelford]
import "lib/vectors" =~ [=> V]
exports (makePPM)

# Pixel area: 4 / (w * h)
# Pixel radius: √(area / pi) = 2 / √(w * h * pi) = (2 / √pi) / √(w * h)
# This constant is the first half of that.
def R :Double := 2.0 / (0.0.arcCosine() * 2.0).squareRoot()

# XXX common code from lib/console, should move to its own module

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

# XXX these two tables should be generated from scratch, should be computed,
# but we don't have the Elusive Eight yet.
def chiTable :Map[Double, Double] := [
    0.5 => 5.35,
    0.7 => 7.23,
    0.8 => 8.56,
    0.9 => 10.64,
    0.95 => 12.59,
    0.99 => 16.81,
    0.999 => 22.46,
]

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
def minSamples :Int := 2
def maxSamples :Int := 1_000

def qualityCutoff :Double := chiTable[0.9]

def needsMoreSamples(samplers) as DeepFrozen:
    # They should all have the same count!
    def N := samplers[0].count()
    if (N < minSamples) { return true }
    if (N > maxSamples) { return false }

    # This fencepost is correct; -1 comes from Student's
    # t-distribution and degrees of freedom, and -1 comes from
    # 0-indexing vs 1-indexing.
    def tValue := if (N - 2 < tTable.size()) { tTable[N - 2] } else { tFinal }
    def variances := M.call(V, "run", [for s in (samplers) s.variance()],
                            [].asMap())
    def tTests := (variances / N).squareRoot()
    def pValues := tTests * tValue
    # https://en.wikipedia.org/wiki/Fisher's_method
    def fTest := sum(pValues.logarithm()) * -2
    if (N % 100 == 0):
        traceln(`N=$N t=$tTests p=$pValues f=$fTest q=$qualityCutoff`)
    # This f-test has 3 degrees of freedom, so we compare it
    # to the chi-squared table for 6 degrees.
    return fTest < qualityCutoff

# The plastic constant. This nice definition is exact for our Doubles.
def plastic :Double := {
    def s := 69.0.squareRoot()
    def f(x) { return (x / 18) ** (1 / 3) }
    f(9 + s) + f(9 - s)
}
def frac(x) as DeepFrozen:
    return x - x.floor()

# XXX alpha to coverage?
def makeSuperSampler(d) as DeepFrozen:
    # The two low-discrepancy sequences for 2D coordinates. The idea is that
    # we want some controlled de-correlation across different pixels, in order
    # to not have a tropic pattern from a fixed supersampling pattern mask. It
    # happens that this R2 sequence is optimal when folded back onto itself on
    # a single square, and it should similarly give very evenly-spaced but
    # constantly-shifting offsets.
    var c := V(plastic, plastic ** 2)
    return def superSampler.drawAt(x :Double, y :Double,
                                   => aspectRatio :Double,
                                   => pixelRadius :Double):
        def samplers := [makeWelford(), makeWelford(), makeWelford(),
                         makeWelford()]
        def draw(u, v):
            # NB: Work in linear RGB!
            def color := d.drawAt(u, v, => aspectRatio, => pixelRadius).RGB()
            for i => channel in (color) { samplers[i](channel) }
        # Unconditionally take one sample, because we were going to need at
        # least one sample.
        draw(x, y)
        while (needsMoreSamples(samplers)):
            # Jitter the coordinates to achieve quasirandom Monte Carlo.
            def [jx, jy] := V.un(V(x, y) + (c - 0.5) * pixelRadius, null)
            draw(jx, jy)
            c := frac(c + plastic)
        # XXX For funsies: Tint red based on number of samples required; tint
        # green based on average depth of samples. Red ranges from minSamples
        # to maxSamples. Green ranges from no reflections (0) to maxDepth. I
        # say "tint" but I've just done it with a lerp.
        # def sample := if (false) {
        #     def red := (sampler.count() - minSamples) / maxSamples
        #     def green := depthEstimator.mean() / maxDepth
        #     def tint := makeV3(red, green, 0.0)
        #     def sample := sampler.mean()
        #     (sample + (-sample + 1.0) * tint)
        # } else { sampler.mean() }
        # # Okay, *now* we clamp.
        # return sample.min(1.0).asColor()
        def [r, g, b, a] := [for s in (samplers) s.mean()]
        # NB: lib/colors does a premultiply here; I think we're *not*
        # premultiplied, so that this is correct.
        return makeColor.RGB(r, g, b, a)


def makePPM.drawingFrom(drawable) as DeepFrozen:
    "
    Draw from drawable/shader `d` repeatedly to form an image.
    "

    def d := makeSuperSampler(drawable)

    return def draw(width :(Int > 0), height :(Int > 0)):
        def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
        def body := [].diverge(0..!256)
        def aspectRatio :Double := width / height
        # See formula for the constant R.
        def pixelRadius :Double := R / (width * height).asDouble().squareRoot()
        var h := 0
        var w := 0

        return object drawingIterable:
            to next(ej):
                if (h >= height) { throw.eject(ej, "done") }
                def color := d.drawAt(w / width, h / height, => aspectRatio,
                                      => pixelRadius)
                def [r, g, b, _] := color.sRGB()
                body.push((255 * r).floor())
                body.push((255 * g).floor())
                body.push((255 * b).floor())
                w += 1
                if (w >= width):
                    w -= width
                    h += 1

            to finish():
                return preamble + _makeBytes.fromInts(body)
