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

    return 0
