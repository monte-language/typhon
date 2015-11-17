# I don't know what this all is yet.

def a :DeepFrozen := astBuilder
def Expr :DeepFrozen := a.getExprGuard()

# Maybe Python isn't so bad after all.
object zip as DeepFrozen:
    "Transpose iterables."

    match [=="run", iterables, _]:
        def _its := [].diverge()
        for it in iterables:
            _its.push(it._makeIterator())
        def its := _its.snapshot()
        object ziperator:
            to _makeIterator():
                return ziperator
            to next(ej):
                def ks := [].diverge()
                def vs := [].diverge()
                for it in its:
                    def [k, v] := it.next(ej)
                    ks.push(k)
                    vs.push(v)
                return [ks.snapshot(), vs.snapshot()]

def sequence(exprs, span) as DeepFrozen:
    if (exprs.size() == 0):
        return a.NounExpr("null", span)
    else if (exprs.size() == 1):
        return exprs[0]
    else:
        return a.SeqExpr(exprs, span)

def finalPatternToName(pattern, ej) as DeepFrozen:
    if (pattern.getNodeName() == "FinalPattern" &&
        pattern.getGuard() == null):
        return pattern.getNoun().getName()
    ej("Not an unguarded final pattern")

def exprOrNull(expr) as DeepFrozen:
    return if (expr == null) {a.LiteralExpr("null", null)} else {expr}

def weakenPattern(var pattern, nodes) as DeepFrozen:
    "Reduce the strength of patterns based on their usage in scope."

    if (pattern.getNodeName() == "VarPattern"):
        def name :Str := pattern.getNoun().getName()
        for node in nodes:
            if (node.getStaticScope().getNamesSet().contains(name)):
                return pattern
        # traceln(`Weakening var $name`)
        pattern := a.FinalPattern(pattern.getNoun(), pattern.getGuard(),
                                  pattern.getSpan())

    if (pattern.getNodeName() == "FinalPattern"):
        def name :Str := pattern.getNoun().getName()
        for node in nodes:
            if (node.getStaticScope().namesUsed().contains(name)):
                return pattern
        # traceln(`Weakening def $name`)
        pattern := a.IgnorePattern(pattern.getGuard(), pattern.getSpan())

    return pattern

def specialize(name, value) as DeepFrozen:
    "Specialize the given name to the given AST value via substitution."

    def specializeNameToValue(ast, maker, args, span):
        switch (ast.getNodeName()):
            match =="NounExpr":
                if (args[0] == name):
                    return value

            match =="SeqExpr":
                # XXX summons zalgo :c
                def scope := ast.getStaticScope()
                if (scope.outNames().contains(name)):
                    # We're going to delve into the sequence and try to only do
                    # replacements on the elements which don't have the name
                    # defined.
                    var newExprs := []
                    var change := true
                    for i => expr in ast.getExprs():
                        if (expr.getStaticScope().outNames().contains(name)):
                            change := false
                        newExprs with= (if (change) {args[0][i]} else {expr})
                    return maker(newExprs, span)

            match _:
                # If it doesn't use the name, then there's no reason to visit
                # it and we can just continue on our way.
                def scope := ast.getStaticScope()
                if (!scope.namesUsed().contains(name)):
                    return ast

        return M.call(maker, "run", args + [span], [].asMap())

    return specializeNameToValue

def nodeUsesName(node, name :Str) as DeepFrozen:
    return node.getStaticScope().namesUsed().contains(name)

