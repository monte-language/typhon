import "fun/stores" =~ [=> Location, => Store]
exports (constantly, makeSheet)

# http://adapton.org/

# Adapton is an algorithm for incremental computation. Well, a framework for
# incremental computation. Well, a mini-language for incremental computation.
# Look, the point is that it's a good "spreadsheet algorithm"; Adapton
# understands when only part of a system has changed, and incrementally
# updates the system in a way that attempts to minimize extra work.

def keyFetch(m, k :Str) as DeepFrozen:
    return m.fetch(k, fn { m[k] := [].asSet().diverge() })

def constantly(x :DeepFrozen) as DeepFrozen:
    "
    The constant function which always returns `x`.

    This is a good way to put constant values into a sheet.
    "

    return def const(_cells) as DeepFrozen { return x }

def makeSheet() as DeepFrozen:
    "
    Generate a fresh sheet.

    Each sheet has its own namespace and private storage.
    "

    # Indeed, by the folklore of containment, each sheet ought to be isolated
    # from each other! We don't take special effort to ensure this, though.

    def thunks := [].asMap().diverge(Str, DeepFrozen)
    # Hygiene to avoid storing cleanliness bits: When a value is invalidated,
    # we remove it from storage entirely.
    def results := [].asMap().diverge(Str, DeepFrozen)
    # Super-links: Each link goes up.
    def sups := [].asMap().diverge()
    # Sub-links: Each link goes down.
    def subs := [].asMap().diverge()

    def dirty(k):
        if (results.contains(k)):
            results.removeKey(k)
            for a in (keyFetch(sups, k)) { dirty(a) }

    def addEdge(sup, sub):
        keyFetch(subs, sup).include(sub)
        keyFetch(sups, sub).include(sup)

    def delEdge(sup, sub):
        if ((def s := keyFetch(subs, sup)).contains(sub)):
            s.remove(sub)
        if ((def s := keyFetch(sups, sub)).contains(sup)):
            s.remove(sup)

    def trackingCellsRun(thunk):
        return escape ej:
            var seen := [].asSet().diverge()
            object cells:
                to get(k):
                    seen.include(k)
                    return results.fetch(k, fn { ej(k) })
                to fetch(k, f):
                    seen.include(k)
                    return results.fetch(k, f)
            def rv := thunk(cells)
            [rv, seen.snapshot()]
        catch missingKey:
            missingKey

    object bottom {}

    return def sheet(k :Str) as Store:
        "
        An incrementally-computed network of values.
        "

        return object cell as Location:
            to get():
                def go():
                    # Drop all sub-edges.
                    for a in (keyFetch(subs, k)) { delEdge(k, a) }
                    return when (def run := trackingCellsRun<-(thunks[k])) ->
                        if (run =~ [res, seen]) {
                            # Add new sub-edges for everything just used.
                            for a in (seen) { addEdge(k, a) }
                            # Check for whether we are recursive and, if so, whether
                            # we have reached a fixpoint yet.
                            if (seen.contains(k) &&
                                res != results.fetch(k, &bottom.get)) {
                                results[k] := res
                                go()
                            } else { results[k] := res }
                        } else {
                            # Missing key. Go re-run this subcomputation, since
                            # its result is gone. Then, try again.
                            when (sheet(run)<-get()) -> { go() }
                        }
                return results.fetch(k, go)
            to put(value :DeepFrozen):
                thunks[k] := value
                dirty(k)
