import "unittest" =~ [=> unittest :Any]
exports (main)

object PRA as DeepFrozen:
    "
    Primitive recursive arithmetic.

    This auditor audits and guards primitive recursive functions.
    "

    to coerce(var specimen, ej):
        if (!_auditedBy(PRA, specimen)):
            specimen _conformTo= (PRA)
            if (!_auditedBy(PRA, specimen)):
                throw.eject(ej, `Not primitive recursive: $specimen`)
        return specimen

    to audit(audition) :Bool:
        # Must be DF.
        audition.ask(DeepFrozen)

        # Grab the body. We only enforce behavior for .run().
        def objExpr := astBuilder.convertFromKernel(audition.getObjectExpr())
        def run := objExpr.getScript().getMethodNamed("run", throw)
        def body := switch (run.getBody()) {
            match m`escape @ej {
                @call.run(@inner)
                null
            }` ? (ej.getNoun().getName() == call.getName()) { inner }
            match inner { inner }
        }

        # Check the return guard.
        def checkGuard(g :Str):
            if (g != "Int" && g != "Bool") {
                throw(`PRA parameters must be Int or Bool, not $g`)
            }
            return safeScope[`&&$g`].get().get()
        def rvGuard := checkGuard(run.getResultGuard().getName())

        # Grab the args and set up the local scope.
        def args := [for patt in (run.getParams())
            patt.getNoun().getName() => checkGuard(patt.getGuard().getName())]
        def scopeStack := [args].diverge()

        # Recurse through the body, pulling apart each expression into atoms
        # and checking their validity.
        def go(expr):
            return switch (expr.getNodeName()) {
                match =="IfExpr" {
                    if (go(expr.getTest()) != Bool) {
                        throw(`If-expr test not Bool: $expr`)
                    }
                    def lhs := go(expr.getThen())
                    def rhs := go(expr.getElse())
                    if (lhs != rhs) {
                        throw(`If-expr arms aren't same type: $lhs != $rhs`)
                    }
                    lhs
                }
                match =="LiteralExpr" {
                    if (expr.getValue() !~ _ :(Int >= 0)) {
                        throw(`Literal not Int >= 0: $expr`)
                    }
                    Int
                }
                match =="MethodCallExpr" {
                    switch ([go(expr.getReceiver()), expr.getVerb()]) {
                        match ==[Int, "add"] {
                            if (go(expr.getArgs()[0]) != Int) {
                                throw(`Incorrectly-typed call: $expr`)
                            }
                        }
                    }
                    Int
                }
                match =="NounExpr" {
                    scopeStack.last().fetch(expr.getName(), fn {
                        throw(`Forbidden noun: $expr`)
                    })
                }
            }
                    
        def bodyGuard := go(body)
        if (bodyGuard != rvGuard) {
            throw(`Body doesn't match result guard: $bodyGuard != $rvGuard`)
        }

        # All done.
        return true

def PRAZero(assert):
    assert.willNotThrow(fn {
        def zero() :Int as PRA { return 0 }
    })

def PRASucc(assert):
    assert.willNotThrow(fn {
        def succ(x :Int) :Int as PRA { return x + 1 }
    })

unittest([
    PRAZero,
    PRASucc,
])

def main(_argv) as DeepFrozen:
    traceln(PRA)
    def pick(x :Int, y :Int, b :Bool) :Int as PRA:
        return if (b) { x } else { y }
    traceln(pick(2, 3, false))
    return 0
