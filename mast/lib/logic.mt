import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (logic, main)

# http://homes.soic.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

object state as DeepFrozen:
    "A state monad."

    to unit(x):
        return def ::"state.unit"(s) { return [x, s] }

    to "bind"(action, f):
        return def ::"state.bind"(s) {
            def rv := action(s)
            return escape ej {
                def [a, s2] exit ej := rv
                f(a)(s2)
            } catch problem {
                throw(`.bind/2: $rv from $action to $f was not good: $problem`)
            }
        }

    to get():
        return fn s { [s, s] }

    to put(s):
        return fn _ { [null, s] }

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

    to unit(x):
        return def ::"logic.unit"(sk) { return sk(x) }

    to "bind"(action, f):
        # action : (a -> r -> r) -> r -> r
        # f : a -> (b -> r -> r) -> r -> r
        return def ::"logic.bind"(sk) { return action(fn a { f(a)(sk) }) }

    to zero():
        return fn _ { fn fk { fk } }

    to plus(left, right):
        return fn sk { fn fk { left(sk)(right(sk)(fk)) } }

    to lift(action):
        return fn sk { fn fk { state."bind"(action, fn a { sk(a)(fk) }) } }

    to split(action):
        def reflect(result):
            return if (result =~ [a, act]) {
                logic.plus(logic.unit(a), act)
            } else { logic.zero() }
        def ssk(a):
            return fn fk { state.unit([a, logic."bind"(logic.lift(fk), reflect)]) }
        return logic.lift(action(ssk)(state.unit(null)))

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

    to observe(action, ej):
        def s := makeState([].asMap(), 0)
        return action(fn a { fn fk { state.unit(a) } })(ej)(s)

    to collect(action):
        def s := makeState([].asMap(), 0)
        return action(fn a { fn fk {
            state."bind"(fk, fn l { state.unit(l.with(a)) })
        } })(state.unit([]))(s)

    # µKanren interface.

    to unify(u, v):
        return logic."bind"(logic.lift(state.get()), fn s {
            def sc := s.unify(u, v)
            if (sc == null) { logic.zero() } else {
                logic.lift(state.put(sc))
            }
        })

    to control(operator :Str, argArity :Int, paramArity :Int, block):
        var currentAction := {
            def [actions, lambda] := block()
            switch ([operator, argArity, paramArity]) {
                match [=="fresh", ==1, size] {
                    def [action] := actions
                    logic.">>-"(action, fn a {
                        logic.">>-"(logic.lift(state.get()), fn var s {
                            def vs := [].diverge()
                            for _ in (0..!size) {
                                def [sc, v] := s.fresh()
                                s := sc
                                vs.push(v)
                            }
                            vs.push(null)
                            logic.">>-"(logic.lift(state.put(s)), fn _ {
                                def rv := M.call(lambda, "run", vs.snapshot(),
                                                 [].asMap())
                                # And finally, put `a` back into the monad.
                                logic.">>-"(rv, fn _ { logic.unit(a) })
                            })
                        })
                    })
                }
                match ==["do", 1, 1] {
                    def [action] := actions
                    logic.">>-"(action, fn a { lambda(a, null) })
                }
                match ==["do", 1, 0] {
                    def [action] := actions
                    logic.">>-"(action, fn _ { lambda() })
                }
                match ==["where", 1, 1] {
                    def [action] := actions
                    logic.">>-"(action, fn a {
                        escape ej {
                            if (lambda(a, ej)) {
                                logic.unit(a)
                            } else { logic.zero() }
                        } catch _ { logic.zero() }
                    })
                }
            }
        }

        return object controller:
            to control(operator :Str, argArity :Int, paramArity :Int, block):
                currentAction := switch ([operator, argArity, paramArity]) {
                    match ==["do", 0, 1] {
                        def [_, lambda] := block()
                        logic.">>-"(currentAction, fn a { lambda(a, null) })
                    }
                    match ==["where", 0, 1] {
                        def [_, lambda] := block()
                        logic.">>-"(currentAction, fn a {
                            escape ej {
                                if (lambda(a, ej)) {
                                    logic.unit(a)
                                } else { logic.zero() }
                            } catch _ { logic.zero() }
                        })
                    }
                }
                return controller

            to controlRun():
                return currentAction

def whereSanityCheck(hy, x, y):
    def action := logic (logic.unit(x)) where z { z < y }
    def l := logic.collect(action)[0]
    # Iff x < y, then z < y too.
    hy.assert(l == (x < y).pick([x], []))

unittest([
    prop.test([arb.Int(), arb.Int()], whereSanityCheck),
])

def main(_argv) as DeepFrozen:
    def action := logic (logic.unit(42)) fresh b, c {
        logic (logic.unify(b, true)) do { logic.unify(b, c) }
    }
    traceln(logic.observe(action, throw))
    traceln(logic.collect(action))
    return 0
