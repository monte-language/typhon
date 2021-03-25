import "fun/natset" =~ [=> makeNatSet]
exports (makeSimplicialComplex)

# http://people.maths.ox.ac.uk/nanda/cat/TDANotes.pdf

object makeSimplicialComplex as DeepFrozen:
    to fromSolid(face):
        def faces := [].asSet().diverge()
        def queue := [face].diverge()
        while (!queue.isEmpty()):
            def face := queue.pop()
            faces.include(face)
            for vertex in (face):
                def f := face.without(vertex)
                if (!faces.contains(f)):
                    queue.push(f)
        return makeSimplicialComplex.fromSimplices(faces.snapshot())

    to fromSimplices(simplices :Set):
        return object simplicialComplex:
            to dimension():
                var rv := -1
                for s in (simplices):
                    rv max= (s.size())
                return rv

            to facesOf(simplex):
                return [for s in (simplices) ? (s <= simplex) s].asSet()

            to star(simplex) :Set:
                return [for s in (simplices) ? (s >= simplex) s].asSet()

            to link(simplex):
                return makeSimplicialComplex.fromSimplices([for s in (simplices) ? ({
                    simplices.contains(s | simplex) && (s & simplex).isEmpty()
                }) s].asSet())

            to cone():
                def v := simplicialComplex.dimension() + 1
                def vs := makeNatSet.singleton(v)
                def ss := [for s in (simplices) s.with(v)].asSet()
                return makeSimplicialComplex.fromSimplices(simplices | ss.with(vs))

            to closure(subcomplex :Set):
                def rv := subcomplex.diverge()
                def queue := subcomplex.asList().diverge()
                while (!queue.isEmpty()):
                    def simplex := queue.pop()
                    for face in (simplicialComplex.facesOf(simplex)):
                        if (!rv.contains(face)):
                            rv.include(face)
                            queue.push(face)
                return makeSimplicialComplex.fromSimplices(rv.snapshot())
