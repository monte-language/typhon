exports (cantor)

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
    # However, suppose p does not know that a potential neighborhood of n
    # samples is invalid until after n-1 samples have been taken, and only the
    # n'th sample causes us to take a false->true branch. Then we will have
    # wasted O(n) time. The resulting search tree checks O(2**n)
    # neighborhoods. This hopefully makes clear how we are doing NP-complete
    # searches ala SAT!
    var neigh := [].asMap()
    while (true):
        def n := escape ej {
            p(fn n { neigh.fetch(n, fn { ej(n) }) })
            # traceln("neigh", p, neigh)
            return neigh
        }
        def m := neigh.with(n, false)
        neigh := if (p(runNeighborhood(m))) { m } else { neigh.with(n, true) }

object cantor as DeepFrozen:
    "
    Search through functions from Cantor space.

    This object manipulates predicates on Cantor space to find their
    neighborhoods. More plainly but less precisely, this object works with
    functions which return Bools and themselves take functions from positive
    Ints to Bools; the former are called 'predicates' and the latter are
    'neighborhoods'.

    In general, search through Cantor space takes exponential time, and is
    known (by this module's author) to be NP-complete; size queries
    appropriately.
    "

    to forSome(p) :Bool:
        "Whether there is a neighborhood where the predicate `p` holds."

        return p(runNeighborhood(cantor.find(p)))

    to forEvery(p) :Bool:
        "Whether the predicate `p` holds in all neighborhoods."

        return !cantor.forSome(fn a { !p(a) })

    to find(p) :Neigh:
        "
        A neighborhood, if any, where the predicate `p` holds.

        There may be many satisfying neighborhoods, including smaller ones
        than the one which is found.

        The neighborhood is computed strictly, and may take forever to
        compute.
        "

        return findNeighborhood(p)

    to sameEver(f, g) :Bool:
        "
        Whether two predicates are extensionally equal.

        The predicates need not return Bools; they may return any objects
        comparable for equality.

        `f` and `g` will be called repeatedly with various arguments.
        "

        return cantor.forEvery(fn a { f(a) == g(a) })

    to modulus(f) :Int:
        "
        The size of neighborhoods needed to distinguish the behavior of the
        predicate `f`; `f`'s modulus of uniform continuity.

        Since `f` is assumed to be computably continuous, it can take at least
        as much time to determine the modulus as to find a witnessing
        neighborhood, and possibly much more.
        "

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
