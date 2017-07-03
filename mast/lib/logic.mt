import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (logic, main)

# http://homes.soic.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

object logic as DeepFrozen:
    "A fair backtracking logic monad."

    to unit(x):
        return fn sk { sk(x) }

    to "bind"(action, f):
        # action : (a -> r -> r) -> r -> r
        # f : a -> (b -> r -> r) -> r -> r
        return fn sk { action(fn a { f(a)(sk) }) }

    to zero():
        return fn _ { fn fk { fk } }

    to plus(left, right):
        return fn sk { fn fk { left(sk)(right(sk)(fk)) } }

    to split(action):
        def reflect(result):
            return if (result =~ [a, act]) {
                logic.plus(logic.unit(a), act)
            } else { logic.zero() }
        def ssk(a):
            return fn r { logic.unit([a, logic."bind"(r, reflect)]) }
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

    to observe(action, ej):
        return escape sk:
            action(sk)(ej)

    to collect(action) :List:
        return action(fn a { fn l { l.with(a) } })([])

    to control(operator :Str, argArity :Int, paramArity :Int, block):
        var currentAction := {
            def [actions, lambda] := block()
            switch ([operator, argArity, paramArity]) {
                match ==["choose", 1, 1] {
                    def [iterable] := actions
                    def [head] + tail := [for a in (iterable) a]
                    var act := logic.unit(head)
                    for t in (tail) { act := logic.plus(act, logic.unit(t)) }
                    logic.">>-"(act, fn a { lambda(a, null) })
                }
                match ==["do", 1, 1] {
                    def [action] := actions
                    logic.">>-"(action, fn a { lambda(a, null) })
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
                    match ==["choose", 1, 1] {
                        def [[iterable], lambda] := block()
                        def [head] + tail := [for a in (iterable) a]
                        var act := logic.unit(head)
                        for t in (tail) { act := logic.plus(act, logic.unit(t)) }
                        currentAction := logic.">>-"(currentAction, fn _ { act })
                        logic.">>-"(currentAction, fn a { lambda(a, null) })
                    }
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
    def l := logic.collect(action)
    # Iff x < y, then z < y too.
    hy.assert(l == (x < y).pick([x], []))

unittest([
    prop.test([arb.Int(), arb.Int()], whereSanityCheck),
])

def main(_argv) as DeepFrozen:
    def action := logic (0..10) choose x {
        logic.unit(x * 2)
    } where x :Int { x > 7 }
    traceln(logic.observe(action, throw))
    traceln(logic.collect(action))
    return 0
