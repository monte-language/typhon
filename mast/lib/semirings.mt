import "lib/iterators" =~ [=> zip]
exports (booleanSemiring, makeMatrixSemiring)

# http://stedolan.net/research/semirings.pdf

object booleanSemiring as DeepFrozen:
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