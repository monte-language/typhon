import "lib/tubes" =~ [
    => makeUTF8EncodePump :DeepFrozen,
    => makePumpTube :DeepFrozen
]
import "lib/monte/monte_parser" =~ [=> parseModule :DeepFrozen]
import "lib/monte/monte_lexer" =~  [=> makeMonteLexer :DeepFrozen]
import "lib/uKanren" =~ [
    => iterGoal :DeepFrozen,
    => satisfiable :DeepFrozen,
    => unifyGoal :DeepFrozen,
    => callFresh :DeepFrozen,
    => allOf :DeepFrozen,
    => anyOf :DeepFrozen,
    => delay :DeepFrozen,
]
import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "unittest" =~ [=> unittest]
exports (main, makeInference)
"Type inference for Monte."

def bench(_, _) as DeepFrozen:
    null

def Expr :DeepFrozen := astBuilder.getExprGuard()
def Patt :DeepFrozen := astBuilder.getPatternGuard()

object MysteryBox as DeepFrozen:
    "An unspecified type."

def consistent(left, right) :Bool as DeepFrozen:
    "Whether the two types are consistent."

    def g := anyOf(
        # Reflexivity.
        unifyGoal(left, right),
        # All types are consistent with the mystery box.
        unifyGoal(MysteryBox, left),
        unifyGoal(MysteryBox, right),
    )
    return satisfiable(g)

def assigning(rhs, lhs) :Bool as DeepFrozen:
    "Consider whether the `rhs` can be assigned to the `lhs`."

    if (lhs == Any):
        # Top.
        return true

    if (lhs.supersetOf(rhs)):
        return true

    traceln(`Couldn't assign $rhs to $lhs`)
    return false

def reifyGuard(expr :NullOk[Expr]) as DeepFrozen:
    if (expr != null && expr.getNodeName() == "NounExpr"):
        def &&rv := safeScope.fetch(`&&${expr.getName()}`, fn {&&Any})
        return rv
    return Any


