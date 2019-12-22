exports (findNeighborhood, cantor)

# "Seemingly impossible" search through Cantor space.
# http://math.andrej.com/2007/09/28/seemingly-impossible-functional-programs/

def N :DeepFrozen := Int >= 0
def Neigh :DeepFrozen := Map[N, Bool]

# Based on effect-oriented style in video at
# http://math.andrej.com/2011/12/06/how-to-make-the-impossible-functionals-run-even-faster/
def runNeighborhood(m :Neigh) as DeepFrozen:
    return def neigh(n :N) :Bool { return m.fetch(n, &true.get) }

def findNeighborhood(p) :Neigh as DeepFrozen:
    # AFAIK this is the only such arrangment of this algorithm, so I'd better
    # explain it.
    # We iteratively look for more-and-more precise neighborhoods of p. Each
    # time p wants a sample from Cantor space at the point n, we give it what
    # it wants, first trying false and then trying true.
    # Suppose p needs n samples to specify its neighborhood. Then we run p
    # once per sample to discover the next point, and once per sample to test
    # whether the point should be false, giving exactly 2n => O(n) runtime.
    var neigh := [].asMap()
    while (true):
        def n := escape ej {
            p(fn n { neigh.fetch(n, fn { ej(n) }) })
            traceln("neigh", p, neigh)
            return neigh
        }
        def m := neigh.with(n, false)
        neigh := if (p(runNeighborhood(m))) { m } else { neigh.with(n, true) }

object cantor as DeepFrozen:
    to forSome(p) :Bool:
        return p(cantor.find(p))

    to forEvery(p) :Bool:
        return !cantor.forSome(fn a { !p(a) })

    to find(p):
        return runNeighborhood(findNeighborhood(p))

    to sameEver(f, g) :Bool:
        "
        Whether two functions out of the Cantor space are equal.

        Both `f` and `g` ought to have a .run/1 which takes a function from
        the natural numbers to the Booleans. They may return any type, but the
        return values ought to be comparable for equality.

        `f` and `g` both may be called repeatedly with various arguments.
        "

        return cantor.forEvery(fn a { f(a) == g(a) })

    to modulus(f) :Int:
        def least(p) :Int:
            var rv := 0
            while (!p(rv)) { rv += 1 }
            return rv
        def eq(n, a, b) :Bool:
            for i in (0..!n):
                if (a(i) != b(i)) { return false }
            return true
        return least(fn n {
            cantor.forEvery(fn a {
                cantor.forEvery(fn b { !eq(n, a, b) || f(a) == f(b) })
            })
        })