def mix(expr, => safeFinalNames :List := []) as DeepFrozen:
    "Partially evaluate a thawed Monte expression.
    
     This function recurses on its own, to avoid visiting every node."

    # traceln(`Mixing ${expr.getNodeName()}: $expr`)
    return switch (expr.getNodeName()):
        match =="CatchExpr":
            # Nothing fancy yet; just recurse.
            def body := mix(expr.getBody(), => safeFinalNames)
            def catcher := mix(expr.getCatcher(), => safeFinalNames)
            def pattern := weakenPattern(expr.getPattern(), [catcher])
            a.CatchExpr(body, pattern, catcher, expr.getSpan())

        match =="DefExpr":
            # Not worth it to weaken here. Weaken DefExprs from above instead.
            def pattern := expr.getPattern()
            def ej := expr.getExit()
            def rhs := expr.getExpr()
            def span := expr.getSpan()
            switch (pattern.getNodeName()):
                match =="IgnorePattern":
                    switch (pattern.getGuard()):
                        match ==null:
                            # m`def _ := expr` -> m`expr`
                            mix(rhs)
                        match guard:
                            # m`def _ :Guard exit ej := expr` ->
                            # m`Guard.coerce(expr, ej)`
                            a.MethodCallExpr(guard, "coerce", [mix(rhs), ej],
                                             [], span)

                # The expander shouldn't ever give us list patterns with
                # tails, but we'll filter them out here anyway.
                match =="ListPattern" ? (pattern.getTail() == null):
                    switch (rhs.getNodeName()):
                        match =="LiteralExpr":
                            # m`def [x, y] := [a, b]` ->
                            # m`def x := a; def y := b`
                            # The RHS must be a thawed literal list.
                            def value := rhs.getValue()
                            def patterns := pattern.getPatterns()
                            if (value =~ l :List ? (l.size() ==
                                                    patterns.size())):
                                def seq := [for [p, v] in (zip(patterns, l))
                                            a.DefExpr(p, ej, a.LiteralExpr(v,
                                                                           span),
                                                     span)]
                                mix(sequence(seq, span))
                            else:
                                throw(`mix/1: $expr: List pattern ` +
                                      `assignment from literal list will ` +
                                      `always fail`)

                        match =="MethodCallExpr":
                            def receiver := rhs.getReceiver()
                            if (receiver.getNodeName() == "NounExpr" &&
                                receiver.getName() == "__makeList"):
                                # m`def [name] := __makeList.run(item)` ->
                                # m`def name := item`
                                # XXX why doesn't this work for multiples? It
                                # should, right?
                                def patterns := pattern.getPatterns()
                                def l := rhs.getArgs()
                                if (l.size() == patterns.size()):
                                    def seq := [for [p, v] in (zip(patterns, l))
                                                a.DefExpr(p, ej, mix(v), span)]
                                    mix(sequence(seq, span))
                                else:
                                    throw(`mix/1: $expr: List pattern ` +
                                          `assignment from __makeList will ` +
                                          `always fail`)
                            else:
                                expr

                        match _:
                            expr

                match =="FinalPattern":
                    if (ej != null && pattern.getGuard() == null):
                        # m`def name exit ej := expr` -> m`def name := expr`
                        a.DefExpr(pattern, null, mix(rhs), span)
                    else:
                        expr

                match _:
                    expr

        match =="EscapeExpr":
            def body := expr.getBody()
            def ejPatt := weakenPattern(expr.getEjectorPattern(), [body])
            # m`escape ej {expr}` -> m`expr`
            if (ejPatt.getNodeName() == "IgnorePattern"):
                mix(body, => safeFinalNames)
            else:
                switch (body.getNodeName()):
                    match =="MethodCallExpr":
                        # m`escape ej {ej.run(expr)}` -> m`expr`
                        # But if `ej` doesn't occur in `expr`, then we instead
                        # choose the weaker optimization:
                        # m`escape ej {ej.run(expr)}` -> m`escape ej {expr}`
                        def receiver := body.getReceiver()
                        if (receiver.getNodeName() == "NounExpr" &&
                            ejPatt =~ via (finalPatternToName) name &&
                            receiver.getName() == name):
                            # Looks like this escape qualifies! Let's check
                            # the catch.
                            # XXX we can totally handle a catch, BTW; we just
                            # currently don't. Catches aren't common on
                            # ejectors, especially on the ones like __return
                            # that are most affected by this optimization.
                            if (expr.getCatchPattern() == null):
                                def args := body.getArgs()
                                if (body.getArgs() =~ [arg]):
                                    # Moment of truth. If the ejector's still
                                    # used within the expr, then rebuild and
                                    # remix. Otherwise, strip the escape
                                    # entirely.
                                    if (nodeUsesName(arg, name)):
                                        mix(expr.withBody(arg),
                                            => safeFinalNames)
                                    else:
                                        mix(arg, => safeFinalNames)
                                else:
                                    throw(`mix/1: $expr: Known ejector ` + 
                                          `called with wrong arity ${args.size()}`)
                            else:
                                expr
                        else:
                            expr

                    match =="SeqExpr":
                        # m`escape ej {before; ej.run(value); expr}` ->
                        # m`escape ej {before; ej.run(value)}`
                        var slicePoint := -1
                        def exprs := body.getExprs()

                        for i => expr in exprs:
                            switch (expr.getNodeName()):
                                match =="MethodCallExpr":
                                    def receiver := expr.getReceiver()
                                    if (receiver.getNodeName() == "NounExpr" &&
                                        ejPatt =~ via (finalPatternToName) name &&
                                        receiver.getName() == name):
                                        # The slice has to happen *after* this
                                        # expression; we want to keep the call to
                                        # the ejector.
                                        slicePoint := i + 1
                                        break
                                match _:
                                    pass

                        if (slicePoint != -1 && slicePoint < exprs.size()):
                            def slice := [for n
                                          in (exprs.slice(0, slicePoint))
                                          mix(n, => safeFinalNames)]
                            def newSeq := sequence(slice, body.getSpan())
                            # Since we must have chosen a slicePoint, we've
                            # definitely opened up new possibilities and we
                            # should recurse.
                            mix(expr.withBody(newSeq), => safeFinalNames)
                        else:
                            expr

                    match _:
                        expr

        match =="FinallyExpr":
            # Nothing fancy yet; just recurse.
            def body := mix(expr.getBody(), => safeFinalNames)
            def unwinder := mix(expr.getUnwinder(), => safeFinalNames)
            a.FinallyExpr(body, unwinder, expr.getSpan())

        match =="IfExpr":
            def test := expr.getTest()
            def cons := exprOrNull(expr.getThen())
            def alt := exprOrNull(expr.getElse())
            if (test.getNodeName() == "LiteralExpr"):
                escape wrongType:
                    def b :Bool exit wrongType := test.getValue()
                    return mix(b.pick(cons, alt))
                catch _:
                    throw(`mix/1: $expr: if-test evaluates to non-Bool $test`)
            else:
                expr

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
                                if (cons.getNamedArgs() != alt.getNamedArgs()):
                                    throw.eject(badLength, null)
                                def [consArg] exit badLength := cons.getArgs()
                                def [altArg] exit badLength := alt.getArgs()
                                var newIf := a.IfExpr(test, mix(consArg),
                                                      mix(altArg),
                                                      expr.getSpan())
                                return a.MethodCallExpr(consReceiver,
                                                        cons.getVerb(),
                                                        [mix(newIf)],
                                                        cons.getNamedArgs(),
                                                        expr.getSpan())

            # m`if (test) {x := cons} else {x := alt}` ->
            # m`x := if (test) {cons} else {alt}`
            if (cons.getNodeName() == "AssignExpr" &&
                alt.getNodeName() == "AssignExpr"):
                def consNoun := cons.getLvalue()
                def altNoun := alt.getLvalue()
                if (consNoun.getName() == altNoun.getName()):
                    var newIf := a.IfExpr(test, mix(cons.getRvalue()),
                                          mix(alt.getRvalue()),
                                          expr.getSpan())
                    return a.AssignExpr(consNoun, mix(newIf), expr.getSpan())
            expr

        match =="Matcher":
            def body := mix(expr.getBody(), => safeFinalNames)
            def pattern := weakenPattern(expr.getPattern(), [body])
            a.Matcher(pattern, body, expr.getSpan())

        match =="Method":
            def safeNames := [for patt in (expr.getPatterns())
                              if (patt =~ via (finalPatternToName) name) name]
            # traceln(`method $expr safeNames $safeNames`)
            def body := mix(expr.getBody(), "safeFinalNames" => safeNames)
            expr.withBody(body)

        match =="MethodCallExpr":
            def receiver := expr.getReceiver()
            def verb := expr.getVerb()
            def args := [for arg in (expr.getArgs()) mix(arg)]
            def namedArgs := expr.getNamedArgs()
            a.MethodCallExpr(receiver, verb, args, namedArgs, expr.getSpan())

        match =="ObjectExpr":
            def script := mix(expr.getScript())
            expr.withScript(script)

        match =="Script":
            def methods := [for m in (expr.getMethods()) mix(m)]
            def matchers := [for m in (expr.getMatchers()) mix(m)]
            a.Script(expr.getExtends(), methods, matchers, expr.getSpan())

        match =="SeqExpr":
            # traceln(`seqexpr $expr`)
            def exprs := expr.getExprs()
            # m`expr; noun; lastNoun` -> m`expr; lastNoun`
            # m`def x := 42; expr; x` -> m`expr; 42` ? x is replaced in expr
            var nameMap := [].asMap()
            var newExprs := []
            for i => var item in exprs:
                # First, rewrite. This ensures that all propagations are
                # fulfilled.
                for name => rhs in nameMap:
                    item transform= (specialize(name, rhs))

                # Now, optimize. This probably won't be too expensive and lets
                # us take advantage of the substitutions that have already
                # been performed.
                item := mix(item, => safeFinalNames)

                if (item.getNodeName() == "DefExpr"):
                    # traceln(`defexpr $item`)
                    def pattern := item.getPattern()
                    if (pattern.getNodeName() == "FinalPattern" &&
                        pattern.getGuard() == null):
                        def name := pattern.getNoun().getName()
                        def rhs := item.getExpr()
                        if (rhs.getNodeName() == "LiteralExpr"):
                            nameMap with= (name, rhs)
                            # If we found a simple definition, do *not* add it
                            # to the list of new expressions to emit.
                            continue
                        else if (rhs.getNodeName() == "NounExpr"):
                            # traceln(`item $item rhs $rhs SFN $safeFinalNames`)
                            # We need to know that this noun is final. If we
                            # don't know that, then we shouldn't be replacing
                            # it, since we could be stomping on a var noun; at
                            # least monte_lexer requires us to do due
                            # diligence here. ~ C.
                            if (safeFinalNames.contains(rhs.getName())):
                                nameMap with= (name, rhs)
                                continue
                else if (i < exprs.size() - 1):
                    if (item.getNodeName() == "NounExpr"):
                        # Bare noun; skip it.
                        continue

                # Whatever survived to the end is clearly worthy.
                newExprs with= (mix(item, => safeFinalNames))
            # And rebuild.
            sequence(newExprs, expr.getSpan())

        match _:
            # traceln(`Nothing interesting about $expr`)
            expr

