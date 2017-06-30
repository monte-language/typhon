exports (main)

object identity as DeepFrozen:
    "The identity monad."

    to unit(x):
        return x

    to "bind"(action, f):
        return f(action)

def eitherT(m :DeepFrozen) as DeepFrozen:
    "The either monad transformer."

    object LEFT as DeepFrozen {}
    object RIGHT as DeepFrozen {}

    return object either as DeepFrozen:
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

        to get():
            return m."bind"(m.get(), either.unit)

        to put(x):
            return m."bind"(m.put(x), either.unit)

def readerT(m :DeepFrozen) as DeepFrozen:
    "The reader monad transformer."

    return object reader as DeepFrozen:
        to _printOn(out):
            out.print(`<reader($m)>`)

        to unit(x):
            return fn _ { m.unit(x) }

        to "bind"(action, f):
            return fn e { m."bind"(action(e), fn a { f(a)(e) }) }

        to ask():
            return fn e { m.unit(e) }

        to local(f, action):
            return fn e { action(f(e)) }

        to fail(message):
            return m."bind"(m.fail(message), reader.unit)

        to get():
            return m."bind"(m.get(), reader.unit)

        to put(x):
            return m."bind"(m.put(x), reader.unit)

        to zero():
            return m."bind"(m.zero(), reader.unit)

        to alt(left, right):
            return fn e { m.alt(left(e), right(e)) }

def stateT(m :DeepFrozen) as DeepFrozen:
    "The state monad transformer."

    return object state as DeepFrozen:
        to _printOn(out):
            out.print(`<state($m)>`)

        to unit(x):
            return def unit(s) { return m.unit([x, s]) }

        to "bind"(action, f):
            return def ::"bind"(s) {
                return m."bind"(action(s), fn [a, s2] { f(a)(s2) })
            }

        to get():
            return def get(s) {
                return m.unit([s, s])
            }

        to put(x):
            return def put(_) {
                return m.unit([null, x])
            }

        to zero():
            return def zero(_) { return m.zero() }

        to alt(left, right):
            return def alt(s) { return m.alt(left(s), right(s)) }

def ambT(m :DeepFrozen) as DeepFrozen:
    "
    The non-determinism monad transformer.

    This implementation uses `Set` to model non-determinism.
    "

    return object amb as DeepFrozen:
        to _printOn(out):
            out.print(`<amb($m)>`)

        to unit(x):
            return m.unit([x].asSet())

        to "bind"(action, f):
            return m."bind"(action, fn xs {
                var rv := m.unit([].asSet())
                for x in (xs) { rv := amb.alt(rv, f(x)) }
                rv
            })

        to get():
            return m."bind"(m.get(), amb.unit)

        to put(x):
            return m."bind"(m.put(x), amb.unit)

        to zero():
            return m.unit([].asSet())

        to alt(left, right):
            return m."bind"(left, fn l {
                m."bind"(right, fn r { m.unit(l | r) })
            })

