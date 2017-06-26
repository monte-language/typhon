exports (main)

object identity as DeepFrozen:
    "The identity monad."

    to unit(x):
        return x

    to "bind"(action, f):
        return f(action)

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

def ev(m, ev, e) as DeepFrozen:
    "
    An extensible definitional interpreter for Monte, in operational monad
    `m`, interpreting expression `e`.
    "

    def r(expr):
        return ev(m, ev, expr)

    return switch (e.getNodeName()):
        # Layer 0: Sequencing.
        match =="LiteralExpr":
            m.unit(e.getValue())
        match =="SeqExpr":
            var rv := m.unit(null)
            for expr in (e.getExprs()):
                rv := m."bind"(rv, fn _ { r(expr) })
            rv

def main(_argv) as DeepFrozen:
    def f(m, ev):
        traceln(`Running interpreter $ev on monad $m`)
        # def ast := m`def x := 5; def y := 2; 42; x; y`
        def ast := m`42; 5; 7`
        def action := ev(m, ev, ast)
        def rv := action(null)
        traceln(rv)
    f(ambT(stateT(identity)), ev)
    f(flowT(identity), ev)
    f(stateT(ambT(identity)), ev)
    return 0
