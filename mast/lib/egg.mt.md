```
import "lib/disjoint" =~ [=> makeDisjointForest]
import "lib/schwartzian" =~ [=> makeSchwartzian]
exports (makeEGraph)
```

# E-Graphs

An [e-graph](https://egraphs-good.github.io/) is a hybrid data structure
consisting of two components:

* A union-find structure, like from lib/disjoint
* A graph whose edges and vertices are grouped by that union-find

The overall effect is to create graphs whose vertices are equivalence classes,
or e-classes, over some family of trees. In this particular presentation,
we'll allow cycles, so that we're storing many different equivalent graphs
inside a single graph structure.

## E-Matching

The bulk of our time will be spent trying to match user-supplied patterns
against the e-graph. We'll follow the [de Moura-Bjørner abstract
machine](http://leodemoura.github.io/files/ematching.pdf), with a few
simplifications.

For a variety of sanity reasons, it will be easiest for us to tag all leaf
nodes with a sentinel value.

```
object leaf as DeepFrozen {}
```

We will want to compile our leaf comparisons before our branch comparisons, to
reduce the amount of backtracking required. To do this, we'll need to be able
to sort our maps so that lists come after literals.

```
def isList(x) as DeepFrozen:
    return escape ej { List.coerce(x, ej); true } catch _ { false }

def subpatternsLast(x, y) as DeepFrozen:
    def xIsList := isList(x)
    def yIsList := isList(y)
    return if (xIsList &! yIsList) {
        1
    } else if (yIsList &! xIsList) {
        -1
    } else { x.op__cmp(y) }
```

The actual compiler follows the original design.

```
# p6
def compile(W :Map, V :Map, o :Int) as DeepFrozen:
    return if (W.isEmpty()) {
        ["yield"] + [for i in (V) i]
    } else {
        # Put subpatterns at the end.
        def i := makeSchwartzian(subpatternsLast).sortValues().getKeys()[0]
        switch (W[i]) {
            match [==leaf, t] { ["check", i, t, compile(W.without(i), V, o)] }
            match [f] + p {
                def Wp := W.without(i) | [for n => pn in (p) o + n => pn]
                ["bind", i, f, o, compile(Wp, V, o + p.size())]
            }
            match via (V.fetch) vxk {
                ["compare", i, vxk, compile(W.without(i), V, o)]
            }
            match xk { compile(W.without(i), V.with(xk, i), o) }
        }
    }

def compilePattern(pattern) as DeepFrozen:
    def [f] + ps := pattern
    return [f, compile([for i => p in (ps) i => p], [].asMap(), ps.size())]
```

To run the abstract machine, we'll embed a state machine into an iterator.

```
def makeMatcher(egraph, t, program) as DeepFrozen:
    return def matcher._makeIterator():
        # p4
        var pc := program
        def reg := t.diverge()
        def bstack := [].diverge()
        var i := 0
        return def matcherIterator.next(ej):
            while (true):
                switch (pc):
                    match [=="bind", i, f, o, next]:
                        def appsf := egraph.terms(reg[i], f)
                        bstack.push(["choose-app", o, next, appsf, 0])
                        pc := "backtrack"
                    match [=="check", i, t, next]:
                        pc := if (egraph.find(reg[i]) == egraph.find(t)) {
                            next
                        } else { "backtrack" }
                    match [=="compare", i, j, next]:
                        pc := if (egraph.find(reg[i]) == egraph.find(reg[j])) {
                            next
                        } else { "backtrack" }
                    match [=="yield"] + xs:
                        def rv := [i, [for x in (xs) reg[x]]]
                        pc := "backtrack"
                        return rv
                    match =="backtrack":
                        if (bstack.isEmpty()):
                            throw.eject(ej, "End of iteration")
                        pc := bstack.pop()
                    match [=="choose-app", o, next, s, j]:
                        # XXX known at compile time?
                        if (s.size() > j):
                            for i => t in (s[j]):
                                reg[o + i] := t
                            bstack.push(["choose-app", o, next, s, j + 1])
                            pc := next
                        else:
                            pc := "backtrack"
```

## Core

Our implementation and nomenclature will closely follow
[egg](https://arxiv.org/abs/2004.03082), a high-performance e-graph design.

```
def makeEGraph() as DeepFrozen:
    # p3
    def U := makeDisjointForest()
    def eM := [].asMap().diverge()
    def H := [].asMap().diverge()

    def canonicalize(n):
        def [f] + args := n
        return [f] + [for a in (args) U.find(a)]

    # p4
    def lookup(n, ej):
        return H.fetch(canonicalize(n), ej)

    return object egraph:
        # p5
        to add(n):
           return escape ej { lookup(n, ej) } catch _ {
                def a := U.freshClass()
                eM[a] := [n].asSet()
                a
           }

        to merge(a, b):
            U.union(a, b)
            eM[a] := eM[b] := eM[a] | eM[b]

        to find(a):
            return U.find(a)

        to terms(a, f):
            def rv := [].diverge()
            for c in (eM[U.find(a)]):
                def [==f] + args exit __continue := c
                rv.push(c)
            return rv.snapshot()

        to ematch(p):
            def [f, program] := compilePattern(p)
            def rv := [].diverge()
            for c => nodes in (eM):
                for node in (nodes):
                    def [==f] + args exit __continue := node
                    for m in (makeMatcher(egraph, args, program)):
                        rv.push(m)
            return rv.snapshot()
```