def flowT(m :DeepFrozen) as DeepFrozen:
    "Flow-sensitive non-determinism monad."

    return object flow as DeepFrozen:
        to _printOn(out):
            out.print(`<flow($m)>`)

        to unit(x):
            return fn s { m.unit([x => s]) }

        to "bind"(action, f):
            return fn s {
                m."bind"(action(s), fn xs {
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
            return fn s { m.unit([s => s]) }

        to put(x):
            return fn _ { m.unit([null => x]) }

        to zero():
            return fn s { m.unit([].asMap()) }

        to alt(left, right):
            return fn s {
                m."bind"(left(s), fn l {
                    m."bind"(right(s), fn r { m.unit(l | r) })
                })
            }

def makeMonadControl(m :DeepFrozen, operator :Str, argArity :Int,
                     paramArity :Int, block) as DeepFrozen:
    # XXX check if monad supports .fail/1 and enable it in that case!
    var action := switch ([operator, argArity, paramArity]) {
        match [=="do", _size, ==_size] {
            def [values, lambda] := block()
            var collector := m.unit([])
            for value in (values) {
                collector := m."bind"(collector, fn xs {
                    m."bind"(value, fn v { m.unit(xs.with(v)) })
                })
            }
            m."bind"(collector, fn xs {
                M.call(lambda, "run", xs.with(null), [].asMap())
            })
        }
        match [=="do", _size, ==0] {
            def [values, lambda] := block()
            var runner := m.unit(null)
            for value in (values) {
                runner := m."bind"(runner, fn _ { value })
            }
            m."bind"(runner, fn _ { lambda() })
        }
        match ==["lift", 1, 1] {
            def [[value], lambda] := block()
            m."bind"(value, fn x { m.unit(lambda(x, null)) })
        }
        match ==["lift", 1, 0] {
            def [[value], lambda] := block()
            m."bind"(value, fn _ { m.unit(lambda()) })
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

def operational(m :DeepFrozen) as DeepFrozen:
    "Make a monad fully operational."

    return object operationalMonad extends m as DeepFrozen:
        to _printOn(out):
            out.print(`<*($m)>`)

        to control(operator :Str, argArity :Int, paramArity :Int, block):
            return makeMonadControl(operationalMonad, operator, argArity,
                                    paramArity, block)

        to modify(f):
            return m."bind"(m.get(), fn s { m.put(f(s)) })

        to lookup(name):
            return m."bind"(m.get(), fn store {
                if (store.contains(name)) { m.unit(store[name]) } else {
                    m."bind"(m.ask(), fn env {
                        if (env.contains(name)) { m.unit(env[name]) } else {
                            m.fail(`Name $name not found`)
                        }
                    })
                }
            })

        to freshScope(action):
            return m."bind"(m.get(), fn store {
                m.local(fn e { e | store },
                        m."bind"(m.put([].asMap()), fn _ { action }))
            })

def makeBinding(value, guard, isFinal :Bool) as DeepFrozen:
    return object binding:
        to _printOn(out):
            out.print(`<binding($value, $guard, $isFinal)>`)

        to isFinal():
            return isFinal

        to getGuard():
            return guard

        to get():
            return def slot.get():
                return value

def ev(m, ev, e) as DeepFrozen:
    "
    An extensible definitional interpreter for Monte, in operational monad
    `m`, interpreting expression `e`.
    "

    if (e == null):
        return m.unit(null)

    def r(expr):
        return ev(m, ev, expr)

    def matchBind(patt, specimen, _ej):
        return switch (patt.getNodeName()):
            match =="FinalPattern":
                m (r(patt.getGuard())) do g {
                    def binding := makeBinding(specimen, g, true)
                    m.modify(fn store {
                        store.with("&&" + patt.getNoun().getName(), binding)
                    })
                }
            match =="VarPattern":
                m (r(patt.getGuard())) do g {
                    def binding := makeBinding(specimen, g, false)
                    m.modify(fn store {
                        store.with("&&" + patt.getNoun().getName(), binding)
                    })
                }

    return switch (e.getNodeName()):
        # Layer 0: Sequencing.
        match =="LiteralExpr":
            m.unit(e.getValue())
        match =="SeqExpr":
            var rv := m.unit(null)
            for expr in (e.getExprs()):
                rv := m (rv) do { r(expr) }
            rv
        # Layer 1: Read-only store.
        match =="NounExpr":
            m (m.lookup("&&" + e.getName())) lift b { b.get().get() }
        match =="BindingExpr":
            m.lookup("&&" + e.getName())
        # Layer 2: Read-write store.
        match =="DefExpr":
            m (r(e.getExpr()), r(e.getExit())) do rhs, ex {
                m (matchBind(e.getPattern(), rhs, ex)) lift { rhs }
            }
        match =="AssignExpr":
            def name := "&&" + e.getLvalue().getName()
            m (r(e.getRvalue()), m.lookup(name)) do rhs, b {
                if (!b.isFinal()) {
                    def binding := makeBinding(rhs, b.getGuard(), false)
                    m (m.modify(fn store {
                        store.with(name, binding)
                    })) lift { rhs }
                } else {
                    m.fail(`Binding $b was final!`)
                }
            }
        # Layer 3: Scopes.
        match =="HideExpr":
            m.freshScope(r(e.getBody()))
        match =="IfExpr":
            m.freshScope(m (r(e.getTest())) do test {
                if (test =~ b :Bool) {
                    m.freshScope(r(b.pick(e.getThen(), e.getElse())))
                } else {
                    m.fail(`Test value $test didn't conform to Bool`)
                }
            })

def main(_argv) as DeepFrozen:
    def f(m, ev):
        def om := operational(m)
        traceln(`control demo`)
        def demoAction := om (m.unit(42)) do x { om.unit(x + 1) } lift x {
            x * 2
        }
        traceln(demoAction(null)(null))
        traceln(`Running interpreter $ev on monad $om`)
        # def ast := m`def x := 5; def y := 2; 42; x; y`
        def ast := m`def x := 1; { def y := 2 }; if (true) { 2 } else { 3 }`
        def action := ev(om, ev, ast)
        def env := [=> &&true]
        def store := [].asMap()
        def rv := action(env)(store)
        traceln(rv)
    f(readerT(eitherT(stateT(identity))), ev)
    return 0
