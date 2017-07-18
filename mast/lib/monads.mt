import "unittest" =~ [=> unittest]
exports (identity)

# A few good monads. This design features tags for monadic values to minimize
# programmer error, as well as controller syntax support.

def sequence(m :DeepFrozen, l :List) as DeepFrozen:
    "
    Collate a list `l` of monadic actions in monad `m` into a single action,
    yielding a list of the yields of each individual action.
    "

    return if (l =~ [head] + tail):
        var rv := m."bind"(head, fn x { m.unit([x]) })
        for action in (tail):
            rv := m."bind"(rv, fn xs {
                m."bind"(action, fn x { m.unit(xs.with(x)) })
            })
        rv
    else:
        m.unit([])

def complete(m :DeepFrozen) as DeepFrozen:
    # Allow failures to propagate into the monad, for monads which support
    # either failure or a monoidal zero.
    def hasFail :Bool := m._respondsTo("fail", 1)
    def fail(message) as DeepFrozen:
        return if (hasFail) { m.fail(message) } else { throw(message) }

    def collect(block, => lift :Bool) as DeepFrozen:
        def [values, lambda] := block()
        return m."bind"(sequence(m, values), fn xs {
            escape ej {
                def rv := M.call(lambda, "run", xs.with(ej), [].asMap())
                if (lift) { m.unit(rv) } else { rv }
            } catch problem {
                fail(`Failure in monad: $problem`)
            }
        })

    def run(block, => lift :Bool) as DeepFrozen:
        def [values, lambda] := block()
        var runner := m.unit(null)
        for value in (values) {
            runner := m."bind"(runner, fn _ { value })
        }
        return m."bind"(runner, fn _ {
            def rv := lambda()
            if (lift) { m.unit(rv) } else { rv }
        })

    return object controllableMonad extends m as DeepFrozen:
        to _printOn(out):
            out.print(`<controllable($m)>`)

        to control(operator :Str, argArity :Int, paramArity :Int, block):
            var action := switch ([operator, argArity, paramArity]) {
                match [=="do", _size, ==_size] {
                    collect(block, "lift" => false)
                }
                match [=="do", _size, ==0] {
                    run(block, "lift" => false)
                }
                match [=="lift", _size, ==_size] {
                    collect(block, "lift" => true)
                }
                match [=="lift", _size, ==0] {
                    run(block, "lift" => true)
                }
                match ==["modify", 1, 1] {
                    def [[value], lambda] := block()
                    m."bind"(value, fn x {
                        m."bind"(m.modify(fn s { lambda(s, null) }), fn _ {
                            m.unit(x)
                        })
                    })
                }
            }
            return object controlFlow:
                to control(operator :Str, argArity :Int, paramArity :Int, block):
                    def [values, lambda] := block()
                    action := switch ([operator, argArity, paramArity]) {
                        match ==["do", 0, 1] {
                            m."bind"(action, fn x { lambda(x, null) })
                        }
                        match ==["lift", 0, 1] {
                            m."bind"(action, fn x { m.unit(lambda(x, null)) })
                        }
                        match ==["lift", 0, 0] {
                            m."bind"(action, fn x { m.unit(lambda()) })
                        }
                        match ==["modify", 0, 1] {
                            m."bind"(action, fn x {
                                m."bind"(m.modify(fn s { lambda(s, null) }), fn _ {
                                    m.unit(x)
                                })
                            })
                        }
                    }
                    return controlFlow

                to controlRun():
                    return action

object id as DeepFrozen:
    "The identity monad."

    to unit(x):
        return x

    to "bind"(action, f):
        return f(action)

def identity :DeepFrozen := complete(id)

def testIdentityNatural(assert):
    object unchanged {}
    def m := identity
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action, unchanged)

unittest([
    testIdentityNatural,
])

def either(m :DeepFrozen) as DeepFrozen:
    "The 'Either' monad transformer."

    object LEFT as DeepFrozen {}
    object RIGHT as DeepFrozen {}

    object either as DeepFrozen:
        to _printOn(out):
            out.print(`<either($m)>`)

        to unit(x):
            return m.unit([RIGHT, x])

        to "bind"(action, f):
            return m."bind"(action, fn a {
                if (a =~ [==RIGHT, v]) { f(v) } else { m.unit(a) }
            })

        to fail(message):
            return m.unit([LEFT, message])

        to isLeft(action):
            return action[0] == LEFT

    return complete(either)

def testEitherNatural(assert):
    object unchanged {}
    def m := either(identity)
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action[1], unchanged)