def allSatisfy(pred, specimens) :Bool as DeepFrozen:
    "Return whether every specimen satisfies the predicate."
    for specimen in specimens:
        if (!pred(specimen)):
            return false
    return true

# This is the list of objects which can be thawed and will not break things
# when frozen later on. These objects must satisfy a few rules:
# * Must be uncallable and the transitive uncall must be within the types that
#   are serializable as literals. Currently:
#   * Bool, Char, Int, Str;
#   * List;
#   * broken refs;
#   * Anything in this list of objects; e.g. _booleanFlow is acceptable
# * Must have a transitive closure (under calls) obeying the above rule.
def thawable :Map[Str, DeepFrozen] := [
    # => __makeList,
    # => __makeMap,
    => _booleanFlow,
    => false,
    => null,
    => true,
]

def thaw(ast, maker, args, span) as DeepFrozen:
    "Enliven literal expressions via calls."

    escape ej:
        switch (ast.getNodeName()):
            match =="MethodCallExpr":
                def [var receiver, verb :Str, arguments, []] exit ej := args
                def receiverObj := switch (receiver.getNodeName()) {
                    match =="NounExpr" {
                        def name :Str := receiver.getName()
                        if (thawable.contains(name)) {
                            thawable[name]
                        } else {ej("Not in safe scope")}
                    }
                    match =="LiteralExpr" {receiver.getValue()}
                    match _ {ej("No matches")}
                }
                if (allSatisfy(fn x {x.getNodeName() == "LiteralExpr"},
                    arguments)):
                    def argValues := [for x in (arguments) x.getValue()]
                    # traceln(`thaw call $ast`)
                    def constant := M.call(receiverObj, verb, argValues, [].asMap())
                    return a.LiteralExpr(constant, span)

            match =="NounExpr":
                def name :Str := args[0]
                if (thawable.contains(name)):
                    # traceln(`thaw noun $name`)
                    return a.LiteralExpr(thawable[name], span)

            match _:
                pass

    return M.call(maker, "run", args + [span], [].asMap())

