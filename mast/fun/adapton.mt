exports (adapton)

# http://adapton.org/

# Adapton is an algorithm for incremental computation. Well, a framework for
# incremental computation. Well, a mini-language for incremental computation.
# Look, the point is that it's a good "spreadsheet algorithm"; Adapton
# understands when only part of a system has changed, and incrementally
# updates the system in a way that attempts to minimize extra work.

def addEdge(sup, sub) as DeepFrozen:
    sub.addSuperEdge(sup)
    sup.addSubEdge(sub)

def delEdge(sup, sub) as DeepFrozen:
    sub.delSuperEdge(sup)
    sup.delSubEdge(sub)

# XXX split thunk implementation into thunks and refs?

def makeThunk(thunk, var result, var clean :Bool) as DeepFrozen:
    def sub := [].asSet().diverge()
    def sup := [].asSet().diverge()
    return object adaptonThunk:
        to addSuperEdge(a):
            sup.include(a)

        to delSuperEdge(a):
            if (sup.contains(a)):
                sup.remove(a)

        to addSubEdge(a):
            sub.include(a)

        to delSubEdge(a):
            if (sub.contains(a)):
                sub.remove(a)

        to result():
            return result

        to compute():
            return if (clean) { result } else {
                for a in (sub) { 
                    delEdge(adaptonThunk, a)
                }
                clean := true
                result := thunk()
                adaptonThunk.compute()
            }

        to dirty():
            if (clean):
                clean := false
                for a in (sup):
                    a.dirty()

        to set(v):
            result := v
            adaptonThunk.dirty()

def makeForcer() as DeepFrozen:
    var currentlyAdapting := null
    return def force(a):
        def prevAdapting := currentlyAdapting
        currentlyAdapting := a
        def result := a.compute()
        currentlyAdapting := prevAdapting
        if (currentlyAdapting != null):
            addEdge(currentlyAdapting, a)
        return result

object adapton as DeepFrozen:
    to newRef(val):
        def t := makeThunk(t.result, val, true)
        return object refSlot:
            to get():
                return t.compute()
            to put(v):
                t.set(v)
            to getGuard():
                return Any
            to ref():
                return t

    to newThunk(f):
        return makeThunk(f, null, false)

    to addEdge(sup, sub):
        addEdge(sup, sub)

    to delEdge(sup, sub):
        delEdge(sup, sub)

    to force(a):
        return makeForcer()(a)
