import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (logic, main)

# http://homes.soic.indiana.edu/ccshan/logicprog/LogicT-icfp2005.pdf

object identity as DeepFrozen:
    "The identity monad."

    to unit(x):
        return x

    to "bind"(action, f):
        return f(action)

def logicT(m :DeepFrozen) as DeepFrozen:
    return object logic as DeepFrozen:
        "A fair backtracking logic monad."

        # Actions are of type `(a -> m r -> m r) -> m r -> m r`. This strange
        # signature means that many actions in the logic monad don't even
        # involve lifting through the transformed monad!

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
            return fn sk { fn fk { m."bind"(action, fn a { sk(a)(fk) }) } }

        to split(action):
            def reflect(result):
                return if (result =~ [a, act]) {
                    logic.plus(logic.unit(a), act)
                } else { logic.zero() }
            def ssk(a):
                return fn fk { m.unit([a, logic."bind"(logic.lift(fk), reflect)]) }
            return logic.lift(action(ssk)(m.unit(null)))

        to observe(action, ej):
            # Here `r` is `a`.
            # sk : a -> m a -> m a
            # fk : m a
            action(__return)(null)
            throw.eject(ej, "logic.observe/2: No results")

        to collect(action):
            # Here `r` is `[a]`.
            # sk : a -> m [a] -> m [a]
            # fk : m [a]
            def sk(a):
                return fn fk {
                    m."bind"(fk, fn l { m.unit(l.with(a)) })
                }
            def fk := m.unit([])
            return action(sk)(fk)

def stateT(m :DeepFrozen) as DeepFrozen:
    "The state monad transformer."

    # Actions have type `s -> m [a, s]`.

    return object state as DeepFrozen:
        to unit(x):
            return def ::"state.unit"(s) { return m.unit([x, s]) }

        to "bind"(action, f):
            # action : s -> m [a, s]
            # f : a -> s -> m [b, s]
            return def ::"state.bind"(s) {
                return m."bind"(action(s), fn [a, s2] { f(a)(s2) })
            }

        to get():
            return fn s { m.unit([s, s]) }

        to put(s):
            return fn _ { m.unit([null, s]) }

        to zero():
            return fn _ { m.zero() }

        to plus(left, right):
            return fn s { m.plus(left(s), right(s)) }

        to split(action):
            return fn s { [m.split(action(s)), s] }

        to observe(action, s, ej):
            return m.observe(action(s), ej)

        to collect(action, s):
            return m.collect(action(s))

def enrich(m :DeepFrozen) as DeepFrozen:
    "Enrich a monad."

    return object em extends m as DeepFrozen:
        # MonadPlus.

        to guard(b :Bool):
            return if (b) { m.unit(null) } else { m.zero() }

        # LogicT.

        to interleave(left, right):
            return m."bind"(m.split(left), fn r {
                if (r =~ [a, act]) {
                    m.plus(m.unit(a), em.interleave(right, act))
                } else { right }
            })

        to ">>-"(action, f):
            return m."bind"(m.split(action), fn r {
                if (r =~ [a, act]) {
                    em.interleave(f(a), em.">>-"(act, f))
                } else { m.zero() }
            })

        to ifThen(test, cons, alt):
            return m."bind"(m.split(test), fn r {
                if (r =~ [a, act]) {
                    m.plus(cons(a), m."bind"(act, cons))
                } else { alt }
            })

        to once(action):
            return m."bind"(m.split(action), fn r {
                if (r =~ [a, _act]) { m.unit(a) } else { m.zero() }
            })

        to not(test):
            return em.ifThen(em.once(test), fn _ { m.zero() }, m.unit(null))

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

def m :DeepFrozen := enrich(stateT(logicT(identity)))
object logic as DeepFrozen:
    "A logical flow-control device."

    to unit(x):
        return m.unit(x)

    to observe(action, ej):
        def s := makeState([].asMap(), 0)
        return m.observe(action, s, ej)

    to collect(action):
        def s := makeState([].asMap(), 0)
        return m.collect(action, s)

    # µKanren interface.

    to unify(u, v):
        return m."bind"(m.get(), fn s {
            def sc := s.unify(u, v)
            if (sc == null) { m.zero() } else { m.put(sc) }
        })

    to control(operator :Str, argArity :Int, paramArity :Int, block):
        var currentAction := {
            def [actions, lambda] := block()
            switch ([operator, argArity, paramArity]) {
                match [=="fresh", ==1, size] {
                    def [action] := actions
                    m.">>-"(action, fn a {
                        m.">>-"(m.get(), fn var s {
                            def vs := [].diverge()
                            for _ in (0..!size) {
                                def [sc, v] := s.fresh()
                                s := sc
                                vs.push(v)
                            }
                            vs.push(null)
                            m.">>-"(m.put(s), fn _ {
                                def rv := M.call(lambda, "run", vs.snapshot(),
                                                 [].asMap())
                                # And finally, put `a` back into the monad.
                                m.">>-"(rv, fn _ { m.unit(a) })
                            })
                        })
                    })
                }
                match ==["do", 1, 1] {
                    def [action] := actions
                    m.">>-"(action, fn a { lambda(a, null) })
                }
                match ==["do", 1, 0] {
                    def [action] := actions
                    m.">>-"(action, fn _ { lambda() })
                }
                match ==["where", 1, 1] {
                    def [action] := actions
                    m.">>-"(action, fn a {
                        escape ej {
                            if (lambda(a, ej)) { m.unit(a) } else { m.zero() }
                        } catch _ { m.zero() }
                    })
                }
            }
        }

        return object controller:
            to control(operator :Str, argArity :Int, paramArity :Int, block):
                currentAction := switch ([operator, argArity, paramArity]) {
                    match ==["do", 0, 1] {
                        def [_, lambda] := block()
                        m.">>-"(currentAction, fn a { lambda(a, null) })
                    }
                    match ==["where", 0, 1] {
                        def [_, lambda] := block()
                        m.">>-"(currentAction, fn a {
                            escape ej {
                                if (lambda(a, ej)) {
                                    m.unit(a)
                                } else { m.zero() }
                            } catch _ { m.zero() }
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
    {
        def m := stateT(identity)
        def action := m."bind"(m.unit(42), fn a {
            m."bind"(m.get(), fn s {
                m."bind"(m.put(`$s good`), fn _ { m.unit(a) })
            })
        })
        traceln(action("ok"))
    }
    {
        def m := enrich(logicT(identity))
        def nums := {
            def [var head] + tail := [for x in (0..10) m.unit(x)]
            for t in (tail) { head := m.plus(head, t) }
            head
        }
        def action := m.">>-"(nums, fn a {
            m.">>-"(nums, fn b {
                m.">>-"(m.guard(a + b == 9), fn _ { m.unit([a, b]) })
            })
        })
        def sk := fn a { fn l { l.with(a) } }
        def fk := []
        traceln("what", action(sk)(fk))
        traceln("wow", m.split(action)(sk)(fk))
        traceln("wtf", m.collect(action))
        traceln("why not", m.observe(action, null))
    }
    def action := logic (logic.unit(42)) fresh b, c {
        logic (logic.unify(b, true)) do { logic.unify(b, c) }
    }
    traceln(logic.observe(action, null))
    traceln(logic.collect(action))
    return 0
