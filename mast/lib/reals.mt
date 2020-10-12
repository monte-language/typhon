import "lib/ints" =~ [=> greatestCommonDenominator]
import "lib/doubles" =~ [=> dragon4]
exports (asDouble, simplify, makeReal)

# Computable real numbers, based on continued fractions. A real number is an
# iterable whose key => value pairs satisfy the continued function relation
#              k₀
# x = v₀ + ------------
#                 k₁
#          v₁ + -------
#                    k₂
#               v₂ + --
#                    ……
# For positive coefficients k₀, k₁, … and v₁, v₂, … the second term is
# positive, between 0 and 1, and can address any real number. (Caveat: basic
# reflection from the outside will show that we may only address computable
# real numbers in this way.) Note that if any k is 0, then iteration might as
# well stop, since the rest of the coefficients cannot contribute.
# NB: This is *not* the universal way to represent generalized continued
# fractions. Many sources do not have a k₀. Our preference here makes Gosper's
# algorithms simpler and Lentz's algorithm more complicated. Simple
# continued fractions will use k=1 either way.

# We may use Lentz's algorithm to incrementally compute Double approximants to
# real numbers.

def tiny :Double := 1e-30
def epsilon :Double := 1e-15

def asDouble(real) as DeepFrozen:
    def iter := real._makeIterator()
    def [a1, b0] := iter.next(null)
    var f :Double := b0.asDouble()
    if (f.isZero()) { f := tiny }
    var c :Double := f
    var d :Double := 0.0
    # If we're forced to work around a zero, then refuse to break for at least
    # one more iteration, to cancel it out.
    var canBreak := false
    # Each iteration involves a coefficient from the previous loop.
    var k := a1
    # Detect periods by examining c and d. Don't try too hard, but detect
    # basic fixed points.
    var pc := c
    var pd := d
    traceln("f", dragon4(f), "k", k, "f", f, "c", dragon4(c), "d", dragon4(d))
    for i in (0..!50):
        if (k.isZero()):
            # We're about to run out of digits, and we have exactly consumed
            # everything that we can consume; break.
            traceln("i", i, "f", dragon4(f), "out of digits")
            break
        # Carefully juggle the coefficients.
        def [na, b] := escape ej { iter.next(ej) } catch _ {
            # End of iteration. We've eaten all the digits; break.
            break
        }
        def a := k
        k := na
        c := b + a / c
        d := b + a * d
        if (c.isZero()) { c := tiny; canBreak := false }
        if (d.isZero()) { d := tiny; canBreak := false }
        d reciprocal= ()
        if (canBreak && pc == c && pd == d):
            # No precision problems and we're running in place; break.
            break
        def delta :Double := c * d
        if (canBreak && (1.0 - delta).abs() < epsilon):
            # No precision problems and delta no longer making a difference; break.
            break
        f *= delta
        traceln("i", i, "f", dragon4(f), "a", a, "b", b, "c", dragon4(c), "d", dragon4(d), "delta", dragon4(delta))
        canBreak := true
        pc := c
        pd := d
    return f

# We will often want to incrementally compute a particular real number once
# and for all, and we'd like to both compute it lazily and also share the
# computed coefficients among all callers (keeping cap-safety in mind, of
# course). To facilitate this, we embed pure expensive iterators into impure
# cheap iterables.

def indexed(f) as DeepFrozen:
    def cache := [].diverge()
    return def cachingIterable._makeIterator():
        var index :Int := 0
        return def cachingIterator.next(_ej):
            while (index >= cache.size()):
                cache.push(f(cache.size()))
            def rv := cache[index]
            index += 1
            return rv

# Gosper homographic functions in one argument let us take a real number x and
# four integer coefficients a, b, c, d, and compute the real number
#     a * x + b
# y = ---------
#     c * x + d
# Special cases of Gosper homographic functions include addition (and
# subtraction) by integer constants, multiplication (and division) by rational
# constants, negation, and reciprocation.

def homographic(a :Int, b :Int, c :Int, d :Int, x) as DeepFrozen:
    return def homographicIterable._makeIterator():
        var m := [a, b, c, d]
        def hungry():
            def [q, r, s, t] := m
            return s.isZero() || t.isZero() || (q // s != r // t)
        def xs := x._makeIterator()
        return def homographicIterator.next(ej):
            while (hungry()):
                # XXX this can lose several coefficients at the end of finite
                # inputs! Not great.
                def [k, v] := xs.next(ej)
                traceln("ingestion", "m", m, "k", k, "v", v)
                # Eat.
                def [q, r, s, t] := m
                m := [v * q + r, k * q, v * s + t, k * s]
            # Emit outgoing v = top = bottom.
            def bottom := m[0] // m[2]
            def [q, r, s, t] := m
            m := [s, t, q - s * bottom, r - t * bottom]
            # Simplify the matrix.
            def gcd := greatestCommonDenominator(
                greatestCommonDenominator(m[0].abs(), m[1].abs()),
                greatestCommonDenominator(m[2].abs(), m[3].abs()),
            )
            m := [for coeff in (m) coeff // gcd]
            traceln("egestion", "m", m, "gcd", gcd, "bottom", bottom)
            return [1, bottom]

def simplify(x) as DeepFrozen:
    "The real number `x`, but normalized to a simple continued fraction."

    return homographic(1, 0, 0, 1, x)

# Gosper bihomographic functions let us take two real numbers x and y, and
# four integer coefficients a, b, c, d, e, f, g, h, and compute
#     a * x * y + b * x + c * y + d
# z = -----------------------------
#     e * x * y + f * x + g * y + h
# Special cases of Gosper bihomographic functions include addition,
# subtraction, multiplication, and division of x and y.

# Rational numbers can be represented as finite lists of pairs. Only a small
# adaptation is required to make iteration work correctly.

def pairs(l :List) as DeepFrozen:
    return def pairIterable._makeIterator():
        def iter := l._makeIterator()
        return def pairIterator.next(ej):
            return iter.next(ej)[1]

object makeReal as DeepFrozen:
    "Real numbers."

    to e():
        "e, the base of the natural logarithm."

        return indexed(fn i {
            if (i.isZero()) { [1, 2] } else { [i, i] }
        })

    to phi():
        "φ, the golden ratio."

        return indexed(fn _ { [1, 1] })

    to pi():
        "π, the ratio of a circle's circumference to its diameter."

        return indexed(fn i {
            # if (i.isZero()) { [1, 3] } else { [(i * 2 + 1) ** 2, 6] }
            if (i.isZero()) { [4, 0] } else { [i ** 2, i * 2 - 1] }
        })

    # XXX wrong! But how? The coefficients are right, and Lentz's algorithm
    # doesn't seem pathological near the start...
    to cahen():
        "C, Cahen's constant."

        def a := [0, 1, 1].diverge()
        return def cahenIterable._makeIterator():
            var i := 0
            return def cahenIterator.next(_ej):
                while (i >= a.size()):
                    def x := a[a.size() - 2]
                    def y := a[a.size() - 1]
                    a.push(x * (1 + x * y))
                def rv := [1, a[i] ** 2]
                i += 1
                return rv

    to reciprocal(x):
        "The reciprocal of real number `x`."

        return homographic(0, 1, 1, 0, x)

    to fromRatio(var n :Int, var d :Int):
        "The real number `n/d`."

        def rv := [].diverge()

        while (!d.isZero()):
            def [divisor, remainder] := n.divMod(d)
            rv.push([1, divisor])
            n := d
            d := remainder

        rv.push([0, 1])
        return pairs(rv.snapshot())
