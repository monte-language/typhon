exports (dragon4)

# All about Doubles!

# Dragon4, see https://lists.nongnu.org/archive/html/gcl-devel/2012-10/pdfkieTlklRzN.pdf

# NB: .normalizedExponent() returns a Double for mantissa. This Double is
# in 0.5..!1, if it's not one of the following exceptions. The original
# Dragon4 is phrased in terms of this mantissa being instead a binary
# fraction, and we will have to adjust accordingly.

def exceptions :Map[Double, Str] := [
    -0.0      => "-0.0",
    0.0       => "0.0",
    -Infinity => "-∞",
    Infinity  => "∞",
    NaN       => "NaN",
]

# The precision of Doubles.
# In the equation v = f * b**(e - p), rearrange to get:
# v = f / b**p * b**e
# So this is the fixed amount of precision left in the binary fraction
# returned by .normalizedExponent().
def p :Int := 53

# The output base.
def B :Int := 10

def ::"(FPP)²"(f :Int, e :Int) as DeepFrozen:
    # f ≠ 0.0
    def D := [].asMap().diverge(Int, Int)
    var R :Int := f << 0.max(e - p)
    var S :Int := 1 << 0.max(p - e)
    var Mp :Int := 1 << 0.max(e - p)
    var Mm :Int := Mp
    # Begin the simple fixup.
    if (f == 1 << p - 1) {
        Mp <<= 1
        R <<= 1
        S <<= 1
    }
    var k := 0
    # XXX no .ceiling()
    while (R < (S / B).floor() + 1) {
        k -= 1
        R *= B
        Mp *= B
        Mm *= B
    }
    while ((R << 1) + Mp >= S << 1) {
        S *= B
        k += 1
    }
    # End the simple fixup.
    def H :Int := k - 1
    # NB: Monte doesn't have do-while loops, so this is partially unrolled.
    k -= 1
    def [var U :Int, _r] := (R * B).divMod(S)
    R := _r
    Mm *= B
    Mp *= B
    var low :Bool := R << 1 < Mm
    var high :Bool := R << 1 > 2 * S - Mp
    while (!low & !high) {
        D[k] := U
        k -= 1
        def [u, r] := (R * B).divMod(S)
        U := u
        R := r
        Mm *= B
        Mp *= B
        low := R << 1 < Mm
        high := R << 1 > 2 * S - Mp
    }
    if (low &! high) {
        D[k] := U
    } else if (high &! low) {
        D[k] := U + 1
    } else if (low & high) {
        if (2 * R <= S) { D[k] := U }
        if (2 * R >= S) { D[k] := U + 1 }
    }
    def N := k
    return [H, N, D.snapshot()]

def dragon4(d :Double) :Str as DeepFrozen:
    def [normal, e] := d.normalizedExponent()
    return exceptions.fetch(normal, fn {
        # normal ≠ 0.0
        def [H, _N, D] := ::"(FPP)²"((normal * (2.0 ** p)).floor(), e)
        def [head] + tail := [for v in (D.getValues()) '0' + v]
        _makeStr.fromChars([head, '.'] + tail + ['e']) + `$H`
    })
