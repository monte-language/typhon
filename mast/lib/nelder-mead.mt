import "lib/iterators" =~ [=> zip]
import "lib/schwartzian" =~ [=> makeSchwartzian]
import "lib/welford" =~ [=> makeWelford]
exports (makeNelderMead)

def combineVectors(l :List, r :List) :List as DeepFrozen:
    return [for [x, y] in (zip(l, r)) (x + y) * 0.5]

def reflectVector(l :List, o :List) :List as DeepFrozen:
    return [for [x, y] in (zip(l, o)) (x * 2.0) - y]

def makeNelderMead(f, d :(Int >= 2), => origin :List[Double] := [0.0] * d,
                   => epsilon :Double := 1e-15) as DeepFrozen:
    "
    Iteratively minimize `d`-dimensional black-box function `f` until the
    error is less than `epsilon`.

    The `origin` is an overridable starting estimate.
    "

    def call(l):
        return M.call(f, "run", l, [].asMap())

    def sorter := makeSchwartzian.fromKeyFunction(call)

    def done(xs):
        def stats := makeWelford()
        for x in (xs):
            stats(call(x))
        return stats.standardDeviation() < 1e-7

    return def nelderMead._makeIterator():
        var xs := [origin] + [for i => o in (origin) origin.with(i, o + 1.0)]
        var j := 0
        def finish(l):
            xs with= (xs.size() - 1, l)
            def rv := [j, l]
            j += 1
            return rv

        return def iterator.next(ej):
            # Termination
            if (done(xs)):
                throw.eject(ej, "end of iteration")
            # Order
            xs := sorter.sort(xs)
            def best := xs[0]
            def cb := call(best)
            if (cb < epsilon):
                throw.eject(ej, "end of iteration")
            # Centroid
            def centroid := [for column in (M.call(zip, "run", xs, [].asMap())) {
                var mean := 0.0
                for c in (column) { mean += c }
                mean / column.size()
            }]
            # Reflection
            def worst := xs.last()
            def reflected := reflectVector(centroid, worst)
            def cr := call(reflected)
            if (cr < call(xs[xs.size() - 2])):
                return if (cr >= cb) { finish(reflected) } else {
                    # Expansion
                    def expanded := reflectVector(reflected, centroid)
                    finish((call(expanded) < cr).pick(expanded, reflected))
                }
            # Contraction
            def contracted := combineVectors(centroid, worst)
            if (call(contracted) < call(worst)):
                return finish(contracted)
            # Shrink
            xs := [for x in (xs) combineVectors(best, x)]
            def rv := [j, best]
            j += 1
            return rv
