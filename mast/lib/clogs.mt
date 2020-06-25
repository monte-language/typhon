import "lib/ints" =~ [=> greatestCommonDenominator]
exports (makeCLog)

# https://arxiv.org/abs/1606.06984

# Continued logarithms, expressed in binary, are an extremely compact way to
# represent sparse numbers with extreme magnitudes and relatively few
# significant digits of precision. Gosper originally suggested them as an
# alternative to continued fractions (to our lib/continued) for certain sorts
# of scientific and engineering work; in particular, they seem apt for
# metrology and other instances of exact rational arithmetic.

# A (binary) continued logarithm is a real number. We model them as Monte
# iterables. When iterated, they yield i => x pairs, where i is the
# traditional Int index and x is a Bool.

# Every representation has some fast operations. What are fast operations for
# binary continued logarithms?
# +1 to first coefficient => *2

# We define several transformations. Normally, for compactness, we will want
# to coalesce multiple consecutive true bits into a single datum using
# run-length encoding, giving a list of Ints. This also allows us to give a
# leading negative coefficient, which extends the system down into the unit
# interval.

def coalesce(iterable) as DeepFrozen:
    return def coalescingIterable._makeIterator():
        def iterator := iterable._makeIterator()
        var k :Int := 0
        var done :Bool := false
        return def coalescingIterator.next(ej):
            if (done) { throw.eject(ej, "no more digits") }
            var acc :Int := 0
            escape inner:
                while (iterator.next(inner)[1]) { acc += 1 }
            catch _:
                done := true
            def rv := [k, acc]
            k += 1
            return rv

# Rational numbers are given by repeatedly spinning a rational pair p/q until
# it arrives at 1.

