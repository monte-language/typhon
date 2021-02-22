```
import "lib/iterators" =~ [=> zip]
import "lib/proptests" =~ [=> arb, => prop]
import "unittest" =~ [=> unittest :Any]
exports (
    booleanSemiring,
    probabilitySemiring, viterbiSemiring,
    tropicalSemiring,
    makeSetMonoidSemiring,
    makeMatrixSemiring,
)
```

# Semirings

A [semiring](https://en.wikipedia.org/wiki/Semiring) is an algebraic structure
upon some collection of objects. They originally generalized the natural
numbers, and so the terminology is still number-oriented:
* An *addition* combines two objects in an associative and commutative way
* A *multiplication* piles two objects up in an associative way
* Multiplication distributes over addition
* A *zero* does nothing when used in addition
* A *one* does nothing when used in multiplication

The number-oriented intuition comes from the fact that, for any element `a` of
the semiring:

    a = a + 0 = 1 × (a + 0) = 1 × a + 1 × 0 = a + 0 = a

However, aside from this, the structure of semirings can diverge greatly from
intuition. In particular, multiplication might not commute. When it does,
we'll say that those semirings are commutative. We may also have a *closure*
operation, denoted with a star, which has the following axiom:

    a* = 1 + a × a* = 1 + a* × a

We'll say that those semirings are closed. Some sources, particularly
Wikipedia, call these star semirings instead, due to the notation.

To test whether we've implemented each semiring properly, we'll use property
tests. There are eight axioms to check, plus one extra axiom if the semiring
is closed. We allow each semiring to not just provide its own generator of
elements, but also a strategy for comparing them.

```
def semiringProperties(sr, gen, compare, => closed :Bool) as DeepFrozen:
    def cmp := switch (compare) {
        match =="sameEver" { fn hy, x, y { hy.sameEver(x, y) } }
        match =="asBigAs" { fn hy, x, y { hy.asBigAs(x, y) } }
        match =="epsilon" { fn hy, x, y { hy.assert((x - y).abs() < 1e-7) } }
    }
    # NB: We use .asBigAs/2 instead of .sameEver/2 because we will be testing
    # ordered sets for equality. We could configure this with a flag if it
    # negatively impacts test quality. ~ C.
    def semiringAdditionCommutative(hy, a, b):
        cmp(hy, sr.add(a, b), sr.add(b, a))
    def semiringAdditionAssociative(hy, a, b, c):
        cmp(hy, sr.add(a, sr.add(b, c)), sr.add(sr.add(a, b), c))
    def semiringAdditionZero(hy, a):
        cmp(hy, sr.add(a, sr.zero()), a)
    def semiringMultiplicationAssociative(hy, a, b, c):
        cmp(hy, sr.multiply(a, sr.multiply(b, c)),
                sr.multiply(sr.multiply(a, b), c))
    def semiringMultiplicationZero(hy, a):
        cmp(hy, sr.multiply(a, sr.zero()), sr.zero())
        cmp(hy, sr.multiply(sr.zero(), a), sr.zero())
    def semiringMultiplicationOne(hy, a):
        cmp(hy, sr.multiply(a, sr.one()), a)
        cmp(hy, sr.multiply(sr.one(), a), a)
    def semiringMultiplicationDistributive(hy, a, b, c):
        cmp(hy, sr.multiply(a, sr.add(b, c)),
                sr.add(sr.multiply(a, b), sr.multiply(a, c)))
        cmp(hy, sr.multiply(sr.add(a, b), c),
                sr.add(sr.multiply(a, c), sr.multiply(b, c)))
    def semiringClosure(hy, a):
        cmp(hy, sr.closure(a),
                sr.add(sr.one(), sr.multiply(sr.closure(a), a)))
        cmp(hy, sr.closure(a),
                sr.add(sr.one(), sr.multiply(a, sr.closure(a))))
    return [
        prop.test([gen(), gen()], semiringAdditionCommutative),
        prop.test([gen(), gen(), gen()], semiringAdditionAssociative),
        prop.test([gen()], semiringAdditionZero),
        prop.test([gen(), gen(), gen()], semiringMultiplicationAssociative),
        prop.test([gen()], semiringMultiplicationZero),
        prop.test([gen()], semiringMultiplicationOne),
        prop.test([gen(), gen(), gen()], semiringMultiplicationDistributive),
    ] + if (closed) { [prop.test([gen()], semiringClosure)] } else { [] }
```

The semirings we implement include selections from [Fun with
Semirings](http://stedolan.net/research/semirings.pdf) by Dolan and [Semiring
Parsing](https://www.aclweb.org/anthology/J99-4004.pdf) by Goodman.

## Booleans

The smallest interesting semiring is on the Booleans. This semiring is
commutative and closed.

```
object booleanSemiring as DeepFrozen:
    "The Boolean semiring."

    to zero():
        return false

    to one():
        return true

    to closure(_):
        return true

    to add(left, right):
        return left | right

    to multiply(left, right):
        return left & right

unittest(
    semiringProperties(booleanSemiring, arb.Bool, "sameEver", "closed" => true)
)
```

## Probabilities

We consider several probability semirings. The first one is the standard
probability semiring, sometimes called "inside probability" as in Goodman.
This semiring has high dynamic range for probabilities. The closure of `x`
gives the sum of a geometric series starting at 1 and with a ratio of
convergence `x`, or ∞ when the series would diverge.

```
object probabilitySemiring as DeepFrozen:
    "The semiring of probabilities represented as Doubles."

    to zero():
        return 0.0

    to one():
        return 1.0

    to add(l, r):
        return l + r

    to multiply(l, r):
        return l * r

    to closure(a):
        return if (a < 1.0) { (1.0 - a).reciprocal() } else { Infinity }

def arbUnitInterval():
    return object unitInterval:
        to arbitrary(entropy):
            return entropy.nextDouble()
        to shrink(_):
            return []

unittest(
    semiringProperties(probabilitySemiring, arbUnitInterval, "epsilon", "closed" => true)
)
```

Another useful probability semiring is the Viterbi semiring, which corresponds
to a different notion of likelihood. It is not closed.

```
object viterbiSemiring as DeepFrozen:
    to zero():
        return 0.0

    to one():
        return 1.0

    to add(l, r):
        return l.max(r)

    to multiply(l, r):
        return l * r

unittest(
    semiringProperties(viterbiSemiring, arbUnitInterval, "epsilon", "closed" => false)
)
```

## Tropical Analysis

The [tropical semiring](https://en.wikipedia.org/wiki/Tropical_semiring), also
called the min-plus semiring because of its addition and multiplication, is a
setting for doing a certain kind of path-counting where some paths are
unreachable.

```
object tropicalSemiring as DeepFrozen:
    "The tropical semiring. Specifically, the min-plus variant."

    to zero():
        return null

    to one():
        return 0

    to add(l, r):
        return if (l == null) { r } else if (r == null) { l } else {
            l.min(r)
        }

    to multiply(l, r):
        # NB: One-armed if-expr abuse. ~ C.
        return if (l != null && r != null) { l + r }

    to closure(_):
        return 0

def arbMaybeNat():
    return object nat extends arb.NullOk(arb.Int("ceiling" => 10)):
        to arbitrary(entropy):
            def x := super.arbitrary(entropy)
            return if (x != null) { x.abs() }

unittest(
    semiringProperties(tropicalSemiring, arbMaybeNat, "sameEver", "closed" => true)
)
```

## Sets on Monoids

Given a monoid, there is a semiring on sets of elements of the monoid:
* The zero is the empty set
* The one is the set with the monoid's one
* Addition is set union
* Multiplication is the monoidal product of the Cartesian product

If the monoid is commutative, then so is the semiring.

Not yet implemented: If the monoid has finite order height, then the semiring
can be closed. The closure iteratively proceeds using the recurrence:

    a* = 1 + a × a*

The recurrence would start with the value `1 + a` and terminate when equal.

```
def makeSetMonoidSemiring(monoid :DeepFrozen) as DeepFrozen:
    "The semiring on sets of elements of `monoid`."

    return object setMonoidSemiring as DeepFrozen:
        to zero():
            return [].asSet()

        to one():
            return [monoid.one()].asSet()

        to add(left, right):
            return left | right

        to multiply(left, right):
            def rv := [].asSet().diverge()
            for l in (left):
                for r in (right):
                    rv.include(monoid.multiply(l, r))
            return rv.snapshot()
```

And we'll define a little numeric monoid for testing purposes. The list monoid
would work as well, but this multiplication monoid has much shorter test
failure messages!

```
object testMonoid as DeepFrozen:
    to one():
        return 1

    to multiply(l, r):
        return l * r

unittest(
    semiringProperties(makeSetMonoidSemiring(testMonoid),
                       fn { arb.Set(arb.Int("ceiling" => 10)) },
                       "asBigAs",
                       "closed" => false))
```

## Matrices

Given a semiring, the square matrices of elements also form semirings. When
the semiring is closed, then so are the semirings of matrices.

For a particular closed semiring of matrices, we can solve affine mappings of
the form `x = Ax + B` given `A` and `B`, as if we were doing linear algebra.

```
def makeMatrixSemiring(semiring :DeepFrozen, n :(Int > 0)) as DeepFrozen:
    "The closed semiring of `n` × `n` matrices of elements of `sr`."

    def sum(xs) as DeepFrozen:
        var rv := semiring.zero()
        for x in (xs):
            rv := semiring.add(rv, x)
        return rv

    # We're going to do column-major addressing:
    # [ 0 3 6 ]
    # [ 1 4 7 ]
    # [ 2 5 8 ]

    return object matrixSemiring as DeepFrozen:
        "
        A closed semiring of matrices on a closed semiring.

        This closed semiring features closure, and additionally can solve
        affine maps.
        "

        to zero() :List:
            return [semiring.zero()] * n ** 2

        to one() :List:
            def diagonals := [for i in (0..!n) i ** 2]
            return [for i in (0..!n ** 2) if (diagonals.contains(i)) {
                semiring.one()
            } else { semiring.zero() }]

        to closure(x :List) :List:
            # Lehmann's algorithm.
            # https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.71.7650&rep=rep1&type=pdf
            var a := x
            for k in (0..!n):
                a := [for index => val in (a) {
                    def [i, j] := index.divMod(n)
                    semiring.add(val, semiring.multiply(a[i * n + k],
                        semiring.multiply(semiring.closure(a[k + k * n]),
                            a[k * n + j])))
                }]
            return matrixSemiring.add(matrixSemiring.one(), a)

        to add(left :List, right :List) :List:
            return [for [x, y] in (zip(left, right)) semiring.add(x, y)]

        to multiply(left :List, right :List) :List:
            def rv := [].diverge()
            for i in (0..!n):
                for j in (0..!n):
                    rv.push(sum([for k in (0..!n) {
                        semiring.multiply(left[i * n + k], right[k * n + j])
                    }]))
            return rv.snapshot()

        to solveAffineMap(a :List, var b :List) :List:
            "
            Solve an affine mapping of the form x = Ax + B.

            `b` need not be square; it may be as thin as a single column or as
            wide as a square. The solution will be as wide as `b`.
            "

            # Stretch b to be square.
            def stride := b.size() // n
            if (stride < n) { b += [semiring.zero()] * (n * (n - stride)) }
            traceln(`sizes ${a.size()} ${b.size()}`)
            # Construct the solution.
            def rv := matrixSemiring.multiply(matrixSemiring.closure(a), b)
            # And unstretch.
            return rv.slice(0, n * stride)
```
