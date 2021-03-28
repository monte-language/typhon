import "fun/natset" =~ [=> Nat, => makeNatSet]
exports (makeSimplicialComplex, collapsingFiltration)

# http://people.maths.ox.ac.uk/nanda/cat/TDANotes.pdf

# A simplicial map is a relabeling of vertices s.t. a simplicial complex is
# still a simplicial complex after being relabeled. A bit of thought will show
# that this means that we must be able to pack the relabeling into not just a
# Map, but a List.
def SimplicialMap :DeepFrozen := List[Nat]

# Our unordered sets of natural numbers have a natural orientation under the
# typical ordering. This gives us a natural iteration over the faces under a
# given simplex.
def orientedFaces(simplex) as DeepFrozen:
    return def faceIterable._makeIterator():
        var iter := simplex._makeIterator()
        return def faceIterator.next(ej):
            def [k, v] := iter.next(ej)
            return [k, simplex.without(v)]

object makeSimplicialComplex as DeepFrozen:
    "
    Create simplicial complices indexed by natural numbers.

    This maker produces basic computable combinatorial spaces. Each space is
    represented by a simplicial complex, a union of possibly-overlapping
    simplices. Storage is proportional to the number of simplices.
    "

    to fromSolid(n :Nat):
        "The solid `n`-dimensional simplicial complex."

        return makeSimplicialComplex([for i in (1..!(2 ** (n + 1))) {
            makeNatSet(i)
        }].asSet())

    to fromHollow(n :Nat):
        "
        The hollow `n`-dimensional simplicial complex.

        Like the solid `n`-dimensional simplicial complex, but without the
        highest-dimensional simplex, creating an `n`-dimensional hole. Note
        that there is no hollow 0-dimensional simplicial complex, because we
        do not represent (the single unique) (-1)-dimensional simplex.
        "

        return makeSimplicialComplex([for i in (1..!(2 ** (n + 1)) - 1) {
            makeNatSet(i)
        }].asSet())

    to run(simplices :Set ? (!simplices.isEmpty() && !simplices.contains(makeNatSet(0)))):
        "
        Assemble a simplicial complex from `simplices`. At least one simplex
        must be provided, and no simplex may be empty.

        Closure is not enforced, so the resulting complex may be invalid. To
        ensure that this is not the case, use
        `makeSimplicialComplex.fromSolid/1` to prepare a complex which is
        large enough to hold the closure as a subcomplex, and then call
        `.closure/1`.
        "

        return object simplicialComplex:
            "A discrete combinatorial space."

            to _printOn(out):
                if (simplices.isEmpty()):
                    out.print("<empty simplicial complex>")
                else if (simplices.size() <= 5 * 2):
                    out.print("<simplicial complex ")
                    out.quote(simplices.asList().sort().reverse())
                    out.print(">")
                else:
                    out.print("<simplicial complex, dimension ")
                    out.quote(simplicialComplex.dimension())
                    out.print(", ")
                    out.quote(simplices.size())
                    out.print(" simplices>")

            to _makeIterator():
                return simplices._makeIterator()

            to dimension() :Nat:
                "The maximum dimension of all simplices in this complex."

                var rv := 1
                for s in (simplices):
                    rv max= (s.size())
                return rv - 1

            to applyMap(m :SimplicialMap):
                "Apply simplicial map `m` to this complex."

                return makeSimplicialComplex([for s in (simplices) {
                    makeNatSet.fromIterable([for x in (s) m[x]])
                }].asSet())

            to facesOf(simplex) :Set:
                "The faces of `simplex` in this complex."

                return [for s in (simplices) ? (s <= simplex) s].asSet()

            to star(simplex) :Set:
                "
                The open star of `simplex` in this complex.

                Combine with `.closure/1` for the closed star.
                "

                return [for s in (simplices) ? (s >= simplex) s].asSet()

            to link(simplex):
                "The link of `simplex` in this complex."

                return makeSimplicialComplex([for s in (simplices) ? ({
                    simplices.contains(s | simplex) && (s & simplex).isEmpty()
                }) s].asSet())

            to cone():
                "The cone of this complex."

                # For a fresh vertex, we'll take the union of everything in
                # the complex, and then find the first vertex not in that
                # union.
                var union := makeNatSet(0)
                for s in (simplices):
                    union |= s
                for v in (0..union.asBits().bitLength()):
                    if (union.contains(v)):
                        continue
                    # v is not currently used, so we'll use it for a vertex.
                    def vs := makeNatSet.singleton(v)
                    def ss := [for s in (simplices) s.with(v)].asSet()
                    return makeSimplicialComplex(simplices | ss.with(vs))
                throw(".cone/0: Unreachable code")

            to closure(subcomplex :Set):
                "
                The closure of a `subcomplex` within this complex.

                The `subcomplex` is only given as a `Set`, but the closure
                will be a proper complex.
                "

                def rv := subcomplex.diverge()
                def queue := subcomplex.asList().diverge()
                while (!queue.isEmpty()):
                    def simplex := queue.pop()
                    for face in (simplicialComplex.facesOf(simplex)):
                        if (!rv.contains(face)):
                            rv.include(face)
                            queue.push(face)
                return makeSimplicialComplex(rv.snapshot())

            to fiberAt(f :SimplicialMap, t):
                "The fiber of `f` over `t` in this complex."

                return makeSimplicialComplex([for s in (simplices) ? ({
                    makeNatSet.fromIterable([for x in (s) f[x]]) <= t
                }) s].asSet())

            to freeFaces() :Set:
                "
                The faces in this complex whose open stars contain exactly
                themselves and one other simplex.
                "

                return [for s in (simplices) ? ({
                    simplicialComplex.star(s).size() == 2
                }) s].asSet()

            to elementaryCollapse(face):
                "
                The subcomplex which is missing `face`.

                The face must already be in this complex and be the smaller of
                a free face pair.
                "

                def [s] := simplicialComplex.star(face).without(face).asList()
                return makeSimplicialComplex(simplices.without(face).without(s))

            to eulerCharacteristic() :Int:
                "The Euler characteristic of this simplicial complex."

                var rv :Int := 0
                for s in (simplices):
                    # NB: This isn't backwards; dimension has opposite parity
                    # from size, so when size is even, dimension is odd, etc.
                    rv += (s.size() & 1).isZero().pick(-1, 1)
                return rv


def collapsingFiltration(complex) as DeepFrozen:
    "
    Iteratively collapse `complex` to successively smaller subcomplices.

    Each iteration yields a single elementary collapse, or end of iteration if
    no free face pairs remain.
    "

    return def collapseIterable._makeIterator():
        var i := 0
        var subcomplex := complex
        return def collapseIterator.next(ej):
            # Find a free face pair.
            def [face] + _ exit ej := subcomplex.freeFaces().asList()
            subcomplex elementaryCollapse= (face)
            def rv := [i, subcomplex]
            i += 1
            return rv