# def weakenAllPatterns(ast, maker, args, span) as DeepFrozen:
#     "Find and weaken all patterns."
#
#     switch (ast.getNodeName()):
#         match =="EscapeExpr":
#             def [var ejPatt, ejBody, var catchPatt, catchBody] := args
#             ejPatt := weakenPattern(ejPatt, [ejBody])
#             if (catchPatt != null):
#                 catchPatt := weakenPattern(catchPatt, [catchBody])
#
#             return maker(ejPatt, ejBody, catchPatt, catchBody, span)
#
#         match =="Matcher":
#             def [var pattern, body] := args
#             pattern := weakenPattern(pattern, [body])
#
#             return maker(pattern, body, span)
#
#         match =="Method":
#             var patterns := args[2]
#             var namedPatterns := args[3]
#             def body := args[5]
#             def candidatePatterns := patterns + namedPatterns
#             patterns := [for i => pattern in (patterns)
#                          weakenPattern(pattern,
#                                        candidatePatterns.slice(i + 1) + [body])]
#
#             var pi := patterns.size()
#             namedPatterns := [for i => pattern in (namedPatterns)
#                               weakenPattern(pattern,
#                                             candidatePatterns.slice(pi += 1) + [body])]
#             return maker(args[0], args[1], patterns, namedPatterns, args[4], body, span)
#
#         match =="SeqExpr":
#             def [var exprs] := args
#
#             # Took me a couple extra readthroughs to understand. This
#             # iteration is safe and `exprs` is altered during iteration but
#             # that doesn't change the iteration order, which is frozen once at
#             # the beginning of the loop. ~ C.
#             for i => expr in exprs:
#                 if (expr.getNodeName() == "DefExpr"):
#                     var defPatt := expr.getPattern()
#                     defPatt := weakenPattern(defPatt, exprs.slice(i + 1))
#                     def newDef := a.DefExpr(defPatt, expr.getExit(),
#                                             expr.getExpr(), expr.getSpan())
#                     exprs with= (i, newDef)
#
#             return sequence(exprs, span)
#
#         match _:
#             pass
#
#     return M.call(maker, "run", args + [span], [].asMap())

