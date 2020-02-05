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
    var R :Int := f << 0.max(e - p)
    var S :Int := 1 << 0.max(p - e)
    var Mp :Int := 1 << 0.max(e - p)
    var Mm :Int := Mp
    # Begin the simple fixup.
    if (f == 1 << p - 1):
        Mp <<= 1
        R <<= 1
        S <<= 1
    var k := 0
    # XXX no .ceiling()
    while (R < (S / B).floor() + 1):
        k -= 1
        R *= B
        Mp *= B
        Mm *= B
    while ((R << 1) + Mp >= S << 1):
        S *= B
        k += 1
    # End the simple fixup.

    def [var U :Int, _r] := (R * B).divMod(S)
    R := _r
    Mm *= B
    Mp *= B
    var low :Bool := R << 1 < Mm
    var high :Bool := R << 1 > 2 * S - Mp
    var final :Bool := false
    def digiterator.next(ej):
        # Main loop: Produce another digit.
        if (!low & !high):
            def rv := [k, U]
            k -= 1
            def [u, r] := (R * B).divMod(S)
            U := u
            R := r
            Mm *= B
            Mp *= B
            low := R << 1 < Mm
            high := R << 1 > 2 * S - Mp
            return rv
        # Final digit.
        if (final):
            throw.eject(ej, "Out of digits")
        def rv := if (low &! high) {
            [k, U]
        } else if (high &! low) {
            [k, U + 1]
        } else if (low & high) {
            [k, if (2 * R >= S) { U + 1 } else { U }]
        }
        final := true
        return rv
    return [k -= 1, digiterator]

def dragon4(d :Double) :Str as DeepFrozen:
    def [normal, e] := d.normalizedExponent()
    return exceptions.fetch(normal, fn {
        # normal ≠ 0.0
        def [var H, digits] := ::"(FPP)²"((normal * (2.0 ** p)).floor(), e)
        # Eat some 0. We must have at least one digit available.
        var head := digits.next(null)
        while (head[1].isZero()) { head := digits.next(__break) }
        # Either head is non-zero, or we're out of digits. But we can't be out
        # of digits with just zeroes, because we eliminated 0.0 as a
        # possibility, so either way, head is the correct first digit.
        H := head[0]
        def l := ['0' + head[1], '.'].diverge()
        while (true) { l.push('0' + digits.next(__break)[1]) }
        # We may have to pad with 0, though, because we munched so hard.
        if (l.last() == '.') { l.push('0') }
        l.push('e')
        _makeStr.fromChars(l) + `$H`
    })
