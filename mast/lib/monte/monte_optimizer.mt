# Note that the identity "no-op" operation on ASTs is not `return ast` but
# rather `return M.call(maker, "run", args + [span])`; the transformation has
# to rebuild the AST.

def ["astBuilder" => a] | _ := import("lib/monte/monte_ast",
                                      [=> NullOk, => DeepFrozen,
                                       => __matchSame, => __bind, => Map,
                                       => __switchFailed, => Int, => Str,
                                       => Bool, => Double, => Char,
                                       => simple__quasiParser, => List,
                                       => __booleanFlow, => __validateFor,
                                       => __comparer, => __makeOrderedSpace,
                                       => __iterWhile, => __mapExtract,
                                       => bench, => __accumulateList,
                                       => __quasiMatcher, => __suchThat,
                                       => __makeVerbFacet])
def [=> term__quasiParser] := import("lib/monte/termParser",
                                     [=> NullOk, => DeepFrozen,
                                      => __matchSame, => __bind, => Map,
                                      => __switchFailed, => Int, => Str,
                                      => Bool, => Double, => Char,
                                      => simple__quasiParser, => List,
                                      => __booleanFlow, => __validateFor,
                                      => __comparer, => __makeOrderedSpace,
                                      => __iterWhile, => __mapExtract,
                                      => bench, => __accumulateList,
                                      => __quasiMatcher, => __suchThat,
                                      => __makeVerbFacet])


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