unittest([
    testEitherNatural,
])

def reader(m :DeepFrozen) as DeepFrozen:
    "The 'Reader' monad transformer."

    interface Reader :DeepFrozen {}

    object reader as DeepFrozen:
        to _printOn(out):
            out.print(`<reader($m)>`)

        to unit(x):
            return def ::"reader.unit"(_) as Reader { return m.unit(x) }

        to "bind"(action :Reader, f):
            return def ::"reader.bind"(e) as Reader:
                return m."bind"(action(e), fn a { f(a)(e) })

        to ask():
            return def ::"reader.ask"(e) as Reader { return m.unit(e) }

        to local(f, action :Reader):
            return def ::"reader.local"(e) as Reader { return action(f(e)) }

    return complete(reader)

def testReaderNatural(assert):
    object unchanged {}
    def m := reader(identity)
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action(null), unchanged)

unittest([
    testReaderNatural,
])

def state(m :DeepFrozen) as DeepFrozen:
    "The 'State' monad transformer."

    interface State :DeepFrozen {}

    object state as DeepFrozen:
        to _printOn(out):
            out.print(`<state($m)>`)

        to unit(x):
            return def ::"state.unit"(s) as State { return m.unit([x, s]) }

        to "bind"(action :State, f):
            return def ::"state.bind"(s) as State {
                return m."bind"(action(s), fn [a, s2] { f(a)(s2) })
            }

        to get():
            return def ::"state.get"(s) as State { return m.unit([s, s]) }

        to put(x):
            return def ::"state.put"(_) as State { return m.unit([null, x]) }

    return complete(state)

def testStateNatural(assert):
    object unchanged {}
    object magicState {}
    def m := state(identity)
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action(magicState), [unchanged, magicState])

unittest([
    testStateNatural,
])

def amb(m :DeepFrozen) as DeepFrozen:
    "
    A non-determinism monad transformer.

    This implementation uses `Set` to model non-determinism.
    "

    object amb as DeepFrozen:
        to _printOn(out):
            out.print(`<amb($m)>`)

        to unit(x):
            return m.unit([x].asSet())

        to "bind"(action :Set, f):
            return m."bind"(action, fn xs {
                var rv := m.unit([].asSet())
                for x in (xs) { rv := amb.alt(rv, f(x)) }
                rv
            })

        to zero():
            return m.unit([].asSet())

        to alt(left :Set, right :Set):
            return m."bind"(left, fn l {
                m."bind"(right, fn r { m.unit(l | r) })
            })

    return complete(amb)

def testAmbNatural(assert):
    object unchanged {}
    def m := amb(identity)
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action, [unchanged].asSet())

unittest([
    testAmbNatural,
])

def flow(m :DeepFrozen) as DeepFrozen:
    "
    A non-determinism stateful monad transformer.

    This transformer models state and non-determinism by linking each
    non-deterministic path to its own state. The resulting monad's
    non-determinism is control-flow-sensitive in a unique way.
    "

    interface Flow :DeepFrozen {}

    object flow as DeepFrozen:
        to _printOn(out):
            out.print(`<flow($m)>`)

        to unit(x):
            return def ::"flow.unit"(s) as Flow { return m.unit([x => s]) }

        to "bind"(action :Flow, f):
            return def ::"flow.bind"(s) as Flow {
                return m."bind"(action(s), fn xs {
                    var rv := m.unit([].asMap())
                    def actions := [for k => v in (xs) f(k)(v)]
                    for a in (actions) {
                        rv := m."bind"(rv, fn l {
                            m."bind"(a, fn r { m.unit(l | r) })
                        })
                    }
                    rv
                })
            }

        to get():
            return def ::"flow.get"(s) as Flow { return m.unit([s => s]) }

        to put(x):
            return def ::"flow.put"(_) as Flow { return m.unit([null => x]) }

        to zero():
            return def ::"flow.zero"(_) as Flow { return m.unit([].asMap()) }

        to alt(left :Flow, right :Flow):
            return def ::"flow.alt"(s) {
                return m."bind"(left(s), fn l {
                    m."bind"(right(s), fn r { m.unit(l | r) })
                })
            }

    return complete(flow)

def testFlowNatural(assert):
    object unchanged {}
    object magicState {}
    def m := flow(identity)
    def action := m (m.unit(unchanged)) do x { m.unit(x) }
    assert.equal(action(magicState), [unchanged => magicState])

unittest([
    testFlowNatural,
])
