import "lib/iterators" =~ [=> zip]
import "lib/schwartzian" =~ [=> makeSchwartzian]
import "lib/welford" =~ [=> makeWelford]
exports (makeNelderMead)

def makeNelderMead(f, d :(Int >= 2)) as DeepFrozen:
    "Iteratively minimize `d`-dimensional black-box function `f`."

    def call(l):
        def rv := M.call(f, "run", l, [].asMap())
        traceln("call", l, "->", rv)
        return rv

    def sorter := makeSchwartzian.fromKeyFunction(call)
    def zero := [0.0] * d

    def done(xs):
        def stats := makeWelford()
        for x in (xs):
            stats(call(x))
        return stats.standardDeviation() < 1e-7

    return def nelderMead._makeIterator():
        var xs := [zero] + [for i in (0..!d) zero.with(i, 1.0)]
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
            # Centroid
            def centroid := [for column in (M.call(zip, "run", xs, [].asMap())) {
                var mean := 0.0
                for c in (column) { mean += c }
                mean / column.size()
            }]
            # Reflection
            def best := xs[0]
            def worst := xs.last()
            def reflected := [for i => c in (centroid) c * 2.0 - worst[i]]
            def cr := call(reflected)
            if (cr < call(xs[xs.size() - 2])):
                if (cr >= call(xs[0])):
                    return finish(reflected)
                # Expansion
                def expanded := [for i => r in (reflected) r * 2.0 - centroid[i]]
                return finish((call(expanded) < cr).pick(expanded, reflected))
            # Contraction
            def contracted := [for i => c in (centroid) (c + worst[i]) * 0.5]
            if (call(contracted) < call(worst)):
                return finish(contracted)
            # Shrink
            xs := [for x in (xs) [for i => c in (best) (c + x[i]) * 0.5]]
            def rv := [j, best]
            j += 1
            return rv