def optimize(ast, maker, args, span):
    "Transform ASTs to be more compact and efficient without changing any
     operational semantics."

    switch (ast.getNodeName()):
        match =="DefExpr":
            # m`def _ := expr` -> m`expr`
            def pattern := ast.getPattern()
            if (pattern.getNodeName() == "IgnorePattern"):
                # We don't handle the case with a guard yet.
                if (pattern.getGuard() == null):
                    return ast.getExpr().transform(optimize)

        match =="EscapeExpr":
            escape nonFinalPattern:
                def via (finalPatternToName) name exit nonFinalPattern := ast.getEjectorPattern()
                def body := ast.getBody()


                # m`escape ej {expr}` ? ej not used by expr -> m`expr`
                def scope := body.getStaticScope()
                if (!scope.namesUsed().contains(name)):
                    # We can just return the inner node directly.
                    return body.transform(optimize)

                switch (body.getNodeName()):
                    match =="MethodCallExpr":
                        # m`escape ej {ej.run(expr)}` -> m`expr`
                        def receiver := body.getReceiver()
                        if (receiver.getNodeName() == "NounExpr" &&
                            receiver.getName() == name):
                            # Looks like this escape qualifies! Let's check
                            # the catch.
                            if (ast.getCatchPattern() == null):
                                def args := body.getArgs()
                                if (args.size() == 1):
                                    return args[0].transform(optimize)

                    match =="SeqExpr":
                        # m`escape ej {ej.run(value); expr}` ->
                        # m`escape ej {ej.run(value)}`
                        var slicePoint := -1
                        for i => expr in body.getExprs():
                            if (expr.getNodeName() == "MethodCallExpr"):
                                def receiver := expr.getReceiver()
                                if (receiver.getNodeName() == "NounExpr" &&
                                    receiver.getName() == name):
                                    # The slice has to happen *after* this
                                    # expression; we want to keep the call to
                                    # the ejector.
                                    slicePoint := i + 1
                                    break
                        if (slicePoint != -1):
                            def exprs := [for n in (body.getExprs().slice(0, slicePoint))
                                          n.transform(optimize)]
                            def newSeq := sequence(exprs, body.getSpan())
                            return maker(args[0], newSeq, args[2], args[3],
                                         span).transform(optimize)

                    match _:
                        pass

        match =="IfExpr":
            escape failure:
                def cons ? (cons != null) exit failure := ast.getThen()
                def alt ? (alt != null) exit failure := ast.getElse()

                # m`if (test) {true} else {false}` -> m`test`
                if (cons.getNodeName() == "NounExpr" &&
                    cons.getName() == "true"):
                    if (alt.getNodeName() == "NounExpr" &&
                        alt.getName() == "false"):
                        return ast.getTest().transform(optimize)

                # m`if (test) {r.v(cons)} else {r.v(alt)}` ->
                # m`r.v(if (test) {cons} else {alt})`
                if (cons.getNodeName() == "MethodCallExpr" &&
                    alt.getNodeName() == "MethodCallExpr"):
                    def consReceiver := cons.getReceiver()
                    def altReceiver := alt.getReceiver()
                    if (consReceiver.getNodeName() == "NounExpr" &
                        altReceiver.getNodeName() == "NounExpr" &&
                        consReceiver.getName() == altReceiver.getName()):
                        # Doing good. Just need to check the verb and args
                        # now.
                        if (cons.getVerb() == alt.getVerb()):
                            def consArgs := cons.getArgs()
                            def altArgs := alt.getArgs()
                            if (consArgs.size() == 1 && altArgs.size() == 1):
                                return a.MethodCallExpr(consReceiver,
                                                        cons.getVerb(),
                                                        [maker(ast.getTest(),
                                                         consArgs[0],
                                                         altArgs[0],
                                                         span)],
                                                        span)

        match =="MethodCallExpr":
            def receiver := ast.getReceiver()
            def verb := ast.getVerb()
            def arguments := ast.getArgs()

            # m`__booleanFlow.failureList(0)` -> m`__makeList.run(false)`
            if (receiver.getNodeName() == "NounExpr" &&
                receiver.getName() == "__booleanFlow"):
                if (verb == "failureList" && arguments.size() == 1):
                    def node := arguments[0]
                    if (node.getNodeName() == "LiteralExpr" &&
                        node.getValue() == 0):
                        # Success!
                        return a.MethodCallExpr(a.NounExpr("__makeList",
                                                           span),
                                                "run",
                                                [a.NounExpr("false", span)],
                                                span)

            # m`x.pow(e).mod(m)` -> m`x.modPow(e, m)`
            if (verb == "mod"):
                escape badMatch:
                    def [m] exit badMatch := arguments
                    if (receiver.getNodeName() == "MethodCallExpr" &&
                        receiver.getVerb() == "pow"):
                        def [e] exit badMatch := receiver.getArgs()
                        return a.MethodCallExpr(receiver.getReceiver(),
                                                "modPow", [e, m], span)

            # m`2.add(2)` -> m`4`
            # XXX currently fails to interact correctly with ^^^ meaning that
            # some files take unreasonably long to compile.
            # if (receiver.getNodeName() == "LiteralExpr" &&
            #     allSatisfy(fn x {x.getNodeName() == "LiteralExpr"},
            #                arguments)):
            #     def receiverValue := receiver.getValue()
            #     def verb := ast.getVerb()
            #     def argValues := map(fn x {x.getValue()}, arguments)
            #     def constant := M.call(receiverValue, verb, argValues)
            #     return a.LiteralExpr(constant, span)

        match =="SeqExpr":
            # m`expr; noun; lastNoun` -> m`expr; lastNoun`
            # m`def x := 42; expr; x` -> m`expr; 42` ? x is replaced in expr
            var nameMap := [].asMap()
            var newExprs := []
            for i => var expr in args[0]:
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
                        # XXX could rewrite nouns as well, but only if the
                        # noun is known to be final! Otherwise bugs happen.
                        # For example, the lexer is known to be miscompiled.
                        # So be careful.
                        if (rhs.getNodeName() == "LiteralExpr"):
                            nameMap with= (name, rhs)
                            # If we found a simple definition, do *not* add it
                            # to the list of new expressions to emit.
                            continue
                else if (i < args[0].size() - 1):
                    if (expr.getNodeName() == "NounExpr"):
                        # Bare noun; skip it.
                        continue

                # Whatever survived to the end is clearly worthy.
                newExprs with= (expr)
            # And rebuild.
            return sequence(newExprs, span)

        match _:
            pass

    return M.call(maker, "run", args + [span])


def testModPow(assert):
    def ast := a.MethodCallExpr(a.MethodCallExpr(a.LiteralExpr(7, null), "pow",
                                                 [a.LiteralExpr(11, null)],
                                                 null),
                                "mod", [a.LiteralExpr(13, null)], null)
    def result := a.MethodCallExpr(a.LiteralExpr(7, null), "modPow",
                                   [a.LiteralExpr(11, null), a.LiteralExpr(13,
                                   null)], null)
    assert.equal(ast.transform(optimize), result)

def testRemoveUnusedBareNouns(assert):
    def ast := a.SeqExpr([a.NounExpr("x", null), a.NounExpr("y", null)], null)
    def result := a.SeqExpr([a.NounExpr("y", null)], null)
    assert.equal(ast.transform(optimize), result)

unittest([
    testModPow,
    testRemoveUnusedBareNouns,
])


["optimize" => fn ast {ast.transform(optimize)}]
