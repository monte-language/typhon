# Note that the identity "no-op" operation on ASTs is not `return ast` but
# rather `return M.call(maker, "run", args + [span])`; the transformation has
# to rebuild the AST.
# Also note that the AST node provided as part of the transformation is *not*
# yet transformed; the transformed node is constructed by the no-op mentioned
# above. This means that accessing properties of the AST node other than the
# type of node is gonna lead to stale data, broken dreams, and summoning
# Zalgo. Don't summon Zalgo.

def ["astBuilder" => a] | _ := import("prelude/monte_ast",
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


def flattenSeq(exprs):
    "Undo nesting of sequences."

    var rv := []
    for expr in exprs:
        switch (expr.getNodeName()):
            match =="SeqExpr":
                # Recurse. Hopefully this isn't too terribly deep.
                rv += flattenSeq(expr.getExprs())
            match _:
                rv with= (expr)
    return rv


def finalPatternToName(pattern, ej):
    if (pattern.getNodeName() == "FinalPattern" &&
        pattern.getGuard() == null):
        return pattern.getNoun().getName()
    ej("Not an unguarded final pattern")


def normalizeBody(expr, _):
    if (expr == null):
        return null
    if (expr.getNodeName() == "SeqExpr"):
        def exprs := expr.getExprs()
        if (exprs.size() == 1):
            return exprs[0]
    return expr


def specialize(name, value):
    "Specialize the given name to the given AST value via substitution."

    def specializeNameToValue(ast, maker, args, span):
        switch (ast.getNodeName()):
            match =="NounExpr":
                if (args[0] == name):
                    return value

            match =="SeqExpr":
                # XXX summons zalgo :c
                def scope := ast.getStaticScope()
                def outnames := [for n in (scope.outNames()) n.getName()]
                if (outnames.contains(name)):
                    # We're going to delve into the sequence and try to only do
                    # replacements on the elements which don't have the name
                    # defined.
                    var newExprs := []
                    var change := true
                    for i => expr in ast.getExprs():
                        def exOutNames := [for n in (expr.getStaticScope().outNames()) n.getName()]
                        if (exOutNames.contains(name)):
                            change := false
                        newExprs with= (if (change) {args[0][i]} else {expr})
                    return maker(newExprs, span)

            match _:
                # If it doesn't use the name, then there's no reason to visit
                # it and we can just continue on our way.
                def scope := ast.getStaticScope()
                def namesused := [for n in (scope.namesUsed()) n.getName()]
                if (!namesused.contains(name)):
                    return ast

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
            def pattern := args[0]
            switch (pattern.getNodeName()):
                match =="IgnorePattern":
                    def expr := args[2]
                    switch (pattern.getGuard()):
                        match ==null:
                            # m`def _ := expr` -> m`expr`
                            return expr.transform(optimize)
                        match guard:
                            # m`def _ :Guard exit ej := expr` ->
                            # m`Guard.coerce(expr, ej)`
                            def ej := args[1]
                            return a.MethodCallExpr(guard, "coerce", [expr, ej],
                                                    span)
                # The expander shouldn't ever give us list patterns with
                # tails, but we'll filter them out here anyway.
                match =="ListPattern" ? (pattern.getTail() == null):
                    def expr := args[2]
                    if (expr.getNodeName() == "MethodCallExpr"):
                        def receiver := expr.getReceiver()
                        if (receiver.getNodeName() == "NounExpr" &&
                            receiver.getName() == "__makeList"):
                            # m`def [name] := __makeList.run(item)` ->
                            # m`def name := item`
                            escape badLength:
                                def [patt] exit badLength := pattern.getPatterns()
                                def [value] exit badLength := expr.getArgs()
                                return maker(patt, args[1], value, span)
                match _:
                    pass

        match =="EscapeExpr":
            escape nonFinalPattern:
                def via (finalPatternToName) name exit nonFinalPattern := args[0]
                def body := args[1]

                # m`escape ej {expr}` ? ej not used by expr -> m`expr`
                def scope := body.getStaticScope()
                def namesused := [for n in (scope.namesUsed()) n.getName()]
                if (!namesused.contains(name)):
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
                            # XXX we can totally handle a catch, BTW; we just
                            # currently don't. Catches aren't common on
                            # ejectors, especially on the ones like __return
                            # that are most affected by this optimization.
                            if (args[2] == null):
                                def args := body.getArgs()
                                if (args.size() == 1):
                                    return args[0].transform(optimize)

                    match =="SeqExpr":
                        # m`escape ej {before; ej.run(value); expr}` ->
                        # m`escape ej {before; ej.run(value)}`
                        var slicePoint := -1
                        def flattenedExprs := flattenSeq(body.getExprs())

                        for i => expr in flattenedExprs:
                            switch (expr.getNodeName()):
                                match =="MethodCallExpr":
                                    def receiver := expr.getReceiver()
                                    if (receiver.getNodeName() == "NounExpr" &&
                                        receiver.getName() == name):
                                        # The slice has to happen *after* this
                                        # expression; we want to keep the call to
                                        # the ejector.
                                        slicePoint := i + 1
                                        break
                                match _:
                                    pass

                        if (slicePoint != -1 &&
                            slicePoint < flattenedExprs.size()):
                            def exprs := [for n
                                          in (flattenedExprs.slice(0, slicePoint))
                                          n.transform(optimize)]
                            def newSeq := sequence(exprs, body.getSpan())
                            return maker(args[0], newSeq, args[2], args[3],
                                         span).transform(optimize)

                    match _:
                        pass

        match =="IfExpr":
            escape failure:
                def via (normalizeBody) cons ? (cons != null) exit failure := args[1]
                def via (normalizeBody) alt ? (alt != null) exit failure := args[2]

                # m`if (test) {true} else {false}` -> m`test`
                if (cons.getNodeName() == "NounExpr" &&
                    cons.getName() == "true"):
                    if (alt.getNodeName() == "NounExpr" &&
                        alt.getName() == "false"):
                        return args[0].transform(optimize)

                # m`if (test) {r.v(cons)} else {r.v(alt)}` ->
                # m`r.v(if (test) {cons} else {alt})`
                if (cons.getNodeName() == "MethodCallExpr" &&
                    alt.getNodeName() == "MethodCallExpr"):
                    def consReceiver := cons.getReceiver()
                    def altReceiver := alt.getReceiver()
                    if (consReceiver.getNodeName() == "NounExpr" &&
                        altReceiver.getNodeName() == "NounExpr"):
                        if (consReceiver.getName() == altReceiver.getName()):
                            # Doing good. Just need to check the verb and args
                            # now.
                            if (cons.getVerb() == alt.getVerb()):
                                escape badLength:
                                    def [consArg] exit badLength := cons.getArgs()
                                    def [altArg] exit badLength := alt.getArgs()
                                    var newIf := maker(args[0], consArg, altArg,
                                                       span)
                                    # This has, in the past, been a
                                    # problematic recursion. It *should* be
                                    # quite safe, since the node's known to be
                                    # an IfExpr and thus the available
                                    # optimization list is short and the
                                    # recursion is (currently) well-founded.
                                    newIf transform= (optimize)
                                    return a.MethodCallExpr(consReceiver,
                                                            cons.getVerb(),
                                                            [newIf], span)

                # m`if (test) {x := cons} else {x := alt}` ->
                # m`x := if (test) {cons} else {alt}`
                if (cons.getNodeName() == "AssignExpr" &&
                    alt.getNodeName() == "AssignExpr"):
                    def consNoun := cons.getLvalue()
                    def altNoun := alt.getLvalue()
                    if (consNoun == altNoun):
                        var newIf := maker(args[0], cons.getRvalue(),
                                           alt.getRvalue(), span)
                        newIf transform= (optimize)
                        return a.AssignExpr(consNoun, newIf, span)

        match =="MethodCallExpr":
            def receiver := args[0]
            def verb := args[1]
            def arguments := args[2]

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
            if (receiver.getNodeName() == "LiteralExpr" &&
                allSatisfy(fn x {x.getNodeName() == "LiteralExpr"},
                           arguments)):
                def receiverValue := receiver.getValue()
                # Hack: Don't let .pow() get constant-folded, since it can be
                # expensive to run.
                if (verb != "pow"):
                    def argValues := map(fn x {x.getValue()}, arguments)
                    def constant := M.call(receiverValue, verb, argValues)
                    return a.LiteralExpr(constant, span)

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
    # There used to be a SeqExpr around this NounExpr, but the optimizer
    # (correctly) optimizes it away.
    def result := a.NounExpr("y", null)
    assert.equal(ast.transform(optimize), result)

unittest([
    testModPow,
    testRemoveUnusedBareNouns,
])


def fixLiterals(ast, maker, args, span):
    if (ast.getNodeName() == "LiteralExpr"):
        switch (args[0]):
            match b :Bool:
                if (b):
                    return a.NounExpr("true", span)
                else:
                    return a.NounExpr("false", span)
            match _:
                pass

    return M.call(maker, "run", args + [span])


["optimize" => fn ast {ast.transform(optimize).transform(fixLiterals)}]
