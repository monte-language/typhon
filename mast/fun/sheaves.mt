exports (main)

interface Sheaf :DeepFrozen:
    to stalk(x) :Set:
        "The stalk of this sheaf in the neighborhood of `x`."

    to section(u :Set) :Set:
        "The section of this sheaf on the open set `u`."

    to restriction(u :Set, v :Set) :Map:
        "The restriction map from `u` to `v`."

def union(sets :List[Set]) :Set as DeepFrozen:
    var rv := [].asSet()
    for s in (sets):
        rv |= s
    return rv

def makeASC(vertices :Set, facets :Set) as DeepFrozen:
    def space :Set := {
        var rv := facets
        def stack := facets.asList().diverge()
        while (!stack.isEmpty()) {
            def s := stack.pop()
            for ex in (s) {
                def subset := s.without(ex)
                if (!rv.contains(subset)) {
                    rv with= (subset)
                    stack.push(subset)
                }
            }
        }
        rv
    }
    return object abstractSimplicialComplex:
        to vertices():
            return vertices

        to star(simplex :Set) :Set:
            return [for s in (space) ? (simplex <= s) s].asSet()

def main(_) as DeepFrozen:
    def baseSections := [
        ['x'].asSet() => [0].asSet(),
        ['y'].asSet() => [1].asSet(),
        ['z'].asSet() => [2].asSet(),
    ]

    # Can be empty here, because identity restrictions are handled separately.
    def baseRestrictions := [
    ].asMap()

    object basisSheaf as Sheaf:
        to stalk(x) :Set:
            return union([for basis => section in (baseSections)
                          ? (basis.contains(x))
                          section])

        to section(u :Set) :Set:
            return baseSections.fetch(u, fn {
                union([for basis => section in (baseSections)
                       ? (basis <= u)
                       section])
            })

        to restriction(u :Set, v :Set ? (v <= u)) :Map:
            return if (u <=> v) { [for x in (u) x => x] } else {
                baseRestrictions[[u, v]]
            }

    def globalSection():
        def cover := union(baseSections.getKeys())
        return basisSheaf.section(cover)

    traceln(`Stalk at 'x' is ${basisSheaf.stalk('x')}`)
    traceln(`Section at {'x', 'y'} is ${basisSheaf.section(['x', 'y'].asSet())}`)
    traceln(`Global section is ${globalSection()}`)

    def asc := makeASC([1, 2, 3, 4, 5].asSet(), [
        [1, 2].asSet(),
        [1, 3].asSet(),
        [3, 4].asSet(),
        [2, 3, 5].asSet(),
    ].asSet())
    traceln(asc.star([3].asSet()))
    traceln(asc.star([2].asSet()))

    return 0
