exports (logic, main)

# http://homes.soic.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

object VARS as DeepFrozen:
    "Variables are tagged with this object."

def makeState(s :Map[Int, Any], c :Int) as DeepFrozen:
    return object state:
        "µKanren 's/c'."

        to _printOn(out):
            out.print("µKanrenState(")
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
            return if (u =~ [==VARS, k] && s.contains(k)) {
                state.walk(s[k])
            } else { u }

        to unify(u, v) :NullOk[Any]:
            def rv := switch ([state.walk(u), state.walk(v)]) {
                match [[==VARS, x], [==VARS, y]] ? (x == y) {state}
                match [[==VARS, x], y] {makeState([x => y] | s, c)}
                match [x, [==VARS, y]] {makeState([y => x] | s, c)}
                match [x, y] {if (x == y) {state}}
            }
            traceln(`Unify: $u ≡ $v in $s: $rv`)
            return rv

object logic as DeepFrozen:
    "A fair backtracking logic monad."

    # Actions are of type `(a -> r -> r) -> r -> r`. We will almost always
    # instantiate `a` to µKanren state, but we keep it generic for sanity.

    to unit(x):
        return def ::"logic.unit"(sk) { return sk(x) }

    to "bind"(action, f):
        # action : (a -> r -> r) -> r -> r
        # f : a -> (b -> r -> r) -> r -> r
        return def ::"logic.bind"(sk) { return action(fn a { f(a)(sk) }) }

    # MonadPlus.

    to zero():
        return fn _ { fn fk { fk } }

    to plus(left, right):
        return fn sk { fn fk { left(sk)(right(sk)(fk)) } }

    to guard(b :Bool):
        return if (b) { logic.unit(null) } else { logic.zero() }

    # LogicT.

    to split(action):
        # action : (a -> r -> r) -> r -> r
        # rv : (Maybe [a, (a -> r -> r) -> r -> r] -> r -> r) -> r -> r
        def reflect(result):
            return if (result =~ [a, act]) {
                logic.plus(logic.unit(a), act)
            } else { logic.zero() }
        def ssk(a):
            return fn fk { logic.unit([a, reflect(fk)]) }
        return action(ssk)(logic.unit(null))

    to interleave(left, right):
        return logic."bind"(logic.split(left), fn r {
            if (r =~ [a, act]) {
                logic.plus(logic.unit(a), logic.interleave(right, act))
            } else { right }
        })

    to ">>-"(action, f):
        return logic."bind"(logic.split(action), fn r {
            if (r =~ [a, act]) {
                logic.interleave(f(a), logic.">>-"(act, f))
            } else { logic.zero() }
        })

    to ifThen(test, cons, alt):
        return logic."bind"(logic.split(test), fn r {
            if (r =~ [a, act]) {
                logic.plus(cons(a), logic."bind"(act, cons))
            } else { alt }
        })

    to once(action):
        return logic."bind"(logic.split(action), fn r {
            if (r =~ [a, _act]) { logic.unit(a) } else { logic.zero() }
        })

    to not(test):
        return logic.ifThen(logic.once(test), fn _ { logic.zero() },
                            logic.unit(null))

    # Collecting results.

    to observe(action, ej):
        # Here `r` is `a`.
        # sk : a -> a -> a
        # fk : a
        return escape sk:
            action(sk)(null)
            throw.eject(ej, "logic.observe/2: No results")

    to collect(action):
        # Here `r` is `[a]`.
        # sk : a -> [a] -> [a]
        # fk : [a]
        def sk(a):
            return fn l { l.with(a) }
        return action(sk)([])

    # µKanren interface.

    to new():
        return logic.unit(makeState([].asMap(), 0))

    to "≡"(u, v):
        return def unify(s):
            def sc := s.unify(u, v)
            return if (sc == null) { logic.zero() } else { logic.unit(sc) }

    # The controller.

    to control(operator :Str, argArity :Int, paramArity :Int, block):
        var currentAction := {
            def [actions, lambda] := block()
            switch ([operator, argArity, paramArity]) {
                match [=="exists", ==1, size] {
                    def [action] := actions
                    logic.">>-"(action, fn var s {
                        def vs := [].diverge()
                        for _ in (0..!size) {
                            def [sc, v] := s.fresh()
                            s := sc
                            vs.push(v)
                        }
                        var acc := logic.unit(s)
                        vs.push(null)
                        def rv := M.call(lambda, "run", vs.snapshot(),
                                         [].asMap())
                        if (rv =~ clauses :List) {
                            for clause in (clauses) {
                                acc := logic.">>-"(acc, clause)
                            }
                        } else { acc := logic.">>-"(acc, rv) }
                        acc
                    })
                }
            }
        }

        return object controller:
            to control(operator :Str, argArity :Int, paramArity :Int, block):
                currentAction := switch ([operator, argArity, paramArity]) {
                    match [=="exists", ==0, size] {
                        def [_, lambda] := block()
                        logic.">>-"(currentAction, fn var s {
                            def vs := [].diverge()
                            for _ in (0..!size) {
                                def [sc, v] := s.fresh()
                                s := sc
                                vs.push(v)
                            }
                            var acc := logic.unit(s)
                            vs.push(null)
                            def rv := M.call(lambda, "run", vs.snapshot(),
                                             [].asMap())
                            if (rv =~ clauses :List) {
                                for clause in (clauses) {
                                    acc := logic.">>-"(acc, clause)
                                }
                            } else { acc := logic.">>-"(acc, rv) }
                            acc
                        })
                    }
                }
                return controller

            to controlRun():
                return currentAction

def main(_argv) as DeepFrozen:
    def action := logic (logic.new()) exists b, c {[
        logic."≡"(b, true),
        logic."≡"(b, c),
    ]} exists i { logic."≡"(i, 5) }
    traceln(logic.observe(action, null))
    traceln(logic.collect(action))
    return 0
