# Note that the identity "no-op" operation on ASTs is not `return ast` but
# rather `return M.call(maker, "run", args + [span])`; the transformation has
# to rebuild the AST.

def a := import("lib/monte/monte_ast")["astBuilder"]
def [=> term__quasiParser] := import("lib/monte/termParser")


def sequence(exprs, span):
    if (exprs.size() == 0):
        return a.LiteralExpr(null, span)
    else if (exprs.size() == 1):
        return exprs[0]
    else:
        return a.SeqExpr(exprs, span)


def finalPatternToName(pattern, ej):
    if (pattern.getNodeName() == "FinalPattern" &&
        pattern.getGuard() == null):
        return pattern.getNoun().getName()
    ej("Not an unguarded final pattern")


def specialize(name, value):
    "Specialize the given name to the given AST value via substitution."

    def specializeNameToValue(ast, maker, args, span):
        if (ast.getNodeName() == "FinalPattern" ||
            ast.getNodeName() == "VarPattern"):
            def guard := ast.getGuard()
            if (guard != null):
                return maker(args[0], guard.transform(specializeNameToValue),
                             span)
            return ast

        def scope := ast.getStaticScope()
        if (!scope.namesUsed().contains(name)):
            # traceln(`$ast doesn't use $name; skipping it`)
            return ast

        if (scope.outNames().contains(name)):
            # traceln(`$ast defines $name; I shouldn't examine it`)
            if (ast.getNodeName() == "SeqExpr"):
                # We're going to delve into the sequence and try to only do
                # replacements on the elements which don't have the name
                # defined.
                # traceln(`Args: $args`)
                var newExprs := []
                var change := true
                for i => expr in ast.getExprs():
                    if (expr.getStaticScope().outNames().contains(name)):
                        # traceln(`Found the offender!`)
                        change := false
                    newExprs with= (if (change) {args[0][i]} else {expr})
                    # traceln(`New exprs: $newExprs`)
                return maker(newExprs, span)
            else:
                return ast

        if (ast.getNodeName() == "NounExpr" &&
            ast.getName() == name):
            return value
        return M.call(maker, "run", args + [span])

    return specializeNameToValue

def testSpecialize(assert):
    def ast := a.SeqExpr([
        a.NounExpr("x", null),
        a.DefExpr(a.FinalPattern(a.NounExpr("x", null), null, null), null, a.LiteralExpr(42, null), null),
        a.NounExpr("x", null)], null)
    def result := a.SeqExpr([
        a.LiteralExpr(42, null),
        a.DefExpr(a.FinalPattern(a.NounExpr("x", null), null, null), null, a.LiteralExpr(42, null), null),
        a.NounExpr("x", null)], null)
    assert.equal(ast.transform(specialize("x", a.LiteralExpr(42, null))),
                 result)

unittest([testSpecialize])


def propagateSimpleDefs(ast, maker, args, span):
    "Propagate forward simple definitions."

    if (ast.getNodeName() == "SeqExpr"):
        var nameMap := [].asMap()
        var newExprs := []
        for var expr in args[0]:
            # First, rewrite. This ensures that all propagations are
            # fulfilled.
            for name => rhs in nameMap:
                expr transform= (specialize(name, rhs))

            if (expr.getNodeName() == "DefExpr"):
                def pattern := expr.getPattern()
                if (pattern.getNodeName() == "FinalPattern" &&
                    pattern.getGuard() == null):
                    def name := pattern.getNoun().getName()
                    def rhs := expr.getExpr()
                    # XXX could rewrite nouns as well, but only if the noun is
                    # known to be final! Otherwise bugs happen. For example,
                    # the lexer is known to be miscompiled. So be careful.
                    if (rhs.getNodeName() == "LiteralExpr"):
                        nameMap with= (name, rhs)
                        # If we found a simple definition, do *not* add it to
                        # the list of new expressions to emit.
                        continue

            newExprs with= (expr)
        # And rebuild.
        return maker(newExprs, span)

    return M.call(maker, "run", args + [span])


def removeIgnoreDefs(ast, maker, args, span):
    "Remove definitions that do nothing."

    if (ast.getNodeName() == "DefExpr"):
        def pattern := ast.getPattern()
        if (pattern.getNodeName() == "IgnorePattern"):
            # We don't handle the case with a guard yet.
            if (pattern.getGuard() == null):
                return ast.getExpr().transform(removeIgnoreDefs)

    return M.call(maker, "run", args + [span])


def narrowEscapes(ast, maker, args, span):
    "Remove unreachable code in escape expressions."

    if (ast.getNodeName() == "EscapeExpr"):
        def pattern := ast.getEjectorPattern()
        escape nonFinalPattern:
            def via (finalPatternToName) name exit nonFinalPattern := pattern
            def node := ast.getBody()
            if (node.getNodeName() == "SeqExpr"):
                var slicePoint := -1
                for i => expr in node.getExprs():
                    if (expr.getNodeName() == "MethodCallExpr"):
                        def receiver := expr.getReceiver()
                        if (receiver.getNodeName() == "NounExpr" &&
                            receiver.getName() == name):
                            # The slice has to happen *after* this expression;
                            # we want to keep the call to the ejector.
                            slicePoint := i + 1
                            break
                if (slicePoint != -1):
                    def newExprs := node.getExprs().slice(0, slicePoint)
                    def newSeq := sequence(newExprs, node.getSpan())
                    return maker(args[0], newSeq, args[2], args[3], span)

    return M.call(maker, "run", args + [span])


