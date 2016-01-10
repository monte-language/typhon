exports (makeState, runGoal, iterGoal, satisfiable,
         unifyGoal, callFresh, delay, anyOf, allOf)
"μKanren."

object VARS as DeepFrozen:
    "Variables are tagged with this object."

def makeState(s :Map[Int, Any], c :Int) as DeepFrozen:
    return object state:
        "μKanren 's/c'."

        to _printOn(out):
            out.print("μKanrenState(")
            def pairs := ", ".join([for k => v in (s) `_$k := $v`])
            out.print(pairs)
            out.print(")")

        to get(key :Int):
            return s[key]

        to reify(key :Int):
            return state.walk(s[key])

        to reifiedMap() :Map[Int, Any]:
            return [for k => v in (s) k => state.walk(v)]

        to reifiedList() :List:
            return [for k => v in (s) state.walk(v)]

        to fresh():
            return [makeState(s, c + 1), [VARS, c]]

        to walk(u):
            return if (u =~ [==VARS, k]):
                if (s.contains(k)) {state.walk(s[k])} else {u}
            else:
                u

        to unify(u, v) :NullOk[Any]:
            def rv := switch ([state.walk(u), state.walk(v)]) {
                match [[==VARS, x], [==VARS, y]] ? (x == y) {state}
                match [[==VARS, x], y] {makeState([x => y] | s, c)}
                match [x, [==VARS, y]] {makeState([y => x] | s, c)}
                match [x, y] {if (x == y) {state}}
            }
            traceln(`Unify: $u ≡ $v in $s: $rv`)
            return rv

def runGoal(g) as DeepFrozen:
    def emptyState := makeState([].asMap(), 0)
    return g(emptyState)

def iterGoal(g) as DeepFrozen:
    return object kanrenGoalIterable:
        to _makeIterator():
            var i :Int := 0
            var results := runGoal(g)

            def nextState(ej):
                while (true):
                    switch (results) {
                        match [] {ej(`No more states`)}
                        match [x] {results := []; return x}
                        match [x, f] {results := f; return x}
                        match f {results := f()}
                    }

            return object kanrenGoalIterator:
                to next(ej):
                    def state := nextState(ej)
                    def rv := [i, state.reifiedList()]
                    i += 1
                    return rv

def satisfiable(g) :Bool as DeepFrozen:
    "Whether a goal, as stated, can possibly be satisfied."

    var results := runGoal(g)
    while (true):
        switch (results) {
            match [] {return false}
            match [x] {return true}
            match [x, f] {return true}
            match f {results := f()}
        }

def unifyGoal(u, v) as DeepFrozen:
    return def unifyingGoal(state) :List:
        def nextState := state.unify(u, v)
        return if (nextState != null) {[nextState]} else {[]}

def callFresh(f) as DeepFrozen:
    return def freshGoal(state):
        def [freshState, freshVar] := state.fresh()
        return f(freshVar)(freshState)

def mplus(stream1, stream2) as DeepFrozen:
    return switch (stream1) {
        match [] {stream2}
        match [x] + xs {[x, mplus(xs, stream2)]}
        match f {fn {mplus(stream2, f())}}
    }

def mbind(stream, g) as DeepFrozen:
    return switch (stream) {
        match [] {[]}
        match [x] + xs {mplus(g(x), mbind(xs, g))}
        match f {fn {mbind(f(), g)}}
    }

def disj(g1, g2) as DeepFrozen:
    return def orGoal(state):
        return mplus(g1(state), g2(state))

def conj(g1, g2) as DeepFrozen:
    return def andGoal(state):
        return mbind(g1(state), g2)

def delay(g) as DeepFrozen:
    return def delayingGoal(state):
        return def delayedGoal():
            return g(state)

object anyOf as DeepFrozen:
    match [=="run", [goal], _]:
        goal
    match [=="run", goals, _]:
        var g := goals.last()
        for goal in goals.slice(0, goals.size() - 1).reverse():
            g := disj(goal, g)
        g

object allOf as DeepFrozen:
    match [=="run", [goal], _]:
        goal
    match [=="run", goals, _]:
        var g := goals.last()
        for goal in goals.slice(0, goals.size() - 1).reverse():
            g := conj(goal, g)
        g
