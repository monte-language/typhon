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

def countEdge(b :Set, a :Set ? (a.size() + 1 == b.size())) :Int as DeepFrozen:
    # 0 if a is not a face of b, +1 if a is a correctly-oriented face of b, -1
    # if a is a backwards face of b
    return if (a < b) {
        for vertex in (b) {
            def sub := b.without(vertex)
            if (sub <=> a) {
                # They might already be in the right order, which is not just
                # lucky, but expected for nearly all edges.
                break if (sub == a) { 1 } else {
                    # Crappy case. Dump them both to lists and walk until we
                    # either loop or find a swapped vertex.
                    def l := sub.asList()
                    def r := a.asList()
                    def offset :(Int >= 0) := r.indexOf(l[0])
                    def size := r.size()
                    escape swapped {
                        for i => v in (l) {
                            if (r[(i + offset) % size] != v) { swapped() }
                        }
                        # Full loop, no swaps.
                        1
                    } catch _ { -1 }
                }
            }
        }
    } else { 0 }

def makeASC(vertices :Map, facets :Set) as DeepFrozen:
    def space :Set := {
        var rv := facets.asSet()
        def stack := facets.asList().diverge()
        while (!stack.isEmpty()) {
            def s := stack.pop()
            for ex in (s) {
                def subset := s.without(ex)
                if (!rv.contains(subset)) {
                    # XXX We don't have a good poset representation, so
                    # instead we are forced to iterate to confirm that,
                    # indeed, we haven't occurred in this poset so far.
                    def ej := __continue
                    for specimen in (rv) {
                        if (specimen <=> subset) { ej() }
                    }
                    rv with= (subset)
                    stack.push(subset)
                }
            }
        }
        rv
    }
    # traceln(`space $space`)
    def restrictions :Map[Pair[Set, Set], Any] := {
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
    # traceln(`restrictions $restrictions`)
    return object abstractSimplicialComplex:
        to vertices():
            return vertices

        to eulerCharacteristic() :Int:
            var rv :Int := 0
            for s in (space):
                rv += -1 ** (s.size() - 1)
            return rv

        to star(simplex :Set) :Set:
            return [for s in (space) ? (simplex <= s) s].asSet()

        to flabbySheaf():
            return abstractSimplicialComplex.sheaf([].asMap())

        to sheaf(consistency :Map[Set, Any]):
            return object abstractSheaf as Sheaf:
                to stalkAt(u :Set):
                    return [for x in (u) vertices[x]]

                to sectionAt(assignment :Map, ej) :Map:
                    def fullSection := [].asMap().diverge()
                    # For all sets in the space, if they are fully specified
                    # by the given section, then check their consistency and
                    # then include them.
                    for s in (space):
                        def section := [for x in (s)
                                        assignment.fetch(x, __continue)]
                        if (consistency.contains(s)):
                            def con := consistency[s]
                            if (!M.call(con, "run", section, [].asMap())):
                                continue
                        fullSection[s] := section
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
    traceln(`Euler: ${asc.eulerCharacteristic()}`)
    traceln(asc.star([3].asSet()))
    traceln(asc.star([2].asSet()))

    def sheaf := asc.flabbySheaf()
    traceln(sheaf)
    traceln(sheaf.stalkAt([2, 3, 5].asSet()))
    traceln(sheaf.sectionAt([1 => 1], null))
    traceln(sheaf.sectionAt([
        1 => 1,
        2 => 2,
    ], null))

    def simpleXorASC := makeASC([for x in (['x', 'y', 'z', 'w']) x => Bool], [
        # x ^ y == z
        ['x', 'y', 'z'].asSet(),
        # x ^ z == w
        ['x', 'z', 'w'].asSet(),
    ].asSet())
    def xorCheck(in0 :Bool, in1 :Bool, out :Bool) :Bool:
        # Check the truth table, yo.
        return in0 ^ in1 ^ !out
    def simpleXorSheaf := simpleXorASC.sheaf([
        ['x', 'y', 'z'].asSet() => xorCheck,
        ['x', 'z', 'w'].asSet() => xorCheck,
    ])
    def incorrect := [
        'x' => false,
        'y' => false,
        'z' => true,
    ]
    traceln("Incorrect section", simpleXorSheaf.sectionAt(incorrect, null))
    def correct := [
        'x' => true,
        'y' => false,
        'z' => true,
    ]
    traceln("Correct section", simpleXorSheaf.sectionAt(correct, null))

    return 0
