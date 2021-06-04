```
import "lib/disjoint" =~ [=> makeDisjointForest]
import "lib/schwartzian" =~ [=> makeSchwartzian]
exports (leaf, makeEGraph)
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

What's the point? Imagine that we have a tree for a program in some language.
We also have some rewrite rules for the language. We want to reduce the tree
by repeatedly applying rewrite rules, but we don't want to care about the
order in which we apply rules. An e-graph solves this problem by collecting
rewritten tree branches in a holistic and efficient manner. The downside, as
one might expect, is that we are no longer working with entire trees, but
fragments of branches; an e-graph is something like a wood chipper.

An e-class contains branches. A branch is identified by a verb and arity, like
Monte methods. The arity indicates how many subordinate e-classes are
referenced by the branch. For lib/asdl trees, each constructor gives a verb
and arity, and each subordinate branch is associated with its own e-class.

For a variety of sanity reasons, it will be easiest for us to tag all leaf
nodes with a sentinel value. It will also be easy if this value always
compares less than non-leaf values. This will make it simple to tell whether
an e-class contains concrete data or just pointers to other e-classes.

```
def leaf.op__cmp(other) as DeepFrozen:
    return (leaf == other).pick(0, -1)
```

Concrete data will have `leaf` as its verb and unary arity.

## E-Matching

The bulk of our time will be spent trying to match user-supplied patterns
against the e-graph, a process known as "e-matching". We'll follow the [de
Moura-Bjørner abstract
machine](http://leodemoura.github.io/files/ematching.pdf), with a few
simplifications.

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

The actual compiler follows the original de Moura-Bjørner design. In the
future, we could compile many e-match patterns into a single program, as long
as they all start with the same verb and arity. More on that later.

```
# p6
def compile(W :Map, V :Map, o :Int) as DeepFrozen:
    return if (W.isEmpty()) {
        ["yield"] + [for i in (V.sortKeys()) i]
    } else {
        # Put subpatterns at the end.
        def schwartzian := makeSchwartzian.fromComparison(subpatternsLast)
        def i := schwartzian.sortValues(W).getKeys()[0]
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
    return [f, ps.size(), compile([for i => p in (ps) i => p], [].asMap(), ps.size())]
```

To run the abstract machine, we'll embed a state machine into an iterator. The
e-graph will set up the state machine, preselecting the verb and arity and
preloading the registers.

```
def makeMatcher(egraph, t, program) as DeepFrozen:
    return def matcher._makeIterator():
        # p4
        var pc := program
        def reg := t.diverge(Int)
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
                        def r := egraph.add([leaf, t], null)
                        pc := if (egraph.find(reg[i]) == egraph.find(r)) {
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
                            # Set up registers.
                            while ((o + s[j].size()) > reg.size()):
                                reg.push(-1)
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
def makeEGraph(analysis) as DeepFrozen:
    # p3
    def U := makeDisjointForest()
    def eM := [].asMap().diverge()
    def H := [].asMap().diverge()
```

In the egg design, each e-class is mapped to its parent e-classes via struct
pointers. Here, we'll use a map from e-classes to maps of parent nodes to
parent e-classes. This removes the need to realize e-classes as structs, and
instead we only refer to them by numeric index. Note that all access to the
parent map is through representative keys only, so we must be careful to
`.find()` each key first.

```
    # XXX it would be nice if we had defaultmap
    def parents := [].asMap().diverge()
```

Similarly, we map from e-classes to associated data generated by e-class
analysis.

```
    def data := [].asMap().diverge()
```

Our canonicalization of e-nodes is almost exactly like the standard one,
except that `leaf` nodes have special handling for concrete data.

```
    def canonicalize(n):
        def [f] + args := n
        return if (f == leaf) { n } else { [f] + [for a in (args) U.find(a)] }
```

And we model the e-graph itself as an object closed over all of these
ingredients.

```
    return object egraph:
        to _printOn(out):
            out.print(`<e-graph, ${U.partitions()} e-classes, ${H.size()} e-nodes>`)
```

When we add e-nodes, we take an additional seed argument which tweaks
analyses. In pratice, this is the source span for ASTs.

```
        # p5
        to add(n, seed) :Int:
            "
            Include `n` as an e-node, returning its e-class.

            Optionally include `seed` data for analysis.
            "

            def enode := canonicalize(n)
            def rv := escape ej { H.fetch(enode, ej) } catch _ {
                def eclass := U.freshClass()
                if (enode =~ [!=leaf] + args) {
                    for child in (args) {
                        if (!parents.contains(child)) {
                            parents[child] := [].asMap()
                        }
                        parents[child] with= (enode, eclass)
                    }
                }
                H[enode] := eclass
                def d := data[eclass] := analysis.make(enode, seed, egraph)
                eM[eclass] := analysis.modify([enode].asSet(), d)
                eclass
            }
            # traceln(`add($n) (enode: ${canonicalize(n)}) -> $rv`)
            return rv
```

The egg design deliberately breaks invariants after each merge operation, and
requires a rebuild operation after many merges. This is something of an API
infelicity, and we can fix it by directly allowing for multiple merge
operations to be submitted in a single batch. At the end of the batch
operation, we'll restore our invariants, and recursive merges made during
invariant maintenance will be turned into an iterative series of batches.

```
        # p8
        to mergePairs(pairs :List) :Bool:
            "
            Merge many `pairs` in a single motion.

            Return whether any e-classes were merged.
            "
            # Worklist is broken into two pieces:
            # * mergelist: next batch of pairs to merge
            # * classlist: next batch of e-classes to rebuild
            var rv := false
            def mergelist := pairs.asSet().diverge()
            while (!mergelist.isEmpty()):
                # merge()
                # traceln("merge()", mergelist)
                def classlist := [].asSet().diverge()
                for [a, b] in (mergelist):
                    def ra := U.find(a)
                    def rb := U.find(b)
                    if (ra != rb):
                        rv := true
                        classlist.include(ra)
                        U.union(ra, rb)
                        parents[ra] := parents[rb] := (
                            parents.fetch(ra, fn { [].asMap() }) |
                            parents.fetch(rb, fn { [].asMap() })
                        )
                        def d := analysis.join(data[ra], data[rb])
                        data[ra] := data[rb] := d
                        eM[ra] := eM[rb] := analysis.modify(eM[ra] | eM[rb], d)

                # Reset the mergelist.
                mergelist.clear()

                # rebuild()
                # traceln("rebuild()", classlist)
                while (!classlist.isEmpty()):
                    for todo in (classlist):
                        def eclass := U.find(todo)
                        # repair()
                        # traceln("repair()", eclass)
                        def oldParents := parents.fetch(eclass, fn { [].asMap() })
                        def newParents := [].asMap().diverge()
                        for parent => pclass in (oldParents):
                            def pnode := canonicalize(parent)

                            if (newParents.contains(pnode)):
                                mergelist.push([pclass, newParents[pnode]])

                            if (H.contains(parent)):
                                H.removeKey(parent)
                            H[pnode] := newParents[pnode] := U.find(pclass)
                        parents[eclass] := newParents.snapshot()

                        # Do we need to rebuild the associated data? First, we
                        # ask this question for the e-class, and if yes, then
                        # ask again for each affected parent.
                        def original := eM[eclass]
                        def modified := analysis.modify(original, data[eclass])
                        if (modified != original):
                            eM[eclass] := modified
                            # Yes, we need to visit each parent.
                            for parent => pclass in (newParents):
                                # Try sprouting a leaf in the joinsemilattice
                                # and see if it makes a difference.
                                def newLeaf := analysis.make(parent, null, egraph)
                                def oldData := data[pclass]
                                def newData := analysis.join(newLeaf, oldData)
                                if (newData != oldData):
                                    data[pclass] := newData
                                    classlist.include(pclass)

                    # Reset the classlist.
                    classlist.clear()
            return rv
```

For completeness, we encapsulate the union-find and e-node maps.

```
        to find(a):
            "The canonical representative of e-class `a`."

            def rv := U.find(a)
            # traceln(`find($a) -> $rv`)
            return rv

        to nodes(a):
            "The e-nodes of e-class `a`."

            return eM[U.find(a)]

        to analyze(a):
            "The associated data from e-graph analysis at e-class `a`."

            return data[U.find(a)]
```

The heavy-duty search functionality starts by filtering e-classes to look up
all e-nodes with a given verb.

```
        to terms(a, f):
            def rv := [].diverge()
            for c in (eM[U.find(a)]):
                def [==f] + args exit __continue := c
                rv.push(args)
            return rv.snapshot()
```

And here is the final portion of e-matching. Note that we scan each e-class
for e-nodes with matching verb and arity, but since e-match programs are
already keyed by verb and arity, we could switch the ordering of these loops:
For each e-class, for each e-node, look up all of the e-matchers which have
that e-node's verb and arity, and apply each of them.

```
        to ematch(p):
            def [f, arity, program] := compilePattern(p)
            def rv := [].diverge()
            for c => nodes in (eM):
                for node in (nodes):
                    def [==f] + args ? (args.size() == arity) exit __continue := node
                    for m in (makeMatcher(egraph, args, program)):
                        rv.push([c] + m)
            return rv.snapshot()
```

Finally, extraction methods allow reconstruction of candidate trees from
within the e-graph's forest of nodes. We'll delegate the actual tree
construction to callers; here, we're more concerned with ordering each e-class
so that the lower-cost constructors are preferred.

```
        to extract(a, nodeOrder):
            "
            A representative of e-class `a`.

            Nodes will be preferred according to `nodeOrder`. Leaves are
            always more preferred than any node, and nodes not in the order
            will be left for last.
            "

            def nodeKeys := [for k => v in (nodeOrder) v => k]
            def schwartzian := makeSchwartzian.fromKeyFunction(fn [f] + _ {
                if (f == leaf) { -1 } else {
                    nodeKeys.fetch(f, fn { Infinity })
                }
            })
            # Only non-cyclic nodes are candidates.
            def candidates := [for n in (eM[U.find(a)]) ? (!n.contains(a)) n]

            return schwartzian.sort(candidates)[0]

        to extractFiltered(a, pred):
            "
            A representative of e-class `a` satisfying predicate `pred`.

            "

            for node in (eM[U.find(a)]):
                def [f] + args := node
                if (pred(f)):
                    return node
            throw(`No members of e-class $a satisfy $pred`)
```
