exports (main)

interface Sheaf :DeepFrozen:
    to stalkAt(u :Set) :Set:
        "The stalk of this sheaf in the neighborhood of `u`."

    to sectionAt(assignment :Map[Set, Any], ej) :Map[Set, Any]:
        "
        Validate and complete a section with a given `assignment` of values
        to subsets of this sheaf.
        "

    to restriction(u :Set, v :Set) :Map:
        "The restriction map from `u` to `v`."

def union(sets :List[Set]) :Set as DeepFrozen:
    var rv := [].asSet()
    for s in (sets):
        rv |= s
    return rv

def makeASC(vertices :Map, facets :Set) as DeepFrozen:
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
    def defaultRestrictions :Map[Pair[Set, Set], Any] := {
        # NB: Can't have subsets of singleton sets.
        def m := [for u in (space) ? (u.size() > 1) u => {
            def positions := [for i => x in (u) x => i]
            def patt := astBuilder.ListPattern([for i => _x in (u) {
                # XXX need to get the guards from `vertices` into here
                # somehow.
                astBuilder.FinalPattern(astBuilder.NounExpr(`x$i`, null),
                                        null, null)
            }], null, null)
            [for v in (space) ? (v <= u) v => {
                def body := astBuilder.ListExpr([for x in (v) {
                    astBuilder.NounExpr(`x${positions[x]}`, null)
                }], null)
                eval(m`fn $patt { $body }`.expand(), safeScope)
            }]
        }]
        def rv := [].asMap().diverge()
        for u => vs in (m) {
            for v => res in (vs) {
                rv[[u, v]] := res
            }
        }
        rv.snapshot()
    }
    return object abstractSimplicialComplex:
        to vertices():
            return vertices

        to star(simplex :Set) :Set:
            return [for s in (space) ? (simplex <= s) s].asSet()

        to flabbySheaf():
            return abstractSimplicialComplex.sheaf(defaultRestrictions)

        to sheaf(restrictions :Map[Pair[Set, Set], Any]):
            def resIndex := {
                def rv := [].asMap().diverge()
                for [u, v] => res in (restrictions) {
                    if (!rv.contains(u)) { rv[u] := [].diverge() }
                    rv[u].push([v, res])
                }
                [for k => v in (rv) k => v.snapshot()]
            }
            return object abstractSheaf as Sheaf:
                to stalkAt(u :Set):
                    return [for x in (u) vertices[x]]

                to sectionAt(assignment :Map[Set, Any], ej) :Map[Set, Any]:
                    def fullSection := assignment.diverge()
                    def stack := assignment.getKeys().diverge()
                    # For all u in the assignment, recursively look for u -> v
                    # in the provided restrictions, and include v in the
                    # assignment.
                    while (!stack.isEmpty()):
                        def u := stack.pop()
                        for [v, res] in (resIndex.fetch(u, fn { [] })):
                            def val := res(fullSection[u])
                            if (fullSection.contains(v)):
                                # Check consistency.
                                if (!(fullSection[v] <=> val)):
                                    throw.eject(ej, `Section $assignment couldn't be extended to include $v because ${fullSection[v]} != $val`)
                            else:
                                fullSection[v] := val
                                stack.push(v)
                    return fullSection.snapshot()

                to restriction(u :Set, v :Set):
                    return restrictions[[u, v]]

def main(_) as DeepFrozen:
    def asc := makeASC([for x in ([1, 2, 3, 4, 5]) x => Int], [
        [1, 2].asSet(),
        [1, 3].asSet(),
        [3, 4].asSet(),
        [2, 3, 5].asSet(),
    ].asSet())
    traceln(asc.star([3].asSet()))
    traceln(asc.star([2].asSet()))

    def sheaf := asc.flabbySheaf()
    traceln(sheaf)
    traceln(sheaf.stalkAt([2, 3, 5].asSet()))
    traceln(sheaf.sectionAt([[1].asSet() => [1]], null))
    traceln(sheaf.sectionAt([
        [1, 2].asSet() => [1, 2],
        [2].asSet() => [2],
    ], null))
    traceln(sheaf.sectionAt([[2, 3, 5].asSet() => [1, 2, 3]], null))
    escape badSection:
        traceln(sheaf.sectionAt([
            [1, 2].asSet() => [1, 2],
            [2].asSet() => [3],
        ], badSection))
    catch problem:
        traceln(`Sheaf section failure: $problem`)

    return 0
