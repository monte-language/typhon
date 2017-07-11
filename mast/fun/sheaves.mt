import "lib/uKanren" =~ [=> anyValue :DeepFrozen, => kanren :DeepFrozen]
exports (main)

interface Section :DeepFrozen:
    to isGlobal() :Bool:
        "Whether this section is defined everywhere."

    to extendTo(assignments :Map) :Section:
        "
        Extend this section to also have the given values at the given
        vertices.
        "

    to extending(assignments :Map, ej) :Section:
        "Attempt an extension."

    to get(assignment):
        "Look up `assignment` in this section."

interface Sheaf :DeepFrozen:
    to stalkAt(u :Set) :Set:
        "The stalk of this sheaf in the neighborhood of `u`."

    to emptySection() :Section:
        "The unique section which has no assignments."

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

def makeSection(vertices :Map, consistency :Map, assignments :Map) as DeepFrozen:
    return object section as Section:
        to isGlobal() :Bool:
            return assignments.size() == vertices.size()

        to extendTo(extension :Map) :Section:
            return section.extending(extension, null)

        to extending(extension :Map, ej) :Section:
            # Set up the full map of vertices to check.
            def fullSection := assignments | extension
            def index := [for i => v in (vertices.getKeys()) v => i]

            # XXX
            anyValue

            # Define the top-level program. It contains each piece of the
            # consistency structure as a subgoal, and also performs the
            # initial assignments.
            object topLevel:
                match [=="run", vars, _]:
                    kanren.allOf([for v => value in (fullSection) {
                        kanren.unify(vars[index[v]], value)
                    }] + [for vs => goalMaker in (consistency) {
                        def swizzle := [for v in (vs) vars[index[v]]]
                        M.call(goalMaker, "run", swizzle, [].asMap())
                    }])
            def program := kanren.fresh(topLevel, vertices.size())
            if (kanren.satisfiable(program)):
                return makeSection(vertices, consistency, extension)
            else:
                throw.eject(ej, `.extending/2: Couldn't extend with $extension`)

        to get(vertex):
            return assignments[vertex]

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

        to sheaf(consistency :Map):
            "
            Build a sheaf according to a `consistency` structure.

            Keys are sets of vertices and values are kanren goals.
            "

            return object abstractSheaf as Sheaf:
                to vertices():
                    return abstractSimplicialComplex.vertices()

                to stalkAt(u :Set):
                    return [for x in (u) vertices[x]]

                to emptySection() :Section:
                    return makeSection(vertices, consistency, [].asMap())

def possibilities(guard) as DeepFrozen:
    return switch (guard):
        match ==Bool:
            [true, false]

def largestSectionAt(sheaf, assignment, ej) as DeepFrozen:
    var largest := sheaf.sectionAt(assignment, ej)
    var sections := [assignment => largest]
    def vs := sheaf.vertices()
    # For each vertex not yet assigned, we will try out the possible
    # assignments and see what kinds of sections we get.
    for vertex => guard in (vs):
        # Skip already-assigned vertices.
        if (assignment.contains(vertex)):
            continue
        def rv := [].asMap().diverge()
        for p in (possibilities(guard)):
            for ass => _ in (sections):
                def new := ass.with(vertex, p)
                def contender := rv[new] := sheaf.sectionAt(new, __continue)
                if (contender.size() > largest.size()):
                    largest := contender
        sections := rv.snapshot()
    return largest

def main(_) as DeepFrozen:
    def and := kanren.table([
        [false, false, false],
        [true, false, false],
        [false, true, false],
        [true, true, true],
    ])
    def xor := kanren.table([
        [false, false, false],
        [true, false, true],
        [false, true, true],
        [true, true, false],
    ])
    def or := kanren.table([
        [false, false, false],
        [true, false, true],
        [false, true, true],
        [true, true, true],
    ])
    def halfAdder(a, b, s, c):
        return kanren.allOf([xor(a, b, s), and(a, b, c)])
    def fullAdder(a, b, cin, cout, s):
        return kanren.fresh(fn firstSum, firstCarry, secondCarry {
            kanren.allOf([
                halfAdder(a, b, firstSum, firstCarry),
                halfAdder(firstSum, cin, s, secondCarry),
                or(firstCarry, secondCarry, cout),
            ])
        }, 3)
    def fullAdderASC := makeASC([for x in (["A", "B", "Cin", "Cout", "S"])
                                 x => Bool],
                                [].asSet())
    def fullAdderSheaf := fullAdderASC.sheaf([
        ["A", "B", "Cin", "Cout", "S"].asSet() => fullAdder,
    ])
    def addsToThree := ["Cout" => true, "S" => true]
    def section := fullAdderSheaf.emptySection()
    traceln("What section adds to three:", section.extendTo(addsToThree))
    return 0
