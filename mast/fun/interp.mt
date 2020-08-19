import "fun/monads" =~ [=> makeMonad, => sequence]
exports (go)

object vatMonoid as DeepFrozen:
    to one():
        return []

    to multiply(x, y):
        return x + y

def traceFrame(m :DeepFrozen, action, message :Str) as DeepFrozen:
    return m (action) do rv {
        m (m.get()) map frame {
            traceln(`traceFrame: $frame ($message)`)
            rv
        }
    }

def sequenceLast(m :DeepFrozen, [ma] + mas) as DeepFrozen:
    "
    Run `ma` and then `mas` in sequence in monad `m` and return a single
    monadic action which just has the final result.

    Like `sequence`, but faster because it does not build a massive
    intermediate list of results. Still quadratic, though.
    "

    return if (mas.isEmpty()) { ma } else {
        m (ma) do _ { sequenceLast(m, mas) }
    }

def monteMonad :DeepFrozen := makeMonad.error(makeMonad.rws(makeMonad.identity(), vatMonoid))

def makeInterpreter(m :DeepFrozen, d :DeepFrozen) as DeepFrozen:
    "Build an interpreter on monad `m` and domain `d`."

    return object interpret as DeepFrozen:
        to namedArgs(_namedArgs):
            # XXX
            return m.pure([].asMap())

        to matchBind(patt :DeepFrozen):
            # Pattern actions yield null. We take an expression action which
            # yields the value to be bound.
            return switch (patt.getNodeName()):
                match =="FinalPattern":
                    def name :Str := patt.getNoun().getName()
                    fn specimen, _ej {
                        m.modify(fn frame {
                            frame.with(name, specimen)
                        })
                    }

        to nullOk(maybe :NullOk[DeepFrozen]):
            return if (maybe == null) { m.pure(null) } else { interpret(maybe) }

        to run(expr :DeepFrozen):
            # Expression actions yield values.
            return switch (expr.getNodeName()):
                match =="SeqExpr":
                    sequenceLast(m, [for e in (expr.getExprs()) interpret(e)])
                match =="LiteralExpr":
                    m.pure(d.literal(expr.getValue()))
                match =="NounExpr":
                    def name := expr.getName()
                    m (m.get()) map frame { frame[name] }
                match =="MethodCallExpr":
                    def receiver := interpret(expr.getReceiver())
                    def verb :Str := expr.getVerb()
                    def args :List := [for a in (expr.getArgs()) interpret(a)]
                    def namedArgs := interpret.namedArgs(expr.getNamedArgs())
                    m (receiver) do r {
                        m (sequence(m, args)) do a {
                            m (namedArgs) map na {
                                traceln(`r $r verb $verb args $a namedArgs $na`)
                                d.call(r, verb, a, na)
                            }
                        }
                    }
                match =="DefExpr":
                    def rhs := interpret(expr.getExpr())
                    def ex := interpret.nullOk(expr.getExit())
                    def patt := interpret.matchBind(expr.getPattern())
                    m (rhs) do rv {
                        m (ex) do ej {
                            m (patt(rv, ej)) map _ { rv }
                        }
                    }

object concreteMonte as DeepFrozen:
    to literal(x):
        return x

    to call(receiver, verb :Str, args :List, namedArgs :Map):
        return M.call(receiver, verb, args, namedArgs)

object typesOnly as DeepFrozen:
    to literal(x):
        return x._getAllegedInterface()

    to call(receiver, verb :Str, args :List, _namedArgs :Map):
         return switch ([receiver, verb, args]):
            match [==Int, =="add", [==Int]]:
                Int

def interp :DeepFrozen := makeInterpreter(monteMonad, concreteMonte)
traceln(`interp $interp`)

def tycheck :DeepFrozen := makeInterpreter(monteMonad, typesOnly)
traceln(`tycheck $tycheck`)

def go() as DeepFrozen:
    def expr := m`def y := 3; 4; x.add(y)`
    def abs := tycheck(expr)
    traceln(`action $abs`)
    escape ej:
        traceln(`ejector $ej`)
        def flowed := abs(ej)
        traceln(`flowed action $flowed`)
        def rv := flowed(null, ["x" => Int])
        traceln(`rv $rv`)

    def action := interp(expr)
    traceln(`action $action`)
    escape ej:
        traceln(`ejector $ej`)
        def flowed := action(ej)
        traceln(`flowed action $flowed`)
        def rv := flowed(null, ["x" => 3])
        traceln(`rv $rv`)