def rational(numerator :Int, denominator :Int) as DeepFrozen:
    # Fast algorithm: Compute entire runs at once by abusing .bitLength() to
    # compute quick log2.
    return def rationalIterable._makeIterator():
        var p :Int := numerator
        var q :Int := denominator
        var k :Int := 0
        return def rationalIterator.next(ej):
            # traceln(`p / q $p / $q`)
            if (q.isZero() || p == q) { throw.eject(ej, "No more digits") }
            # Find the multiplier for q.
            def v := (p // q).bitLength() - 1
            def rv := [k, v]
            k += 1
            q *= 2 ** v
            # Update state.
            def nq := p - q
            p := q
            q := nq
            # Eat powers of two.
            while ((p & 1).isZero() && (q & 1).isZero()) { p >>= 1; q >>= 1 }
            return rv

# Quadratic surds require a four-number support structure. We implement them
# with the "monster" algorithm which operates on generalized surds and their
# support structures all at once.

def monster(n :(Int > 1), var p :Int, var q :Int, var c :Int,
            var d :Int) as DeepFrozen:
    "Return digits for (p/q)(c+d√n) exactly and quickly."
    if (d == 0) { return rational(p * c, q) }
    var k := 0
    return def fastSurdIterator.next(ej) {
        # traceln(`(p / q)(c + d√n) ($p / $q)($c + $d√$n)`)
        # Sign parity of d determines operations.
        def signParity := d.aboveZero()
        # Is x ≥ 2?
        def c1 := n * (d ** 2) * (p ** 2)
        def c2 := (q - c * p) ** 2
        if (signParity == c2.aboveZero() && c1 == c2) {
            throw.eject(ej, "No more digits")
        }
        def c3 := (2 * q - c * p) ** 2
        def v := if (signParity) {
            c2.belowZero() || c1 >= c3
        } else {
            c2.belowZero() && c1 <= c3
        }
        def rv := [k, v]
        k += 1
        # Update state.
        if (v) { q *= 2 } else {
            def t := c * p - q
            c := t
            d *= -p
            p := q
            q := (t ** 2) - c1
        }
        # Ensure p and q are positive.
        if (q.belowZero()) { q := -q; p := -p }
        if (p.belowZero()) { p := -p; c := -c; d := -d }
        # Simplify c and d.
        if (!c.isZero() && !d.isZero()) {
            def f1 := greatestCommonDenominator(c.abs(), d.abs())
            c //= f1
            d //= f1
            p *= f1
        }
        # Simplify p and q.
        def f2 := greatestCommonDenominator(p, q)
        p //= f2
        q //= f2
        return rv
    }

# Homographic functions, of the form (ax+b)/(cx+d) with all constants
# integers, can be applied. Examples:
# a=1, c=0, d=1: addition by b
# b=0, c=0, d=1: multiplication by a
# b=0, c=0: multiplication by a/d
# a=0, b=1, c=1, d=0: reciprocal
# If we take this as a matrix,
# [ a b ]
# [ c d ]
# Then any composition of such matrices is also homographic.

def homographic(var a :Int, var b :Int, var c :Int, var d :Int, iterable) as DeepFrozen:
    var k :Int := 0
    return def homographicIterable._makeIterator():
        def iterator := iterable._makeIterator()
        return def homographicIterator.next(ej):
            # We will check not just that d and c+d have the same sign, but
            # also that top >= 2 iff bottom >=2.
            while (true):
                # First, sign check. Are we even facing the same
                # direction? And, can we divide?
                if (!c.isZero() && !(c + d).isZero() &&
                    d.aboveZero() == (c + d).aboveZero()):
                    def top := (a + b) // (c + d)
                    def bottom := a // c
                    # We need top ≥ 2 iff bottom ≥ 2, or
                    # 1 < top < 2 iff 1 < bottom < 2. But since top and bottom
                    # are computed with integer maths, the latter case means
                    # that top == bottom == 1.
                    if ((top >= 2 && bottom >= 2) ||
                        (top == 1 && bottom == 1)):
                        # We are settled enough to egest.
                        break
                # We're not settled; we need at least one more digit. If
                # upstream is finished, then so are we.
                # traceln(`ingest (${a}x + $b)/(${c}x + $d)`)
                def n := iterator.next(ej)[1]
                # Ingest n 1s.
                a *= 2 ** n
                c *= 2 ** n
                # Ingest 0: a -1 and reciprocation.
                var t := a + b
                b := a
                a := t
                t := c + d
                d := c
                c := t
            # Egest.
            def v := (a // c) >= 2
            # traceln(`egest (${a}x + $b)/(${c}x + $d) -> $v`)
            def rv := [k, v]
            k += 1
            # Update the matrix.
            if (v):
                c *= 2
                d *= 2
            else:
                var t := a - c
                a := c
                c := t
                t := b - d
                b := d
                d := t
            # And remove extra factors.
            def f := greatestCommonDenominator(
                greatestCommonDenominator(a, b),
                greatestCommonDenominator(c, d))
            a //= f
            b //= f
            c //= f
            d //= f
            return rv

object makeCLog as DeepFrozen:
    to fromRational(n :Int, d :Int):
        "An iterator over the continued logarithm of `n / d`."

        # XXX might not be necessary/useful?
        def f := greatestCommonDenominator(n, d)
        return rational(n // f, d // f)

    to fromSurd(n :(Int > 1)):
        "An iterator over the continued logarithm of √n."

        def surdIterable._makeIterator():
            return monster(n, 1, 1, 0, 1)
        return coalesce(surdIterable)

    to fromQuadraticExpression(p :(Int > 0), q :(Int > 0), c :Int, d :Int,
                               n :(Int > 0)):
        "
        An iterator over the continued logarithm of (p/q)(c+d√n).

        Every quadratic equation's solution is of this form; given
        ax² + bx + c, the solutions are (1/2a)(-b±1√(b²-4ac)).
        "

        def quadraticIterable._makeIterator():
            return monster(n, p, q, c, d)
        return coalesce(quadraticIterable)

    to linearTransformation(a :Int, b :Int, c :Int, d :Int):
        "
        Apply the linear transformation (ax+b)/(cx+d) to a continued
        logarithm.
        "

        return def linearTransformation(x) as DeepFrozen:
            return coalesce(homographic(a, b, c, d, x))

    to fromDouble(x :Double):
        "
        An iterator over the continued logarithm of `x`.

        Digits may continue forever, even though they are no longer exact after a
        certain point.
        "

        return def doubleIterable._makeIterator():
            var next :Double := x
            var i :Int := 0
            return def doubleIterator.next(ej):
                if (next == 1.0 || next == Infinity):
                    throw.eject(ej, "No more digits")
                # Fast algorithm: Use .normalizedExponent() to break the
                # Double apart, and retrieve the exponent exactly.
                def [n :Double, e :Int] := next.normalizedExponent()
                def rv := [i, e - 1]
                next := ((n * 2.0) - 1.0).reciprocal()
                i += 1
                return rv
