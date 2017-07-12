import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (anyValue, kanren)
"µKanren."

object VARS as DeepFrozen:
    "Variables are tagged with this object."

object PORTRAYAL as DeepFrozen:
    "Transparent uncalls are tagged with this object."

object anyValue as DeepFrozen:
    "This is not a concrete value."

def makeState(s :Map[Int, Any], c :Int) as DeepFrozen:
    return object state:
        "µKanren 's/c'."

        to _printOn(out):
            out.print("µKanrenState(")
            def pairs := ", ".join([for k => v in (s) `_$k := $v`])
            out.print(pairs)
            out.print(")")

        to reifyAll() :List:
            "
            A list of all reified values, indexed by variable.

            Each element in the list is either a concrete value, or `anyValue`
            if the variable's unification did not result in a concretion.
            "

            # XXX this logic will change when we introduce constraints.
            return [for i in (0..!c) if (s.contains(i)) {
                switch (state.walk(s[i])) {
                    match [==VARS, _] { anyValue }
                    # Rebuild any portrayed objects.
                    match [==PORTRAYAL, target, verb, args, namedArgs] {
                        M.call(target, verb, args, namedArgs)
                    }
                    match rv { rv }
                }
            } else { anyValue }]

        to fresh():
            return [makeState(s, c + 1), [VARS, c]]

        to walk(u):
            return if (u =~ [==VARS, k] && s.contains(k)) {
                state.walk(s[k])
            } else { u }

        to unify(u, v) :NullOk[Any]:
            def rv := switch ([state.walk(u), state.walk(v)]) {
                match [[==VARS, x], [==VARS, y]] ? (x == y) { state }
                match [[==VARS, x], y] { makeState([x => y] | s, c) }
                match [x, [==VARS, y]] { makeState([y => x] | s, c) }
                match [[x] + xs, [y] + ys] {
                    def s := state.unify(x, y)
                    if (s == null) { s } else { s.unify(xs, ys) }
                }
                match [x, ==x] { state }
                match [x :Transparent, y :Transparent] {
                    def l := [PORTRAYAL]
                    state.unify(l + x._uncall(), l + y._uncall())
                }
                match _ { null }
            }
            # traceln(`Unify: $u ≡ $v in $s: $rv`)
            return rv

# NB: Streams can be null, which is the zero, a pair of [result, stream], or a
# thunk which takes zero arguments and returns a stream.

def mplus(stream1, stream2) as DeepFrozen:
    # This early clause prevents an otherwise-common case where `stream1` is a
    # thunk and `stream2 == null`, where we would otherwise return a new thunk
    # and build up useless trash.
    return if (stream2 == null) { stream1 } else {
        switch (stream1) {
            match ==null { stream2 }
            match [x, xs] { [x, mplus(stream2, xs)] }
            match f { fn { mplus(stream2, f()) } }
        }
    }

def mbind(stream, g) as DeepFrozen:
    return switch (stream) {
        match ==null { null }
        match [x, xs] { mplus(g(x), mbind(xs, g)) }
        match f { fn { mbind(f(), g) } }
    }

def disj(g1, g2) as DeepFrozen:
    return def orGoal(state):
        return mplus(g1(state), g2(state))

def conj(g1, g2) as DeepFrozen:
    return def andGoal(state):
        return mbind(g1(state), g2)

interface NoSnooze :DeepFrozen {}

def delay(g) as DeepFrozen:
    return if (g =~ sleepless :NoSnooze) { sleepless } else {
        def delayingGoal(state) {
            return def delayedGoal() { return g(state) }
        }
    }

object kanren as DeepFrozen:
    "A µKanren for relational logical constraint solving."

    # Goal construction.

    to unify(u, v):
        return def unifyingGoal(state) as NoSnooze:
            def nextState := state.unify(u, v)
            return if (nextState != null) { [nextState, null] }

    to fresh(f, count :Int):
        "Create a goal which calls `f` with `count` fresh variables."

        return def freshGoal(var state) as NoSnooze:
            def vars := [for _ in (0..!count) {
                def [freshState, freshVar] := state.fresh()
                state := freshState
                freshVar
            }]
            return M.call(f, "run", vars, [].asMap())(state)

    to unifyAll([head] + tail):
        "Unify all variables."

        return def unifyAllGoal(var state) :List:
            for t in (tail):
                state := state.unify(head, t)
                if (state == null):
                    return []
            return [state]

    to anyOf([head] + tail):
        var g := delay(head)
        for t in (tail):
            g := disj(g, delay(t))
        return g

    to allOf([head] + tail):
        var g := delay(head)
        for t in (tail):
            g := conj(g, delay(t))
        return g

    to table(rows :List):
        "A table-driven relation."

        return object makeTableGoal:
            match [=="run", vars, _]:
                kanren.anyOf([for row in (rows) {
                    kanren.allOf([for i => x in (row) kanren.unify(vars[i], x)])
                }])

    # Collections.

    to satisfiable(g) :Bool:
        "Whether a goal can possibly be satisfied as stated."

        var results := kanren(g)
        while (true):
            switch (results) {
                match ==null { return false }
                match [_, _] { return true }
                match f { results := f() }
            }

    to run(g):
        def emptyState := makeState([].asMap(), 0)
        return g(emptyState)

    to asIterable(g):
        return def kanrenIterable._makeIterator():
            var i :Int := 0
            var results := kanren(g)

            def nextState(ej):
                while (true):
                    switch (results) {
                        match ==null { throw.eject(ej, `No more states`) }
                        match [x, f] { results := f; return x }
                        match f { results := f() }
                    }

            return def kanrenIterator.next(ej):
                def state := nextState(ej)
                def rv := [i, state.reifyAll()]
                i += 1
                return rv

    # Controller.

    to control(operator :Str, argArity :Int, paramArity :Int, block):
        "Build goals incrementally."

        def buildGoal(config, block):
            def [args, lambda] := block()
            return switch (config) {
                match [=="exists", ==0, count :(Int > 0)] {
                    kanren.fresh(object addEjector {
                        match [=="run", vars, _] {
                            M.call(lambda, "run", vars + [null], [].asMap())
                        }
                    }, count)
                }
                match ==["forAll", 1, 1] {
                    def [iterable] := args
                    kanren.allOf([for v in (iterable) lambda(v, null)])
                }
                match ==["forAll", 1, 2] {
                    def [iterable] := args
                    kanren.allOf([for k => v in (iterable) lambda(k, v, null)])
                }
            }

        var g := buildGoal([operator, argArity, paramArity], block)

        return object kanrenController:
            to control(operator :Str, argArity :Int, paramArity :Int, block):
                def nextGoal := buildGoal([operator, argArity, paramArity],
                                          block)
                g := conj(g, nextGoal)
                return kanrenController

            to controlRun():
                return g

def testSingleUnify(hy, i):
    def g := kanren () exists v { kanren.unify(v, i) }
    def l := _makeList.fromIterable(kanren.asIterable(g))
    hy.assert(l == [[i]])

def testTransparentMapUnify(hy, i, j):
    def g := kanren () exists k, v { kanren.unify([k => v], [i => j]) }
    def l := _makeList.fromIterable(kanren.asIterable(g))
    hy.assert(l == [[i, j]])

unittest([
    prop.test([arb.Int()], testSingleUnify),
    prop.test([arb.Int(), arb.Int()], testTransparentMapUnify),
])
