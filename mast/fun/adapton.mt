import "fun/stores" =~ [=> Location, => Store]
exports (makeSheet)

# http://adapton.org/

# Adapton is an algorithm for incremental computation. Well, a framework for
# incremental computation. Well, a mini-language for incremental computation.
# Look, the point is that it's a good "spreadsheet algorithm"; Adapton
# understands when only part of a system has changed, and incrementally
# updates the system in a way that attempts to minimize extra work.

def keyFetch(m, k :Str) as DeepFrozen:
    return m.fetch(k, fn { m[k] := [].asSet().diverge() })

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
        traceln(`edge + $sup $sub`)
        keyFetch(subs, sub).include(sup)
        keyFetch(sups, sup).include(sub)

    def delEdge(sup, sub):
        traceln(`edge - $sup $sub`)
        keyFetch(subs, sub).remove(sup)
        keyFetch(sups, sup).remove(sub)

    def trackingCellsRun(thunk):
        def seen := [].asSet().diverge()
        def cells.get(k):
            seen.include(k)
            return results[k]
        def rv := thunk(cells)
        traceln(`run $thunk -> $rv (seen ${seen.asList()})`)
        return [rv, seen.snapshot()]

    return def sheet(k :Str) as Store:
        "
        An incrementally-computed network of values.
        "

        return object cell as Location:
            to get():
                return results.fetch(k, fn {
                    # Drop all sub-edges.
                    for a in (keyFetch(subs, k)) { delEdge(k, a) }
                    def [res, seen] := trackingCellsRun(thunks[k])
                    # Add new sub-edges for everything just used.
                    for a in (seen) { addEdge(k, a) }
                    # XXX check fixed point?
                    results[k] := res
                })
            to put(value :DeepFrozen):
                thunks[k] := def just(_cells) as DeepFrozen { return value }
                dirty(k)