def removeSmallEscapes(ast, maker, args, span):
    "Remove escape clauses that are definitely immediately called."

    if (ast.getNodeName() == "EscapeExpr"):
        def pattern := ast.getEjectorPattern()
        escape nonFinalPattern:
            def via (finalPatternToName) name exit nonFinalPattern := pattern
            def expr := ast.getBody()
            if (expr.getNodeName() == "MethodCallExpr"):
                def receiver := expr.getReceiver()
                if (receiver.getNodeName() == "NounExpr" &&
                    receiver.getName() == name):
                    # Looks like this escape qualifies! Let's check the catch.
                    if (ast.getCatchPattern() == null):
                        def args := expr.getArgs()
                        if (args.size() == 1):
                            return args[0]

    return M.call(maker, "run", args + [span])


def removeUnusedEscapes(ast, maker, args, span):
    "Remove unused escape clauses."

    if (ast.getNodeName() == "EscapeExpr"):
        def pattern := ast.getEjectorPattern()
        def node := ast.getBody()
        # This limitation could be lifted but only with lots of care.
        if (pattern.getNodeName() == "FinalPattern" &&
            pattern.getGuard() == null):
            def name := pattern.getNoun().getName()
            def scope := node.getStaticScope()
            if (!scope.namesUsed().contains(name)):
                # We can just return the inner node directly.
                return node.transform(removeUnusedEscapes)

    return M.call(maker, "run", args + [span])


def removeUnusedBareNouns(ast, maker, args, span):
    "Remove unused bare nouns from sequences."

    if (ast.getNodeName() == "SeqExpr" && args[0].size() > 0):
        def exprs := args[0]
        def last := exprs.last()
        def newExprs := [].diverge()
        for expr in exprs.slice(0, exprs.size() - 1):
            if (expr.getNodeName() != "NounExpr"):
                newExprs.push(expr)
        newExprs.push(last)
        return maker(newExprs.snapshot(), span)

    # No-op.
    return M.call(maker, "run", args + [span])

def testRemoveUnusedBareNouns(assert):
    def ast := a.SeqExpr([a.NounExpr("x", null), a.NounExpr("y", null)], null)
    def result := a.SeqExpr([a.NounExpr("y", null)], null)
    assert.equal(ast.transform(removeUnusedBareNouns), result)

unittest([testRemoveUnusedBareNouns])


def allSatisfy(pred, specimens) :Bool:
    "Return whether every specimen satisfies the predicate."
    for specimen in specimens:
        if (!pred(specimen)):
            return false
    return true


def map(f, xs):
    def rv := [].diverge()
    for x in xs:
        rv.push(f(x))
    return rv.snapshot()


def modPow(ast, maker, args, span):
    "Coalesce modular exponentation from two calls into one."

    escape badMatch:
        if (ast.getNodeName() == "MethodCallExpr" &&
            ast.getVerb() == "mod"):
            def [m] exit badMatch := ast.getArgs()
            def pow := ast.getReceiver()
            if (pow.getNodeName() == "MethodCallExpr" &&
                pow.getVerb() == "pow"):
                def [e] exit badMatch := pow.getArgs()
                return a.MethodCallExpr(pow.getReceiver(), "modPow", [e, m],
                                        span)

    # No-op.
    return M.call(maker, "run", args + [span])

def testModPow(assert):
    def ast := a.MethodCallExpr(a.MethodCallExpr(a.LiteralExpr(7, null), "pow",
                                                 [a.LiteralExpr(11, null)],
                                                 null),
                                "mod", [a.LiteralExpr(13, null)], null)
    def result := a.MethodCallExpr(a.LiteralExpr(7, null), "modPow",
                                   [a.LiteralExpr(11, null), a.LiteralExpr(13,
                                   null)], null)
    assert.equal(ast.transform(modPow), result)

unittest([testModPow])


def constantFoldLiterals(ast, maker, args, span):
    "Constant-fold calls to literals with literal arguments."

    if (ast.getNodeName() == "MethodCallExpr"):
        def receiver := ast.getReceiver()
        def argNodes := ast.getArgs()
        if (receiver.getNodeName() == "LiteralExpr" &&
            allSatisfy(fn x {x.getNodeName() == "LiteralExpr"}, argNodes)):
            # traceln(`Constant-folding $ast`)
            def receiverValue := receiver.getValue()
            def verb := ast.getVerb()
            def argValues := map(fn x {x.getValue()}, argNodes)
            def constant := M.call(receiverValue, verb, argValues)
            return a.LiteralExpr(constant, span)

    # No-op.
    return M.call(maker, "run", args + [span])


def optimizations := [
    narrowEscapes,
    # removeSmallEscapes :- narrowEscapes
    removeSmallEscapes,
    modPow,
    propagateSimpleDefs,
    removeIgnoreDefs,
    removeUnusedEscapes,
    removeUnusedBareNouns,
    # constantFoldLiterals :- modPow
    constantFoldLiterals,
]


def optimize(var ast):
    for optimization in optimizations:
        # traceln(`Performing optimization $optimization...`)
        ast := ast.transform(optimization)
        # traceln(`Finished with $optimization!`)
    return ast


[=> optimize]
