import "fun/natset" =~ [=> Nat, => makeNatSet]
exports (makeSimplicialComplex)

# http://people.maths.ox.ac.uk/nanda/cat/TDANotes.pdf

# A simplicial map is a relabeling of vertices s.t. a simplicial complex is
# still a simplicial complex after being relabeled. A bit of thought will show
# that this means that we must be able to pack the relabeling into not just a
# Map, but a List.
def SimplicialMap :DeepFrozen := List[Nat]

object makeSimplicialComplex as DeepFrozen:
    "
    Create simplicial complices indexed by natural numbers.

    This maker produces basic computable combinatorial spaces. Each space is
    represented by a simplicial complex, a union of possibly-overlapping
    simplices. Storage is proportional to the number of simplices.
    "

    to fromSolid(n :Nat):
        "The solid `n`-dimensional simplicial complex."

        return makeSimplicialComplex.fromSimplices([for i in (1..!(2 ** n)) {
            makeNatSet(i)
        }].asSet())

    to fromHollow(n :Nat):
        "
        The hollow `n`-dimensional simplicial complex.

        Like the solid `n`-dimensional simplicial complex, but without the
        highest-dimensional simplex, creating an `n`-dimensional hole.
        "

        return makeSimplicialComplex.fromSimplices([for i in (1..!(2 ** n) - 1) {
            makeNatSet(i)
        }].asSet())

    to fromSimplices(simplices :Set):
        return object simplicialComplex:
            "A discrete combinatorial space."

            to _printOn(out):
                if (simplices.isEmpty()):
                    out.print("<empty simplicial complex>")
                else if (simplices.size() <= 5):
                    out.print("<simplicial complex ")
                    out.quote(simplices.asList().sort())
                    out.print(">")
                else:
                    out.print("<simplicial complex, dimension ")
                    out.quote(simplicialComplex.dimension())
                    out.print(", ")
                    out.quote(simplices.size())
                    out.print(" simplices>")

            to dimension() :Nat:
                "The maximum dimension of all simplices in this complex."

                var rv := 0
                for s in (simplices):
                    rv max= (s.size())
                return rv

            to applyMap(m :SimplicialMap):
                "Apply simplicial map `m` to this complex."

                return makeSimplicialComplex.fromSimplices([for s in (simplices) {
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

                return makeSimplicialComplex.fromSimplices([for s in (simplices) ? ({
                    simplices.contains(s | simplex) && (s & simplex).isEmpty()
                }) s].asSet())

            to cone():
                "The cone of this complex."

                def v := simplicialComplex.dimension() + 1
                def vs := makeNatSet.singleton(v)
                def ss := [for s in (simplices) s.with(v)].asSet()
                return makeSimplicialComplex.fromSimplices(simplices | ss.with(vs))

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
                return makeSimplicialComplex.fromSimplices(rv.snapshot())

            to fiberAt(f :SimplicialMap, t):
                "The fiber of `f` over `t` in this complex."

                return makeSimplicialComplex.fromSimplices([for s in (simplices) ? ({
                    makeNatSet.fromIterable([for x in (s) f[x]]) <= t
                }) s].asSet())
