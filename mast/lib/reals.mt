import "lib/doubles" =~ [=> dragon4]
exports (asDouble, makeReal)

# Computable real numbers, based on continued fractions. A real number is an
# iterable whose key => value pairs satisfy the continued function relation
#              k₁
# x = v₀ + ------------
#                 k₂
#          v₁ + -------
#                    k₃
#               v₂ + --
#                    ……
# For positive coefficients k₀, k₁, … and v₁, v₂, … the second term is
# positive, between 0 and 1, and can address any real number. (Caveat: basic
# reflection from the outside will show that we may only address computable
# real numbers in this way.)
# NB: k₀ is currently reserved.

# We may use Lentz's algorithm to incrementally compute Double approximants to
# real numbers.

def tiny :Double := 1e-30
def epsilon :Double := 1e-15

def asDouble(real) as DeepFrozen:
    var rv :Double := 1.0
    def iter := real._makeIterator()
    def [_a0, b0] := iter.next(null)
    var f :Double := b0.asDouble()
    if (f.isZero()) { f := tiny }
    var c :Double := f
    var d :Double := 0.0
    # for [a, b] in (real):
    traceln("f", dragon4(f), "b0", b0, "c", dragon4(c), "d", dragon4(d))
    for i in (0..!200):
        def [a, b] := iter.next(null)
        c := b + a / c
        d := b + a * d
        if (c.isZero()) { c := tiny }
        if (d.isZero()) { d := tiny }
        d reciprocal= ()
        def delta :Double := c * d
        if ((1.0 - delta).abs() < epsilon):
            traceln("i", i, "f", dragon4(f), "a", a, "b", b, "c", dragon4(c), "d", dragon4(d), "delta", dragon4(delta))
            break
        f *= delta
        if ((i % 10).isZero()):
            traceln("i", i, "f", dragon4(f), "a", a, "b", b, "c", dragon4(c), "d", dragon4(d), "delta", dragon4(delta))
    return f

# We will often want to incrementally compute a particular real number once
# and for all, and we'd like to both compute it lazily and also share the
# computed coefficients among all callers (keeping cap-safety in mind, of
# course). To facilitate this, we embed pure expensive iterators into impure
# cheap iterables.

def iterable(f) as DeepFrozen:
    def cache := [].diverge()
    return def cachingIterable._makeIterator():
        var index :Int := 0
        return def cachingIterator.next(_ej):
            while (index >= cache.size()):
                cache.push(f(cache.size()))
            def rv := cache[index]
            index += 1
            return rv

object makeReal as DeepFrozen:
    "Real numbers."

    to e():
        "e, the base of the natural logarithm."

        return iterable(fn i {
            if (i.isZero()) { [0, 2] } else { [i + 1, i + 1] }
        })

    to phi():
        "φ, the golden ratio."

        return iterable(fn _ { [1, 1] })

    to pi():
        "π, the ratio of a circle's circumference to its diameter."

        return iterable(fn i {
            switch (i) {
                match ==0 { [null, 0] }
                match ==1 { [4, 1] }
                match _ { [(i - 1) ** 2, i * 2 - 1] }
            }
        })
