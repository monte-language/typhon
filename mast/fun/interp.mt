import "fun/monads" =~ [=> makeMonad]
exports (go)

object vatMonoid as DeepFrozen:
    to one():
        return []

    to multiply(x, y):
        return x + y

def monteMonad :DeepFrozen := makeMonad.error(makeMonad.rws(makeMonad.identity(), vatMonoid))

def makeInterpreter(m :DeepFrozen, d :DeepFrozen) as DeepFrozen:
    "Build an interpreter on monad `m` and domain `d`."

    return def interpret(expr :DeepFrozen) as DeepFrozen:
        return switch (expr.getNodeName()):
            match =="LiteralExpr":
                m.pure(d.literal(expr.getValue()))
            match =="NounExpr":
                def name := expr.getName()
                m (m.get()) map frame { frame[name] }

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
            match [==Int, =="add", [==Int, ==Int]]:
                Int

def interp :DeepFrozen := makeInterpreter(monteMonad, concreteMonte)
traceln(`interp $interp`)

def tycheck :DeepFrozen := makeInterpreter(monteMonad, typesOnly)
traceln(`tycheck $tycheck`)

def go() as DeepFrozen:
    def abs := interp(m`x`)
    traceln(`action $abs`)
    escape ej:
        traceln(`ejector $ej`)
        def flowed := abs(ej)
        traceln(`flowed action $flowed`)
        def rv := flowed(null, ["x" => Int])
        traceln(`rv $rv`)

    def action := interp(m`x`)
    traceln(`action $action`)
    escape ej:
        traceln(`ejector $ej`)
        def flowed := action(ej)
        traceln(`flowed action $flowed`)
        def rv := flowed(null, ["x" => 42])
        traceln(`rv $rv`)
