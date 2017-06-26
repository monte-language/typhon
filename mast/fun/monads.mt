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

def operational(m :DeepFrozen) as DeepFrozen:
    "Make a monad fully operational."

    return object operationalMonad extends m as DeepFrozen:
        to _printOn(out):
            out.print(`<*($m)>`)

        to modify(f):
            return m."bind"(m.get(), fn s { m.put(f(s)) })

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
                m."bind"(r(patt.getGuard()), fn g {
                    def binding := makeBinding(specimen, g, true)
                    m.modify(fn store {
                        store.with("&&" + patt.getNoun().getName(), binding)
                    })
                })
            match =="VarPattern":
                m."bind"(r(patt.getGuard()), fn g {
                    def binding := makeBinding(specimen, g, false)
                    m.modify(fn store {
                        store.with("&&" + patt.getNoun().getName(), binding)
                    })
                })

    return switch (e.getNodeName()):
        # Layer 0: Sequencing.
        match =="LiteralExpr":
            m.unit(e.getValue())
        match =="SeqExpr":
            var rv := m.unit(null)
            for expr in (e.getExprs()):
                rv := m."bind"(rv, fn _ { r(expr) })
            rv
        # Layer 1: Read-only store.
        match =="NounExpr":
            m."bind"(m.get(), fn [("&&" + e.getName()) => b] | _ {
                m.unit(b.get().get())
            })
        match =="BindingExpr":
            m."bind"(m.get(), fn [("&&" + e.getName()) => b] | _ {
                m.unit(b)
            })
        # Layer 2: Read-write store.
        match =="DefExpr":
            m."bind"(r(e.getExpr()), fn rhs {
                m."bind"(r(e.getExit()), fn ex {
                    m."bind"(matchBind(e.getPattern(), rhs, ex), fn ==null {
                        m.unit(rhs)
                    })
                })
            })
        match =="AssignExpr":
            def name := "&&" + e.getLvalue().getName()
            m."bind"(r(e.getRvalue()), fn rhs {
                m."bind"(m.get(), fn [(name) => b] | store {
                    if (!b.isFinal()) {
                        def binding := makeBinding(rhs, b.getGuard(), false)
                        m."bind"(m.put(store.with(name, binding)), fn ==null {
                            m.unit(rhs)
                        })
                    } else {
                        m.fail(`Binding $b was final!`)
                    }
                })
            })
        # Layer 3: Scopes.
        match =="HideExpr":
            m."bind"(m.get(), fn store {
                m.local(fn e { e | store }, r(e.getBody()))
            })

def main(_argv) as DeepFrozen:
    def f(m, ev):
        def om := operational(m)
        traceln(`Running interpreter $ev on monad $om`)
        # def ast := m`def x := 5; def y := 2; 42; x; y`
        def ast := m`def x := 1; { def y := 2 }; 3`
        def action := ev(om, ev, ast)
        def rv := action([].asMap())([].asMap())
        traceln(rv)
    f(readerT(eitherT(stateT(identity))), ev)
    return 0
