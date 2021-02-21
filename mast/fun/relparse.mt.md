```
exports ()
```

https://arxiv.org/pdf/1902.06591.pdf

Relational parsing over semirings

A recursive transition network, or RTN, is a standard concept in
linguistics. The original paper's paywalled, sadly, but the idea is to have
a graph of the finite states of the parsing automaton, and label each edge
in the graph with one of three types of label:
* shift: the transition consumes an input terminal
* call: the transition runs a non-terminal rule
* reduce: the automaton accepts/returns to the previous rule (with a custom
          non-terminal return code)
So, in a CFG, imagine that we cut up our productions into ribbons. Each
ribbon has the produced non-terminal, and a single line of terminals and
non-terminals. Such a ribbon always decomposes into a series of shifts and
calls, one shift per terminal and call per non-terminal, finished with a
reduce. All of the ribbons for a single production can be glued into a
single graph, sharing the starting state as a root.

```
object term as DeepFrozen {}
object nonterm as DeepFrozen {}

object shift as DeepFrozen {}
object call as DeepFrozen {}
object reduce as DeepFrozen {}

def graphRibbons(startsym, ribbons :List) :List as DeepFrozen:
    "Coalesce the `ribbons` to graphs, with starting non-terminal `startsym`."

    var nextState := 0
    def graph := [].asMap().diverge()
    def starts := [startsym => 0].diverge()
    def atVertex(k) { return graph.fetch(k, fn { graph[k] := [].diverge() }) }

    for [retsym] + ribbon in (ribbons):
        var currentState := starts.fetch(retsym, fn {
            starts[retsym] := nextState += 1
        })
        for [ty, sym] in (ribbon):
            nextState += 1
            switch (ty):
                match ==term:
                    atVertex(currentState).push([shift, sym, nextState])
                match ==nonterm:
                    atVertex(currentState).push([call, sym, nextState])
            currentState := nextState
        atVertex(currentState).push([reduce, retsym])

    # Turn the map into a list, since our states range from 0..n.
    return [for i in (0..nextState) {
        [for link in (graph.fetch(i, fn { [] })) {
            # Fixup calls to point back into the graph.
            if (link =~ [==call, jsym, k]) {
                [call, starts[jsym], k]
            } else { link }
        }]
    }]

def ribbons := [
    ["BP"],
    ["BP", [term, '('], [term, ')'], [nonterm, "BP"]],
    ["BP", [term, '('], [nonterm, "BP"], [term, ')']],
]

def graph := graphRibbons("BP", ribbons)

traceln("graph", graph)
for i => js in (graph):
    traceln(i, js)

traceln("or, as transition rules")
for i => js in (graph):
    for j in (js):
        switch (j):
            match [x, y, z]:
                traceln(`$i -> $z`, x, y)
            match [x, y]:
                traceln(i, x, y)
```

We will need to send those graph edges into a valuation function. This
function will give each graph edge a value in some semiring. We'll then use
the semiring operations on those values, and we'll build up parse networks
in the semiring instead of on the original values.
The motivation for this strange-seeming abstraction is that various
semirings give various flavors of parser. We'll consider:
* Booleans: recognizer
* Sets of lists of transitions: parse forest
More to be added later.

```
object booleanValuation as DeepFrozen:
    to shift(_, _, _):
        return true

    to call(_, _, _):
        return true

    to reduce(_, _):
        return true

object derivationValuation as DeepFrozen:
    to shift(x, y, z):
        return [[shift, x, y, z]].asSet()

    to call(x, y, z):
        return [[call, x, y, z]].asSet()

    to reduce(x, y):
        return [[reduce, x, y]].asSet()
```

We'll need a domain of transitions, notated D in the paper. We want D_a for
each terminal a, which will be a list of pairs of states; each pair
indicates a legal starting and ending state for that terminal. We also want
D_e for the call-reduce sequences. Each sequence starts with some state
stack prefix, ends with another state stack prefix, and pushes a list of
production labels.

```
def findTransitions(graph :List) as DeepFrozen:
    # Map of terminals to shifts.
    def termshifts := [].asMap().diverge()
    # Map of starting states to list of [states :List, labels :List] pairs.
    def reaches := [].asMap().diverge()
    for i => rules in (graph):
        for rule in (rules):
            switch (rule):
                match [==shift, term, j]:
                    def l := termshifts.fetch(term, fn {
                        termshifts[term] := [].diverge()
                    })
                    l.push([i, j])
                match [==call, s, j]:
                    def l := reaches.fetch(i, fn {
                        reaches[i] := [].asSet().diverge()
                    })
                    l.include([[s, j], []])
                match [==reduce, label]:
                    def l := reaches.fetch(i, fn {
                        reaches[i] := [].asSet().diverge()
                    })
                    l.include([[], [label]])
    # Reach out down all of the call-reduce paths.
    var extendMore :Bool := true
    while (extendMore):
        def toExtend := [].diverge()
        for i => reach in (reaches):
            for [states, labels] in (reach):
                if (!states.isEmpty()):
                    toExtend.push([i, states, labels])
        def new := [].diverge()
        for [i, state, labels] in (toExtend):
            if (state.isEmpty()):
                continue
            def [top] + baseStates := state
            for [nextStates, nextLabels] in (reaches.fetch(top, __continue)):
                new.push([i, nextStates + baseStates, labels + nextLabels])
        extendMore := false
        for [i, states, labels] in (new):
            if (!reaches[i].contains([states, labels])):
                extendMore := true
                reaches[i].include([states, labels])
    return [[for k => v in (termshifts) k => v.snapshot()],
            [for i in (0..!graph.size()) reaches.fetch(i, fn { [] }).snapshot()]]

def [transitions :DeepFrozen, nulls :DeepFrozen] := findTransitions(graph)
traceln("transitions", transitions)
for k => v in (nulls):
    traceln("null", k, v)
```

It will matter greatly whether, from a given state, we can reach a reduction
which lowers the overall stack level by one; these states are called
"nullable". After taking the call-reduce closure, we're left with many rules
which each might make a state nullable.

```
def nullableState(v) :Bool as DeepFrozen:
    for [states, _labels] in (v):
        if (states.isEmpty()):
            return true
    return false
def nullables :List[Bool] := [for n in (nulls) nullableState(n)]
traceln("nullable states", nullables)
```

The null closure of a stack simply removes all of the nullable states from
the stack.

```
def nullClosure(stack :List[Int]) :List[Int] as DeepFrozen:
    return [for s in (stack) ? (nullables[s]) s]
```

We can now consider phases. A phase is when we eat a terminal and advance
forward. From a given set of state stacks, we'll take the shift closure of
those stacks with respect to the eaten terminal, and then the call-reduce
closure, and finally the null closure.

```
def phase(inputs :Set, terminal) :Set as DeepFrozen:
    def rv := [].asSet().diverge()
    for [s, t] in (transitions[terminal]):
        for [states, labels] in (inputs):
            def [==s] + s0 exit __continue := states
            traceln("base", s0, "transition", s, "->", t)
            rv.include([[t] + s0, labels])
            for [ts, tl] in (nulls[t]):
                rv.include([nullClosure(ts) + s0, labels + tl])
                if (nullables[t] &! s0.isEmpty()):
                    def [sp] + s1 := s0
                    traceln("base", s1, "closure", sp)
                    for [ns, nl] in (nulls[sp]):
                        rv.include([nullClosure(ns) + s1, nl + tl])
    return rv.snapshot()

def start := [[0], []]
var current := [start].asSet()
for i => char in ("()(())(()(()))"):
    current := phase(current, char)
    traceln("phase", i, current)
```