def freezeMap :Map[DeepFrozen, Str] := [for k => v in (thawable) v => k]

def freeze(ast, maker, args, span) as DeepFrozen:
    "Uncall literal expressions."

    if (ast.getNodeName() == "LiteralExpr"):
        switch (args[0]):
            match broken ? (Ref.isBroken(broken)):
                # Generate the uncall for broken refs by hand.
                return a.MethodCallExpr(a.NounExpr("Ref", span), "broken",
                                        [a.LiteralExpr(Ref.optProblem(broken),
                                                       span)], [],
                                        span)
            match ==null:
                return a.NounExpr("null", span)
            match b :Bool:
                if (b):
                    return a.NounExpr("true", span)
                else:
                    return a.NounExpr("false", span)
            match _ :Any[Char, Double, Int, Str]:
                return ast
            match l :List:
                # Generate the uncall for lists by hand.
                def newArgs := [for v in (l)
                                a.LiteralExpr(v, span).transform(freeze)]
                return a.MethodCallExpr(a.NounExpr("__makeList", span), "run",
                                        newArgs, [], span)
            match k ? (freezeMap.contains(k)):
                return a.NounExpr(freezeMap[k], span)
            match obj:
                if (obj._uncall() =~ [newMaker, newVerb, newArgs, [], _]):
                    def wrappedArgs := [for arg in (newArgs)
                                        a.LiteralExpr(arg, span)]
                    def call := a.MethodCallExpr(a.LiteralExpr(newMaker,
                                                               span),
                                                 newVerb, wrappedArgs, [], span)
                    return call.transform(freeze)
                traceln(`Warning: Couldn't freeze $obj: Bad uncall`)

    return M.call(maker, "run", args + [span], [].asMap())

def optimize(var expr) as DeepFrozen:
    # expr transform= (thaw)
    expr := mix(expr)
    # expr transform= (freeze)
    return expr

[=> optimize]
