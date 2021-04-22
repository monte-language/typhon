import "lib/mim/syntax/kernel" =~ ["ASTBuilder" => monteBuilder]
import "lib/mim/expand" =~ [=> expand]
exports (holdAuditions)

# Expand auditors into inline auditions. After transformation, the auditors on
# objects are accepted unconditionally and without invoking auditions; the
# entire audition logic is encapsulated in the expansion.

def makeList(elements :List, span) as DeepFrozen:
    return monteBuilder.MethodCallExpr(
        monteBuilder.NounExpr("_makeList", span),
        "run", elements, [], span)

def asAST(_span) as DeepFrozen:
    # XXX reflect span
    def reflectedSpan := expand(m`null`)
    return object reflectScript:
        match [verb, args, _]:
            def span := args.last()
            def go(arg):
                return switch (arg) {
                    match xs :List { makeList([for x in (xs) go(x)], span) }
                    match l :Any[Int, Str] {
                        monteBuilder.LiteralExpr(l, span)
                    }
                    match ==null {
                        monteBuilder.NounExpr("null", span)
                    }
                    match _ { arg }
                }
            def reflectedArgs := [for arg in (args.slice(0, args.size() - 1)) {
                go(arg)
            }]
            monteBuilder.MethodCallExpr(
                monteBuilder.NounExpr("astBuilder", span),
                verb, reflectedArgs.with(reflectedSpan), [], span)

# Many of the set pieces needed for auditions are expressible in Full-Monte.
# We'll recursively expand them using earlier parts of the pipeline.

def poem :DeepFrozen := m`"TBD"`
def validateAudition :DeepFrozen := m`def validateAudition() {
    if (!_auditionActive) { throw($poem) }
}`
def auditionExpr :DeepFrozen := m`object audition {
    to getFQN() :Str { validateAudition(); return fqn }
    to GetObjectExpr() :DeepFrozen { validateAudition(); return objectAST }
    to getGuard(noun :Str) { validateAudition(); return bindingGuards[noun] }
    to ask(auditor :DeepFrozen) :Bool {
        validateAudition()
        return auditor.audit(audition)
    }
}`

def defDef(noun :Str, guard :Str, rhs, span) as DeepFrozen:
    return monteBuilder.DefExpr(
        monteBuilder.FinalPattern(noun,
            monteBuilder.NounExpr(guard, span), span),
        null, rhs, span)

object holdAuditions extends monteBuilder as DeepFrozen:
    to ObjectExpr(docstring, name, asExpr, auditors, script, span):
        def FQN := "xxx$unknown"
        def objectAST := script(asAST(span))
        def wrapper := monteBuilder.HideExpr(
            monteBuilder.SeqExpr([
                expand(m`var _auditionActive := true`),
                expand(validateAudition),
                defDef("fqn", "Str", monteBuilder.LiteralExpr(FQN, span), span),
                defDef("objectAST", "DeepFrozen", objectAST, span),
                # XXX bindingGuards
                expand(auditionExpr),
                expand(m`_auditionActive := false`),
            ], span),
        span)
        return monteBuilder.SeqExpr([
            wrapper,
            monteBuilder.ObjectExpr(docstring, name, asExpr, auditors,
                                    script, span),
        ], span)