def makeInference() as DeepFrozen:
    var log := []

    def logBug(message, span):
        log with= ([message, span])

    return object inference:
        to getBugs():
            return log

        to shouldHaveMethod(specimen, verb, arity, span):
            "Check whether a type has a method."

            for meth in specimen.getMethods():
                if (meth.getVerb() == verb && meth.getArity() == arity):
                    return
            logBug(`$specimen doesn't have method $verb/$arity`, span)

        to inferPatt(specimen, patt :Patt, var context :Map):
            "Infer the type of a pattern and its specimen."

            return switch (patt.getNodeName()):
                match =="FinalPattern":
                    def noun :Str := patt.getNoun().getName()
                    def g := reifyGuard(patt.getGuard())
                    context | [noun => g]
                match =="SamePattern":
                    def [value, c] := inference.inferType(patt.getValue(),
                                                          context)
                    if (value != specimen):
                        logBug(`Same pattern type mismatch: $value vs. $specimen`,
                               patt.getSpan())
                    context
                match =="VarPattern":
                    def noun :Str := patt.getNoun().getName()
                    def g := reifyGuard(patt.getGuard())
                    context | [noun => g]
                match name:
                    traceln(`Couldn't infer anything about $name`)
                    context

        to inferType(expr :NullOk[Expr], var context :Map[Str, Any]):
            "Infer the type of an expression."

            if (expr == null):
                return [Void, context]

            return switch (expr.getNodeName()):
                match =="AugAssignExpr":
                    def [rhs, c] := inference.inferType(expr.getRvalue(), context)
                    def [lhs, _] := inference.inferType(expr.getLvalue(), context)
                    inference.shouldHaveMethod(lhs, expr.getOpName(), 1,
                                               expr.getSpan())
                    [rhs, c]
                match =="BinaryExpr":
                    def [lhs, c] := inference.inferType(expr.getLeft(), context)
                    def [rhs, c2] := inference.inferType(expr.getRight(), c)
                    inference.shouldHaveMethod(lhs, expr.getOpName(), 1,
                                               expr.getSpan())
                    # XXX don't have method rv guards yet
                    [Any, c2]
                match =="DefExpr":
                    def [rhs, c] := inference.inferType(expr.getExpr(), context)
                    context := inference.inferPatt(rhs, expr.getPattern(), c)
                    [rhs, context]
                match =="ForExpr":
                    def [iterable, c] := inference.inferType(expr.getIterable(),
                                                             context)
                    inference.shouldHaveMethod(iterable, "_makeIterator", 0,
                                               expr.getSpan())
                    # XXX key and value
                    inference.inferType(expr.getBody(), c)
                    [Void, context]
                match =="FunCallExpr":
                    def [receiver, c] := inference.inferType(expr.getReceiver(),
                                                             context)
                    # XXX punting
                    inference.shouldHaveMethod(receiver, "run",
                                               expr.getArgs().size(),
                                               expr.getSpan())
                    # XXX don't have function rv guards yet
                    [Any, context]
                match =="IfExpr":
                    def [test, c] := inference.inferType(expr.getTest(), context)
                    if (test != Bool):
                        logBug(`If expr test wasn't Bool, but $test`,
                               expr.getSpan())
                    def [cons, _] := inference.inferType(expr.getThen(), c)
                    def [alt, _] := inference.inferType(expr.getElse(), c)
                    if (cons != alt):
                        logBug(`If expr branches don't match: $cons != $alt`,
                               expr.getSpan())
                    # XXX All
                    [cons, c]
                match =="LiteralExpr":
                    switch (expr.getValue()) {
                        match _ :Bool {[Bool, context]}
                        match _ :Char {[Char, context]}
                        match _ :Double {[Double, context]}
                        match _ :Int {[Int, context]}
                        match _ :Str {[Str, context]}
                        match l {
                            logBug(`Strange literal ${M.toQuote(l)}`,
                                   expr.getSpan())
                            [Any, context]
                        }
                    }
                match =="MethodCallExpr":
                    def [receiver, c] := inference.inferType(expr.getReceiver(),
                                                             context)
                    # XXX punting
                    inference.shouldHaveMethod(receiver, expr.getVerb(),
                                               expr.getArgs().size(),
                                               expr.getSpan())
                    # XXX don't have function rv guards yet
                    [Any, context]
                match =="NounExpr":
                    def noun :Str := expr.getName()
                    def notFound():
                        logBug(`Undefined name $noun`, expr.getSpan())
                        return Any
                    [context.fetch(noun, notFound), context]
                match =="ObjectExpr":
                    def asGuard := reifyGuard(expr.getAsExpr())
                    def c := inference.inferPatt(asGuard, expr.getName(),
                                                 context)
                    # XXX methods and matchers
                    return [asGuard, c]
                match =="RangeExpr":
                    def [left, c] := inference.inferType(expr.getLeft(),
                                                         context)
                    context := c
                    def [right, c2] := inference.inferType(expr.getRight(),
                                                           context)
                    context := c2
                    if (left != right):
                        logBug(`Range expr range type varies from $left to $right`,
                               expr.getSpan())
                    # XXX hax
                    def range := switch (left) {
                        match ==Char {('0'..'1')._getAllegedInterface()}
                        match ==Int {(0..1)._getAllegedInterface()}
                        match _ {Any}
                    }
                    [range, context]
                match =="SameExpr":
                    def [left, c] := inference.inferType(expr.getLeft(),
                                                         context)
                    def [right, c2] := inference.inferType(expr.getRight(), c)
                    if (left != right):
                        logBug(`Same expr types differ: $left vs. $right`,
                               expr.getSpan())
                    # Equality checks always return Bool.
                    [Bool, c2]
                match =="SeqExpr":
                    var rv := Any
                    for subExpr in expr.getExprs():
                        def [t, c] := inference.inferType(subExpr, context)
                        rv := t
                        context := c
                    [rv, context]
                match name:
                    traceln(`Couldn't infer anything about $name`)
                    [Any, context]

def testInferLiteral(assert):
    assert.equal(makeInference().inferType(m`42`, [].asMap()),
                 [Int, [].asMap()])

unittest([
    testInferLiteral,
])

def main(=> currentProcess, => makeFileResource, => makeStdOut,
         => unsealException) as DeepFrozen:
    def path := currentProcess.getArguments().last()

    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout.flowTo(makeStdOut())
    def p := makeFileResource(path).getContents()
    return when (p) ->
        def via (UTF8.decode) s := p
        def tree := escape ej {
            def t := parseModule(makeMonteLexer(s, path), astBuilder,
                                 ej)
            if (t.getNodeName() == "Module") {t.getBody()} else {t}
        } catch parseErrorMsg {
            stdout.receive(`Syntax error in $path:$\n`)
            stdout.receive(parseErrorMsg)
            1
        }
        def inference := makeInference()
        def [type, context] := inference.inferType(tree, [].asMap())
        stdout.receive(`Inferred type: $type$\n`)
        for [problem, span] in inference.getBugs():
            stdout.receive(`Error: $span: $problem$\n`)
        0
    catch via (unsealException) [problem, _]:
        stdout.receive(`Couldn't get Monte source file: $problem$\n`)
        1
