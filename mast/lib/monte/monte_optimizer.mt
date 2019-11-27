import "lib/iterators" =~ [=> zip]
exports (optimize)
# I don't know what this all is yet.

def a :DeepFrozen := astBuilder

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

def weakenPattern(sw, var pattern, nodes) as DeepFrozen:
    "Reduce the strength of patterns based on their usage in scope."

    if (pattern.getNodeName() == "VarPattern"):
        def name :Str := pattern.getNoun().getName()
        for node in (nodes):
            if (sw.nodeSetsName(node, name)):
                return pattern
        # traceln(`Weakening var $name`)
        pattern := a.FinalPattern(pattern.getNoun(), pattern.getGuard(),
                                  pattern.getSpan())

    if (pattern.getNodeName() == "FinalPattern"):
        def name :Str := pattern.getNoun().getName()
        for node in (nodes):
            if (sw.nodeUsesName(node, name)):
                return pattern
        # traceln(`Weakening def $name`)
        pattern := a.IgnorePattern(pattern.getGuard(), pattern.getSpan())

    return pattern

def specialize(name, value) as DeepFrozen:
    "Specialize the given name to the given AST value via substitution."

    def specializeNameToValue(ast, maker, args, span):
        def sw := astBuilder.makeScopeWalker()
        switch (ast.getNodeName()):
            match =="NounExpr":
                if (args[0] == name):
                    return value

            match =="SeqExpr":
                # XXX summons zalgo :c
                if (sw.nodeBindsName(ast, name)):
                    # We're going to delve into the sequence and try to only do
                    # replacements on the elements which don't have the name
                    # defined.
                    var newExprs := []
                    var change := true
                    for i => expr in (ast.getExprs()):
                        if (sw.nodeBindsName(expr, name)):
                            change := false
                        newExprs with= (if (change) {args[0][i]} else {expr})
                    return maker(newExprs, span)

            match _:
                # If it doesn't use the name, then there's no reason to visit
                # it and we can just continue on our way.
                if (!sw.nodeUsesName(ast, name)):
                    return ast

        return M.call(maker, "run", args + [span], [].asMap())

    return specializeNameToValue

object NOUN as DeepFrozen:
    "The tag for static values that are actually nouns."

def mix(expr,
        => staticValues :Map := [].asMap(),
        => safeFinalNames :List := []) as DeepFrozen:
    "Partially evaluate a thawed Monte expression.

     `staticValues` should be a mapping of names to live values. The values
     should be closed under their union with the safe scope with uncall; this
     is necessary to freeze them should the need arise.

     This function recurses on its own, to avoid visiting every node."

    def sw := astBuilder.makeScopeWalker()

    def remix(e):
        return mix(e, => staticValues, => safeFinalNames)

    def const(node, ej):
        return switch (node.getNodeName()) {
            match =="LiteralExpr" {node.getValue()}
            match =="NounExpr" {staticValues.fetch(node.getName(), ej)}
            match expr {throw.eject(ej, `Not constant: $expr`)}
        }

    # traceln(`Mixing ${expr.getNodeName()}: $expr`)
    return switch (expr.getNodeName()):
        match =="AssignExpr":
            def lhs := expr.getLvalue()
            def rhs := remix(expr.getRvalue())
            a.AssignExpr(lhs, rhs, expr.getSpan())

        match =="BindingExpr":
            def name := expr.getNoun().getName()
            def span := expr.getSpan()
            if (staticValues.contains(name)):
                # We'll synthesize a binding.
                switch (staticValues[name]):
                    match [==NOUN, redirect]:
                        # This is not quite kosher, but close enough. In the
                        # case of this kind of redirected name, it was a
                        # boring unguarded FinalPatt; I think that this is
                        # okay? ~ C.
                        a.BindingExpr(a.NounExpr(redirect, span), span)
                    match df :DeepFrozen:
                        # Whoo! It's polite to give a DF binding to those
                        # literals that qualify.
                        a.LiteralExpr(&&df, span)
                    match literal:
                        # And these literals are good too.
                        a.LiteralExpr(&&literal, span)
            else:
                expr

        match =="CatchExpr":
            # Nothing fancy yet; just recurse.
            def body := remix(expr.getBody())
            def catcher := remix(expr.getCatcher())
            def pattern := weakenPattern(sw, expr.getPattern(), [catcher])
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
                            remix(rhs)
                        match guard:
                            # m`def _ :Guard exit ej := expr` ->
                            # m`Guard.coerce(expr, ej)`
                            a.MethodCallExpr(guard, "coerce", [remix(rhs), ej],
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
                                remix(sequence(seq, span))
                            else:
                                throw(`mix/1: $expr: List pattern ` +
                                      `assignment from literal list will ` +
                                      `always fail`)

                        match =="MethodCallExpr":
                            def receiver := rhs.getReceiver()
                            if (receiver.getNodeName() == "NounExpr" &&
                                receiver.getName() == "_makeList"):
                                # m`def [name] := _makeList.run(item)` ->
                                # m`def name := item`
                                # XXX why doesn't this work for multiples? It
                                # should, right?
                                def patterns := pattern.getPatterns()
                                def l := rhs.getArgs()
                                if (l.size() == patterns.size()):
                                    def seq := [for [p, v] in (zip(patterns, l))
                                                a.DefExpr(p, ej, remix(v),
                                                          span)]
                                    remix(sequence(seq, span))
                                else:
                                    throw(`mix/1: $expr: List pattern ` +
                                          `assignment from _makeList will ` +
                                          `always fail`)
                            else:
                                expr

                        match _:
                            expr

                match =="FinalPattern":
                    if (ej != null && pattern.getGuard() == null):
                        # m`def name exit ej := expr` -> m`def name := expr`
                        a.DefExpr(pattern, null, remix(rhs), span)
                    else:
                        expr

                match _:
                    expr

        match =="EscapeExpr":
            def body := expr.getBody()
            def ejPatt := weakenPattern(sw, expr.getEjectorPattern(), [body])
            # m`escape ej {expr}` -> m`expr`
            if (ejPatt.getNodeName() == "IgnorePattern"):
                remix(body)
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
                                    if (sw.nodeUsesName(arg, name)):
                                        remix(expr.withBody(arg))
                                    else:
                                        remix(arg)
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

                        for i => expr in (exprs):
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
                                          remix(n)]
                            def newSeq := sequence(slice, body.getSpan())
                            # Since we must have chosen a slicePoint, we've
                            # definitely opened up new possibilities and we
                            # should recurse.
                            remix(expr.withBody(newSeq))
                        else:
                            expr

                    match _:
                        expr

        match =="FinallyExpr":
            # Nothing fancy yet; just recurse.
            def body := remix(expr.getBody())
            def unwinder := remix(expr.getUnwinder())
            a.FinallyExpr(body, unwinder, expr.getSpan())

        match =="HideExpr":
            # Just recursion.
            a.HideExpr(remix(expr.getBody()), expr.getSpan())

        match =="IfExpr":
            def test := remix(expr.getTest())
            def cons := exprOrNull(expr.getThen())
            def alt := exprOrNull(expr.getElse())

            # Try to constant-fold.
            if (test =~ via (const) b :Bool):
                return remix(b.pick(cons, alt))

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
                                var newIf := a.IfExpr(test, remix(consArg),
                                                      remix(altArg),
                                                      expr.getSpan())
                                return a.MethodCallExpr(consReceiver,
                                                        cons.getVerb(),
                                                        [remix(newIf)],
                                                        cons.getNamedArgs(),
                                                        expr.getSpan())

            # m`if (test) {x := cons} else {x := alt}` ->
            # m`x := if (test) {cons} else {alt}`
            if (cons.getNodeName() == "AssignExpr" &&
                alt.getNodeName() == "AssignExpr"):
                def consNoun := cons.getLvalue()
                def altNoun := alt.getLvalue()
                if (consNoun.getName() == altNoun.getName()):
                    var newIf := a.IfExpr(test, remix(cons.getRvalue()),
                                          remix(alt.getRvalue()),
                                          expr.getSpan())
                    return a.AssignExpr(consNoun, remix(newIf), expr.getSpan())
            a.IfExpr(remix(test), remix(cons),
                     if (expr.getElse() == null) {null} else {remix(alt)},
                     expr.getSpan())

        match =="Matcher":
            def body := remix(expr.getBody())
            def pattern := weakenPattern(sw, expr.getPattern(), [body])
            a.Matcher(pattern, body, expr.getSpan())

        match =="Method":
            def safeNames := [for patt in (expr.getPatterns())
                              ? (patt =~ via (finalPatternToName) name) name]
            # traceln(`method $expr safeNames $safeNames`)
            def body := mix(expr.getBody(), => staticValues,
                            "safeFinalNames" => safeNames)
            expr.withBody(body)

        match =="MethodCallExpr":
            def receiver := expr.getReceiver()
            def verb :Str := expr.getVerb()
            def args := [for arg in (expr.getArgs()) remix(arg)]
            def namedArgs := expr.getNamedArgs()
            # Trying for a constant-fold.
            escape nonConst:
                def constReceiver := const(remix(receiver), nonConst)
                def constArgs := [for arg in (args) const(arg, nonConst)]
                def constNamedArgs := [for arg in (namedArgs)
                                       const(remix(arg.getKey()), nonConst) =>
                                       const(remix(arg.getValue()), nonConst)]
                # Run the constant-folded call.
                try:
                    def rv := M.call(constReceiver, verb, constArgs, constNamedArgs)
                    # Success! Box it up.
                    a.LiteralExpr(rv, expr.getSpan())
                catch problem:
                    traceln(`mix/1: Exception while constant-folding:`)
                    traceln.exception(problem)
                    # Return a default.
                    a.MethodCallExpr(receiver, verb, args, namedArgs, expr.getSpan())
            catch _problem:
                # traceln(`mix/1: Couldn't constant-fold: $_problem`)
                a.MethodCallExpr(receiver, verb, args, namedArgs, expr.getSpan())

        match =="NounExpr":
            def name := expr.getName()
            return if (staticValues.contains(name)) {
                switch (staticValues[name]) {
                    match [==NOUN, n] {
                        # Triangular substitution.
                        # traceln(`Triangle for $name excludes $staticValues`)
                        a.NounExpr(n, expr.getSpan())
                    } match l {
                        # It's alive. It's alive! Mwahahahaha~
                        # traceln(`Propagated [$name => $l] from $staticValues`)
                        a.LiteralExpr(l, expr.getSpan())
                    }
                }
            } else {expr}

        match =="ObjectExpr":
            def script := remix(expr.getScript())
            expr.withScript(script)

        match =="Script":
            def methods := [for m in (expr.getMethods()) remix(m)]
            def matchers := [for m in (expr.getMatchers()) remix(m)]
            a.Script(expr.getExtends(), methods, matchers, expr.getSpan())

        match =="SeqExpr":
            # traceln(`seqexpr $expr`)
            def exprs := expr.getExprs()
            # m`expr; noun; lastNoun` -> m`expr; lastNoun`
            # m`def x := 42; expr; x` -> m`expr; 42` ? x is replaced in expr
            var nameMap := [].asMap()
            var newExprs := []
            for i => var item in (exprs):
                # First, rewrite. This ensures that all propagations are
                # fulfilled.
                for name => rhs in (nameMap):
                    item transform= (specialize(name, rhs))

                # Now, optimize. This probably won't be too expensive and lets
                # us take advantage of the substitutions that have already
                # been performed.
                item := remix(item)

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
                newExprs with= (remix(item))
            # And rebuild.
            sequence(newExprs, expr.getSpan())

        match _:
            # traceln(`Nothing interesting about $expr`)
            expr

def optimize(var expr) as DeepFrozen:
    return expr

    # expr transform= (thaw)
    expr := mix(expr, "staticValues" => [
        => false,
        => true,
    ])
    ## The optimizer and the AST dumper need to agree on what objects are
    ## serializable, and right now there are several things that the AST dumper
    ## doesn't know what to do with. So constant folding is disabled.

    # expr := freeze(expr)

    return expr
