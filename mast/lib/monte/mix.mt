import "unittest" =~ [=> unittest]
exports (main, mix, mixSafeScope)

# The partial evaluator.
# We specialize Monte source to Monte source using straightforward offline
# partial evaluation:
# * Binding-time analysis (BTA)
# * Expression reduction
# * Literal serialization

# Current goal: More accurate BTA
# Current goal: Polyvariant recording
# Current goal: Unfolding
# Next goal: Switch -> If
# Goal: cogen

# def Scope :DeepFrozen := Map[Str, Binding]
# def emptyScope :DeepFrozen := [].asMap()
def Ast :DeepFrozen := astBuilder.getAstGuard()
def Expr :DeepFrozen := astBuilder.getExprGuard()
def Patt :DeepFrozen := astBuilder.getPatternGuard()
def Meth :DeepFrozen := Ast["Method"]

def seq(exprs) as DeepFrozen:
    return if (exprs =~ [e]) { e } else { astBuilder.SeqExpr(exprs, null) }

def pattNames(patt :Patt) :Set[Str] as DeepFrozen:
    return switch (patt.getNodeName()) {
        match =="IgnorePattern" { [].asSet() }
        match =="BindingPattern" { [patt.getNoun().getName()].asSet() }
        match =="FinalPattern" { [patt.getNoun().getName()].asSet() }
        match =="VarPattern" { [patt.getNoun().getName()].asSet() }
        match =="ListPattern" {
            var s := [].asSet()
            for subPatt in (patt.getPatterns()) { s |= pattNames(subPatt) }
            s
        }
        match =="ViaPattern" { pattNames(patt.getPattern()) }
    }

def any(bs :List[Bool]) :Bool as DeepFrozen:
    for b in (bs):
        if (b):
            return true
    return false

object static as DeepFrozen {}
object dynamic as DeepFrozen {}

def annoSum(annos) as DeepFrozen:
    for anno in (annos):
        if (anno == dynamic):
            return dynamic
    return static

def makeAnnoStack(initialSplit :Map) as DeepFrozen:
    # The per-expression Boolean annotations. We'll be returning these.
    def exprAnnos := [].asMap().diverge()
    # The per-method reannotation kits. We'll be returning these too.
    def methodKits := [].asMap().diverge()
    # The per-scope rich annotations.
    def scopeAnnos := [].asMap().diverge()

    # Map of simple names to annotations, stacked to keep changes visible to
    # all levels.
    def scopeStack := [].diverge()
    # The local frame.
    var locals := initialSplit.diverge()

    def lookupName(name :Str):
        def rv := if (locals.contains(name)) { locals[name] } else {
            escape ej {
                for f in (scopeStack.reverse()) {
                    if (f.contains(name)) { ej(f[name]) }
                }
                var visibleNames := [for m in (scopeStack + [locals])
                                     m.getKeys()]
                throw(`lookupName($name): Name not in scopes $visibleNames`)
            }
        }
        return rv

    return object annoStack:
        to lift(name :Str, reason :Str) :Bool:
            "
            Make a static name dynamic.
            
            Returns whether it changed from static to dynamic, or was already
            dynamic.
            "

            def frame := if (locals.contains(name)) { locals } else {
                for f in (scopeStack.reverse()) {
                    if (f.contains(name)) { break f }
                }
            }
            return if (name =~ via (frame.fetch) [dynamic, oldReason]) {
                traceln(`Name $name can't be lifted for $reason because it was already lifted for $oldReason`)
                false
            } else {
                traceln(`Lifted dynamic $name for $reason`)
                frame[name] := [dynamic, reason]
                true
            }

        to annotateExpr(expr :Expr, anno):
            return exprAnnos[expr] := anno

        to annotateScope(expr :Ast, anno):
            scopeAnnos[expr] := anno

        to pushScopeFrom(expr :Ast, index :Int):
            scopeStack.push(locals)
            locals := escape ej {
                scopeAnnos.fetch(expr, ej)[index].diverge()
            } catch _ { [].asMap().diverge() }

        to popScope():
            def rv := locals.snapshot()
            locals := scopeStack.pop()
            return rv

        to popScopeOnto(expr :Ast):
            annoStack.annotateScope(expr, [annoStack.popScope()])

        to assignName(name :Str, anno):
            # Only allow assignments to override missing or static
            # annotations. Dynamic annotations cannot be undone.
            if (locals.fetch(name, fn { static }) == static):
                locals[name] := anno

        to nameIsStatic(name :Str) :Bool:
            def anno := lookupName(name)
            return anno == static

        to isNotDynamic(expr :Expr) :Bool:
            "
            Whether `expr` is not proven dynamic.

            Like .isStatic/1 but assumes that `expr` is static without
            contradictory evidence.
            "

            return exprAnnos.fetch(expr, fn { true })

        to addMethodKit(meth :Meth) :Void:
            methodKits.fetch(meth, fn {
                var newSplit := initialSplit | locals
                for frame in (scopeStack.reverse()) { newSplit |= frame }
                def methodKit() {
                    return makeAnnoStack(newSplit)
                }
                methodKits[meth] := methodKit
            })

        to getAnnos() :Pair[Map[Expr, Bool], Map[Meth, Any]]:
            return [exprAnnos.snapshot(), methodKits.snapshot()]

def staticFixpoint(staticOuters :Set[Str]) as DeepFrozen:
    # Seed the initial split.
    def outerAnnos :Map := [for name in (staticOuters) name => static]
    var annoStack := null

    def refine

    def refineAll(exprs) :Bool:
        var rv :Bool := true
        for expr in (exprs):
            rv &= refine(expr)
        return rv

    def nullOk(expr) :Bool:
        return if (expr == null) { true } else { refine(expr) }

    def annoMatcher(m, pattsAreStatic):
        annoStack.pushScopeFrom(m, 0)
        # Same rationale as methods.
        refine.matchBind(m.getPattern(), pattsAreStatic)
        def anno := refine(m.getBody())
        annoStack.popScopeOnto(m)
        return anno

    # Refine.
    var changes :Int := 1
    return bind refine:
        to annoMethod(meth :Meth, args :List[Bool]) :Bool:
            annoStack.pushScopeFrom(meth, 0)
            var anno := refine(meth.getResultGuard())
            for i => patt in (meth.getPatterns()):
                refine.matchBind(patt, args[i])
            anno &= refine(meth.getBody())
            annoStack.popScopeOnto(meth)
            return anno

        to matchBind(patt, var isStatic :Bool):
            switch (patt.getNodeName()):
                match =="IgnorePattern":
                    refine(patt.getGuard())
                match =="BindingPattern":
                    annoStack.assignName(patt.getNoun().getName(),
                                         [dynamic, "binding-patt"])
                match =="FinalPattern":
                    isStatic &= refine(patt.getGuard())
                    def anno := isStatic.pick(static,
                        [dynamic, "dynamic final-patt"])
                    annoStack.assignName(patt.getNoun().getName(), anno)
                match =="VarPattern":
                    isStatic &= refine(patt.getGuard())
                    # Whether VarPatts may be static.
                    def anno := isStatic.pick(static,
                        [dynamic, "dynamic var-patt"])
                    annoStack.assignName(patt.getNoun().getName(), anno)
                match =="ListPattern":
                    for subPatt in (patt.getPatterns()):
                        # This could be more specific. It would require doing some
                        # more aggressive value analysis.
                        refine.matchBind(subPatt, false)
                match =="ViaPattern":
                    # If the input and transformation are both static, then so is
                    # the output.
                    isStatic &= refine(patt.getExpr())
                    refine.matchBind(patt.getPattern(), isStatic)

        to run(expr) :Bool:
            if (expr == null):
                return true

            def wasStatic := annoStack.isNotDynamic(expr)
            def rv := annoStack.annotateExpr(expr, switch (expr.getNodeName()) {
                match =="LiteralExpr" { true }
                match =="BindingExpr" {
                    # BindingExprs can devirtualize VarSlots, so we consider them
                    # to be escape points. Note that this applies even when the
                    # name is already known to be static, because a reified
                    # VarSlot can be subject to further opaque redirection.
                    def name := expr.getName()
                    if (annoStack.lift(name, "Binding-expr")) { changes += 1 }
                    false
                }
                match =="NounExpr" {
                    annoStack.nameIsStatic(expr.getName())
                }
                match =="AssignExpr" {
                    var anno := refine(expr.getRvalue())
                    def target := expr.getLvalue().getName()
                    # If the RHS isn't static, then we must generalize the
                    # entire VarSlot's name, since we can no longer predict
                    # its values. If the RHS is static, the LHS might still be
                    # dynamic.
                    if (anno) {
                        anno &= annoStack.nameIsStatic(target)
                    } else if (annoStack.lift(target, "dynamic assign")) {
                        changes += 1
                    }
                    anno
                }
                match =="DefExpr" {
                    def rhs := expr.getExpr()
                    var anno := refine(rhs)
                    anno &= refine(expr.getExit())
                    # Look for `match ==value`.
                    # if (rhs != null && rhs.getNodeName() == "NounExpr" &&
                    #     # XXX mpatt`` someday
                    #     expr =~ m`def via (_matchSame.run(@val)) _ exit @_ := @_`) {
                    #     def name := rhs.getName()
                    #     observe(name, val)
                    # }
                    def patt := expr.getPattern()
                    # If the pattern's names aren't static, then we cannot let
                    # their definition be residualized, so it must be dynamic.
                    refine.matchBind(patt, anno)
                    for name in (pattNames(patt)) {
                        anno &= annoStack.nameIsStatic(name)
                    }
                    anno
                }
                match =="HideExpr" {
                    annoStack.pushScopeFrom(expr, 0)
                    var anno := refine(expr.getBody())
                    annoStack.popScopeOnto(expr)
                    anno
                }
                match =="MethodCallExpr" {
                    var anno := refine(expr.getReceiver())
                    anno &= refineAll(expr.getArgs())
                    anno & refineAll(expr.getNamedArgs())
                }
                match =="EscapeExpr" {
                    # Static ejector bodies imply static ejector names. Dynamic
                    # ejector names imply dynamic ejector bodies. We try here to
                    # err on the side of static names.
                    def shouldBeStatic := annoStack.isNotDynamic(expr)
                    annoStack.pushScopeFrom(expr, 0)
                    def ejPatt := expr.getEjectorPattern()
                    refine.matchBind(ejPatt, shouldBeStatic)
                    var anno := refine(expr.getBody())
                    def ejScope := annoStack.popScope()
                    annoStack.pushScopeFrom(expr, 1)
                    def catchPatt := expr.getCatchPattern()
                    if (catchPatt != null) {
                        refine.matchBind(catchPatt, shouldBeStatic)
                        anno &= refine(expr.getCatchBody())
                    }
                    def catchScope := annoStack.popScope()
                    annoStack.annotateScope(expr, [ejScope, catchScope])
                    anno
                }
                match =="FinallyExpr" {
                    annoStack.pushScopeFrom(expr, 0)
                    var anno := refine(expr.getBody())
                    def bodyScope := annoStack.popScope()
                    annoStack.pushScopeFrom(expr, 1)
                    anno &= refine(expr.getUnwinder())
                    def unwinderScope := annoStack.popScope()
                    annoStack.annotateScope(expr, [bodyScope, unwinderScope])
                    anno
                }
                match =="IfExpr" {
                    # A single IfExpr technically has three scopes, with the two
                    # branch scopes being nested within the test scope.
                    annoStack.pushScopeFrom(expr, 0)
                    var anno := refine(expr.getTest())
                    annoStack.pushScopeFrom(expr, 1)
                    anno &= refine(expr.getThen())
                    def thenScope := annoStack.popScope()
                    annoStack.pushScopeFrom(expr, 2)
                    anno &= refine(expr.getElse())
                    def elseScope := annoStack.popScope()
                    def testScope := annoStack.popScope()
                    annoStack.annotateScope(expr,
                                            [testScope, thenScope, elseScope])
                    anno
                }
                match =="SeqExpr" { refineAll(expr.getExprs()) }
                match =="CatchExpr" {
                    annoStack.pushScopeFrom(expr, 0)
                    def bodyScope := annoStack.popScope()
                    var anno := refine(expr.getBody())
                    annoStack.pushScopeFrom(expr, 1)
                    def catcher := expr.getCatcher()
                    # Whether exceptions can be static in the catcher.
                    refine.matchBind(expr.getPattern(), annoStack.isNotDynamic(catcher))
                    anno &= refine(expr.getCatcher())
                    def catcherScope := annoStack.popScope()
                    annoStack.annotateScope(expr, [bodyScope, catcherScope])
                    anno
                }
                match =="ObjectExpr" {
                    def shouldBeStatic := annoStack.isNotDynamic(expr)
                    def patt := expr.getName()
                    refine.matchBind(patt, shouldBeStatic)
                    var anno := (refine(expr.getAsExpr()) &
                                 refineAll(expr.getAuditors()))
                    # Annotate the script pieces. In order to be unfoldable, we
                    # must have only static scripts.
                    def script := expr.getScript()
                    # Even a static method will have dynamic inputs when
                    # evaluated, so we must specialize as if that were the
                    # case. On the other hand, an object can still be static
                    # even if its method outputs are dynamic.
                    for m in (script.getMethods()) {
                        refine.annoMethod(m, [false] * m.getPatterns().size())
                    }
                    for m in (script.getMatchers()) {
                        annoMatcher(m, false)
                    }
                    if (!anno) {
                        # Compute the escaping names.
                        def namesUsed := script.getStaticScope().namesUsed()
                        def freeNames := (namesUsed - pattNames(patt) -
                                          staticOuters).diverge()
                        if (!freeNames.isEmpty()) {
                            for name in (freeNames) {
                                if (annoStack.lift(name,
                                    "in closure of dynamic object")) { changes += 1 }
                            }
                        }
                    }
                    # Whether this object will be static.
                    refine.matchBind(patt, anno)
                    anno
                }
            })
            # If we were static, but are no longer static, then that's a
            # change too.
            if (wasStatic &! rv):
                changes += 1
            return rv

        to annotate(topExpr :Expr) :Pair[Map[Expr, Bool], Map[Meth, Any]]:
            "
            Compute the least-dynamic fixpoint of `topExpr` relative to its
            `staticOuters`.
            "

            # Seed the initial split.
            def freeNames := (topExpr.getStaticScope().namesUsed() -
                              staticOuters)
            def innerAnnos := [for name in (freeNames)
                                name => [dynamic, "free in top scope"]]

            # Set up the annotation stack.
            annoStack := makeAnnoStack(outerAnnos | innerAnnos)

            # Compute the initial split.
            refine(topExpr)
            changes := 1

            # Refine until there's nothing left.
            while (changes > 0):
                changes := 0
                refine(topExpr)
                traceln(`Changes: $changes`)

            # And that's it.
            return annoStack.getAnnos()

        to annotateMethod(meth :Meth, args :List[Bool]) :Pair[Map[Expr, Bool], Map[Meth, Any]]:
            # Seed the initial split.
            def freeNames := (meth.getStaticScope().namesUsed() -
                              staticOuters)
            def innerAnnos := [for name in (freeNames)
                                name => [dynamic, "free in top scope"]]

            annoStack := makeAnnoStack(outerAnnos | innerAnnos)

            changes := 1
            while (changes > 0):
                changes := 0
                refine.annoMethod(meth, args)

            return annoStack.getAnnos()

def isLiteral(expr :Expr) :Bool as DeepFrozen:
    return switch (expr.getNodeName()) {
        match =="LiteralExpr" { true }
        match =="NamedArg" {
            isLiteral(expr.getKey()) && isLiteral(expr.getValue())
        }
        match _ { false }
    }

def allLiteral(exprs :List[Expr]) :Bool as DeepFrozen:
    for expr in (exprs):
        if (!isLiteral(expr)):
            return false
    return true

interface Static :DeepFrozen {}

def makeStaticObject(makeReducer, _methodKits, evalScope, objExpr) as DeepFrozen:
    def script := objExpr.getScript()
    def methods := [for m in (script.getMethods())
                    [m.getVerb(), m.getPatterns().size()] => m]

    def unfold(meth, args, namedArgs):
        # def kit := methodKits[meth]()
        def fixpoint := staticFixpoint(evalScope.getKeys().asSet())
        def [annos, kits] := fixpoint.annotateMethod(meth,
                                                     [true] * args.size())
        def reducer := makeReducer(annos, kits, evalScope)
        return reducer.withScope(fn {
            traceln(`unfold($meth, $args, $namedArgs)`)
            for i => patt in (meth.getPatterns()) {
                reducer.matchBind(patt, args[i])
            }
            for namedPatt in (meth.getNamedPatterns()) {
                # XXX
                namedPatt
                namedArgs
            }
            def body := reducer(meth.getBody())
            def resultGuard := reducer(meth.getResultGuard())
            if (resultGuard == null) { body } else {
                def n := astBuilder.LiteralExpr(null, null)
                reducer.call(resultGuard, "coerce", [body, n])
            }
        })

    return object staticObject as Static:
        # XXX we need to actually unfold these methods so that they are fully
        # reannotated.
        to _sealedDispatch(brand):
            return if (brand == Static):
                def reducedScript := {
                    # Since we are residualizing, we need to optimize
                    # under our method/matcher bindings now instead of
                    # later.
                    def fixpoint := staticFixpoint(evalScope.getKeys().asSet())
                    def [annos, kits] := fixpoint.annotate(objExpr)
                    def reducer := makeReducer(annos, kits, evalScope)
                    def methods := [for m in (script.getMethods()) {
                        reducer.withScope(fn {
                            # XXX lazy
                            def body := reducer(m.getBody())
                            def resultGuard := reducer(m.getResultGuard())
                            astBuilder."Method"(m.getDocstring(),
                                                m.getVerb(),
                                                m.getPatterns(),
                                                m.getNamedPatterns(),
                                                resultGuard, body,
                                                null)
                        })
                    }]
                    # XXX lazy
                    def matchers := [for m in (script.getMatchers()) m]
                    astBuilder.Script(null, methods, matchers, null)
                }
                object staticTool:
                    to run():
                        def ss := reducedScript.getStaticScope()
                        def body := seq([for name in (ss.namesUsed())
                                         ? (!safeScope.contains(`&&$name`)) {
                            def patt := astBuilder.FinalPattern(
                                astBuilder.NounExpr(name, null), null, null)
                            def rhs := astBuilder.LiteralExpr(
                                evalScope[name].get().get(), null)
                            m`def $patt := $rhs`
                        }] + [
                        astBuilder.ObjectExpr(
                            objExpr.getDocstring(), objExpr.getName(),
                            objExpr.getAsExpr(), objExpr.getAuditors(),
                            reducedScript, null)
                        ])
                        return astBuilder.HideExpr(body, null)

        match [verb, args, namedArgs]:
            def m := methods[[verb, args.size()]]
            unfold(m, args, namedArgs).getValue()

def pretty(topExpr, exprAnnos :Map[Expr, Bool]) :Str as DeepFrozen:
    def pieces := [].diverge()
    var indent :Int := 0
    def annoStack := [].diverge()

    def push(var piece :Str):
        if (annoStack.last()):
            def l := [].diverge()
            for c in (piece):
                if (!" \n".contains(c)):
                    l.push('̲')
                l.push(c)
            piece := _makeStr.fromChars(l.snapshot())
        pieces.push(piece)

    def nl():
        push("\n" + " " * indent)

    def openBrace():
        indent += 4
        push(" {")
        nl()

    def closeBrace():
        indent -= 4
        nl()
        push("}")
        nl()

    def go

    def guard(expr):
        if (expr != null):
            push(" :")
            go(expr)

    def p(patt :Patt):
        switch (patt.getNodeName()):
            match =="IgnorePattern":
                push("_")
                guard(patt.getGuard())
            match =="FinalPattern":
                go(patt.getNoun())
                guard(patt.getGuard())
            match =="VarPattern":
                push("var ")
                go(patt.getNoun())
                guard(patt.getGuard())
            match =="BindingPattern":
                push("&&")
                go(patt.getNoun())
            match =="ListPattern":
                push("[")
                if (patt.getPatterns() =~ [head] + patts):
                    p(head)
                    for subPatt in (patts):
                        push(", ")
                        p(subPatt)
                push("]")
            match =="ViaPattern":
                push("via (")
                go(patt.getExpr())
                push(") ")
                p(patt.getPattern())

    bind go(expr :NullOk[Expr]):
        if (expr == null):
            push("null")
            return

        annoStack.push(exprAnnos.fetch(expr, &false.get))
        switch (expr.getNodeName()):
            match =="LiteralExpr":
                push(M.toQuote(expr.getValue()))
            match =="BindingExpr":
                push("&&")
                push(expr.getName())
            match =="NounExpr":
                push(expr.getName())
            match =="AssignExpr":
                go(expr.getLvalue())
                push(" := ")
                go(expr.getRvalue())
            match =="DefExpr":
                push("def ")
                p(expr.getPattern())
                def ex := expr.getExit()
                if (ex != null):
                    push(" exit ")
                    go(ex)
                push(" := ")
                go(expr.getExpr())
            match =="HideExpr":
                openBrace()
                go(expr.getBody())
                closeBrace()
            match =="MethodCallExpr":
                go(expr.getReceiver())
                push(".")
                push(expr.getVerb())
                push("(")
                if (expr.getArgs() =~ [head] + args):
                    go(head)
                    for arg in (args):
                        push(", ")
                        go(arg)
                push(")")
            match =="EscapeExpr":
                push("escape ")
                p(expr.getEjectorPattern())
                openBrace()
                go(expr.getBody())
                closeBrace()
                def catchPatt := expr.getCatchPattern()
                if (catchPatt != null):
                    push(" catch ")
                    p(catchPatt)
                    openBrace()
                    go(expr.getCatchBody())
                    closeBrace()
            match =="FinallyExpr":
                push("try ")
                openBrace()
                go(expr.getBody())
                closeBrace()
                push(" finally ")
                openBrace()
                go(expr.getUnwinder())
                closeBrace()
            match =="IfExpr":
                push("if (")
                go(expr.getTest())
                push(")")
                openBrace()
                go(expr.getThen())
                closeBrace()
                push(" else ")
                openBrace()
                go(expr.getElse())
                closeBrace()
            match =="SeqExpr":
                if (expr.getExprs() =~ [head] + exprs):
                    go(head)
                    for subExpr in (exprs):
                        nl()
                        go(subExpr)
            match =="CatchExpr":
                push("try ")
                openBrace()
                go(expr.getBody())
                closeBrace()
                push(" catch ")
                p(expr.getPattern())
                openBrace()
                go(expr.getCatcher())
                closeBrace()
            match =="ObjectExpr":
                push("object ")
                p(expr.getName())
                openBrace()
                def script := expr.getScript()
                for m in (script.getMethods()):
                    push("method ")
                    push(m.getVerb())
                    push("(")
                    if (m.getPatterns() =~ [head] + patts):
                        p(head)
                        for patt in (patts):
                            push(", ")
                            p(patt)
                    push(")")
                    guard(m.getResultGuard())
                    openBrace()
                    go(m.getBody())
                    closeBrace()
                closeBrace()
        annoStack.pop()

    go(topExpr)

    return "".join(pieces)

def makeReducer(exprAnnos :Map[Expr, Bool], methodKits :Map[Meth, Any],
                topValueScope) as DeepFrozen:
    # Exception reification. When an exception is thrown, we copy it into the
    # exception box, and this allows us to not need `unsealException`.
    object noException as DeepFrozen {}
    var exceptionBox := noException
    object throwStatic:
        to run(ex):
            traceln(`throw($ex)`)
            exceptionBox := ex
            throw(ex)
        to eject(ej, ex):
            traceln(`throw.eject($ej, $ex)`)
            exceptionBox := ex
            throw.eject(ej, ex)
    def staticScope := [
        "throw" => &&throwStatic,
    ]

    def valueStack := [staticScope | topValueScope].diverge()
    var locals := [].asMap().diverge()

    def pushScope():
        valueStack.push(locals.snapshot())
        locals := [].asMap().diverge()

    def popScope():
        locals := valueStack.pop().diverge()

    def freezeScope():
        var values := locals.snapshot()
        for s in (valueStack.reverse()):
            values |= s
        return values

    def addName(name, value):
        # traceln(`addName($name, $value)`)
        locals[name] := value
        # traceln("local keys", locals.getKeys())

    def movable(ex):
        return (ex == null || isLiteral(ex) ||
                ["BindingExpr", "NounExpr"].contains(ex.getNodeName()))

    def maybeValue(expr):
        return if (expr == null) { null } else { expr.getValue() }

    def makeLit(value):
        return astBuilder.LiteralExpr(value, null)

    return object reducer:
        to lookupValue(name :Str):
            if (locals.contains(name)):
                return locals[name]
            for scope in (valueStack.reverse()):
                return scope.fetch(name, __continue)
            def stackDump := [for frame in (valueStack + [locals]) frame.getKeys()]
            throw(`Unassigned name $name, searched $stackDump`)

        to withScope(thunk):
            pushScope()
            def rv := thunk()
            popScope()
            return rv

        to runGuard(guardExpr, specimen, ej):
            def guard := maybeValue(reducer(guardExpr))
            return if (guard == null) { specimen } else {
                guard.coerce(specimen, ej)
            }

        to matchBind(patt, specimen, => ej := null):
            # traceln(`reducer.matchBind($patt, $specimen, $ej)`)
            switch (patt.getNodeName()):
                match =="IgnorePattern":
                    reducer.runGuard(patt.getGuard(), specimen, ej)
                match =="BindingPattern":
                    def prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    addName(patt.getNoun().getName(), prize)
                match =="FinalPattern":
                    def prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    # traceln("matchBind final", patt, prize)
                    addName(patt.getNoun().getName(), &&prize)
                match =="VarPattern":
                    var prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    # traceln("matchBind var", patt, prize)
                    addName(patt.getNoun().getName(), &&prize)
                match =="ListPattern":
                    def patts := patt.getPatterns()
                    def l :List ? (l.size() == patts.size()) exit ej := specimen
                    for i => subPatt in (patts):
                        reducer.matchBind(subPatt, l[i], => ej)
                match =="ViaPattern":
                    def transformer := reducer(patt.getExpr()).getValue()
                    def prize := transformer(specimen, ej)
                    reducer.matchBind(patt.getPattern(), prize, => ej)

        to call(receiver :Expr, verb :Str, args :List[Expr],
                namedArgs :List[Expr], => isStatic := false):
            # XXX we could unfold maybe
            # if (r =~ static :Static) {
            #     def rv := static.unfold(verb, a, na)
            #     traceln(`unfold($verb, $a, $na) -> $rv`)
            #     rv
            # } else {
            return if (isLiteral(receiver) && allLiteral(args)):
                def r := receiver.getValue()
                def a := [for arg in (args) arg.getValue()]
                def na := [for namedArg in (namedArgs)
                           namedArg.getKey().getValue() =>
                           namedArg.getValue().getValue()]
                try:
                    def rv := M.call(r, verb, a, na)
                    traceln(`M.call($r, $verb, $a, $na) -> result $rv`)
                    makeLit(rv)
                catch problem:
                    if (exceptionBox != noException):
                        traceln(`M.call($r, $verb, $a, $na) -> problem $exceptionBox`)
                        # Static throw.
                        def lit := makeLit(exceptionBox)
                        m`throw($lit)`
                    else:
                        # Reraise.
                        throw(problem)
                finally:
                    # Clear the box for next time.
                    exceptionBox := noException
            else:
                if (isStatic):
                    throw(`reducer.call/4: Call should have been static but was dynamic instead`)
                astBuilder.MethodCallExpr(receiver, verb, args, namedArgs,
                                          null)

        to run(expr :NullOk[Ast]):
            if (expr == null):
                return null

            # Is this expression annotated static?
            def isStatic :Bool := exprAnnos[expr]

            # traceln(`reducer(${expr.getNodeName()}) isStatic $isStatic`)

            return switch (expr.getNodeName()) {
                match =="LiteralExpr" { expr }
                match =="BindingExpr" {
                    if (isStatic) {
                        def name := expr.getNoun().getName()
                        def binding := reducer.lookupValue(name)
                        traceln(`Static binding: &&$name := $binding`)
                        makeLit(binding)
                    } else { expr }
                }
                match =="NounExpr" {
                    if (isStatic) {
                        def name := expr.getName()
                        def noun := reducer.lookupValue(name).get().get()
                        traceln(`Static noun: &&$name := $noun`)
                        makeLit(noun)
                    } else { expr }
                }
                match =="AssignExpr" {
                    def rhs := reducer(expr.getRvalue())
                    def lhs := expr.getLvalue()
                    if (isStatic) {
                        def target := lhs.getName()
                        def binding := reducer.lookupValue(target)
                        def value := rhs.getValue()
                        traceln(`Static assign: $target := $value`)
                        binding.get().put(value)
                        rhs
                    } else { astBuilder.AssignExpr(lhs, rhs, null) }
                }
                match =="DefExpr" {
                    var patt := expr.getPattern()
                    def ex := reducer(expr.getExit())
                    var rhs := reducer(expr.getExpr())
                    if (isStatic) {
                        traceln(`Static def: def $patt exit $ex := $rhs`)
                        reducer.matchBind(patt, rhs.getValue(),
                                          "ej" => maybeValue(ex))
                        # And the return value of a DefExpr is the RHS.
                        rhs
                    } else { astBuilder.DefExpr(patt, ex, rhs, null) }
                }
                match =="HideExpr" {
                    reducer.withScope(fn { reducer(expr.getBody()) })
                }
                match =="MethodCallExpr" {
                    def receiver := reducer(expr.getReceiver())
                    def verb := expr.getVerb()
                    def args := [for arg in (expr.getArgs()) reducer(arg)]
                    def namedArgs := [for namedArg in (expr.getNamedArgs())
                                      reducer(namedArg)]
                    # And now we leave the rest to the subroutine.
                    def result := reducer.call(receiver, verb, args,
                                               namedArgs, => isStatic)
                }
                match =="EscapeExpr" {
                    def ejPatt := expr.getEjectorPattern()
                    def catchPatt := expr.getCatchPattern()
                    if (isStatic) {
                        # We create a live ejector here.
                        escape ej {
                            # traceln("Entering ejector", ej)
                            def body := expr.getBody()
                            def rv := reducer.withScope(fn {
                                addName(ejPatt.getNoun().getName(), &&ej)
                                reducer(body)
                            })
                            # traceln("Didn't use ejector", ej)
                            rv
                        } catch val {
                            # traceln("Ejector gave value", val)
                            if (catchPatt == null) {
                                makeLit(val)
                            } else {
                                def catchBody := expr.getCatchBody()
                                reducer.withScope(fn {
                                    addName(catchPatt.getNoun().getName(), &&val)
                                    reducer(catchBody)
                                })
                            }
                        }
                    } else {
                        # We perform ejector analysis here. Note that we only
                        # perform ejector analysis on dynamic escape-exprs.
                        # This is because static escape-exprs already
                        # effectively compute this correctly every time and do
                        # not benefit from our analysis here, which is
                        # necessarily a conservative heuristic.

                        def fullFallback() {
                            # Full fallback.
                            def ejBody := reducer.withScope(fn {
                                reducer(expr.getBody())
                            })
                            def catchBody := reducer.withScope(fn {
                                reducer(expr.getCatchBody())
                            })
                            return astBuilder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody,
                                                         null)
                        }

                        # Our analysis aims to remove ejectors which
                        # can never fire and ejectors which are known to fire
                        # exactly once.
                        switch (ejPatt.getNodeName()) {
                            match =="IgnorePattern" {
                                # Ejector is never bound.
                                astBuilder.HideExpr(reducer.withScope(fn {
                                    reducer(expr.getBody())
                                }), null)
                            }
                            match =="FinalPattern" {
                                def noun := ejPatt.getNoun()
                                def name := noun.getName()
                                def body := expr.getBody()
                                if (body.getStaticScope().namesUsed().contains(name)) {
                                    # Let's see if we can track down that usage.
                                    switch (body.getNodeName()) {
                                        # As with the cases of yesteryear, the case with catches
                                        # isn't here yet.
                                        match =="SeqExpr" ? (expr.getCatchPattern() == null) {
                                            def exprs := body.getExprs()
                                            # Search for the first spot where we definitely call
                                            # the ejector. Trim away everything afterward.
                                            def trimmed := {
                                                def split := for i => ex in (exprs) {
                                                    if (ex =~ m`$noun.run(@inner)`) {
                                                        break [i, inner]
                                                    }
                                                }
                                                if (split =~ [i, inner]) {
                                                    exprs.slice(0, i).with(inner)
                                                } else { exprs }
                                            }
                                            def newBody := seq(trimmed)
                                            # If the new body doesn't use the ejector, then we'll
                                            # discard the ejector altogether.
                                            if (newBody.getStaticScope().namesUsed().contains(name)) {
                                                astBuilder.EscapeExpr(ejPatt, newBody, null, null,
                                                                      null)
                                            } else { newBody }
                                        }
                                        match _ { fullFallback() }
                                    }
                                } else {
                                    # Zero uses, so we can remove all of it.
                                    astBuilder.HideExpr(reducer.withScope(fn {
                                        reducer(body)
                                    }), null)
                                }
                            }
                            match _ { fullFallback() }
                        }
                    }
                }
                match =="FinallyExpr" {
                    if (isStatic) {
                        try {
                            reducer.withScope(fn { reducer(expr.getBody()) })
                        } finally {
                            reducer.withScope(fn { reducer(expr.getUnwinder()) })
                        }
                    } else {
                        def body := reducer.withScope(fn {
                            reducer(expr.getBody())
                        })
                        def unwinder := reducer.withScope(fn {
                            reducer(expr.getUnwinder())
                        })
                        astBuilder.FinallyExpr(body, unwinder, null)
                    }
                }
                match =="IfExpr" {
                    # It is crucial for pruning that we only recurse into a branch if
                    # we need to generate its code; otherwise, we must avoid dead
                    # branches.
                    def oldTest := expr.getTest()
                    reducer.withScope(fn {
                        def test := reducer(oldTest)
                        if (isStatic) {
                            # traceln("if is static", expr)
                            if (test.getValue()) {
                                reducer.withScope(fn {
                                    reducer(expr.getThen())
                                })
                            } else {
                                reducer.withScope(fn {
                                    reducer(expr.getElse())
                                })
                            }
                        } else {
                            def alt := reducer.withScope(fn {
                                reducer(expr.getThen())
                            })
                            def cons := reducer.withScope(fn {
                                reducer(expr.getElse())
                            })
                            astBuilder.IfExpr(test, alt, cons, null)
                        }
                    })
                }
                match =="SeqExpr" {
                    if (isStatic) {
                        var rv := null
                        for i => subExpr in (expr.getExprs()) {
                            rv := reducer(subExpr)
                        }
                        rv
                    } else {
                        def exprs := expr.getExprs()
                        def init := exprs.slice(0, exprs.size() - 1)
                        def last := exprs.last()
                        def rv := [].diverge()
                        for subExpr in (init) {
                            def reduced := reducer(subExpr)
                            # If the reduced result is non-side-effecting,
                            # drop it.
                            def trivialExprs := ["BindingExpr", "LiteralExpr", "NounExpr"]
                            if (!trivialExprs.contains(reduced.getNodeName())) {
                                rv.push(reduced)
                            }
                        }
                        # Don't drop the last expr, regardless of what it is.
                        rv.push(reducer(last))
                        seq(rv.snapshot())
                    }
                }
                match =="CatchExpr" {
                    throw(`We don't handle catch yet!`)
                    expr
                }
                match =="ObjectExpr" {
                    def asExpr := reducer(expr.getAsExpr())
                    def auditors := [for a in (expr.getAuditors()) reducer(a)]
                    def patt := expr.getName()
                    if (isStatic) {
                        def evalScope := freezeScope()
                        # NB: The script must be reduced at unfold time, *not*
                        # at bind time. This is because the script's execution
                        # is actually suspended at bind time and it only runs
                        # during each unfold. Since we reduce in the order of
                        # operations, we must suspend here.
                        def obj := makeStaticObject(makeReducer, methodKits,
                                                    evalScope, expr)
                        traceln(`Virtualizing static object: $patt`)
                        # traceln(`Scope: $evalScope`)
                        reducer.matchBind(patt, obj)
                        makeLit(obj)
                    } else {
                        def script := {
                            # Since we are residualizing, we need to optimize
                            # under our method/matcher bindings now instead of
                            # later.
                            def s := expr.getScript()
                            def methods := [for m in (s.getMethods()) {
                                reducer.withScope(fn {
                                    # XXX lazy
                                    def body := reducer(m.getBody())
                                    def resultGuard := reducer(m.getResultGuard())
                                    astBuilder."Method"(m.getDocstring(),
                                                        m.getVerb(),
                                                        m.getPatterns(),
                                                        m.getNamedPatterns(),
                                                        resultGuard, body,
                                                        null)
                                })
                            }]
                            # XXX lazy
                            def matchers := [for m in (s.getMatchers()) m]
                            astBuilder.Script(null, methods, matchers, null)
                        }
                        astBuilder.ObjectExpr(expr.getDocstring(), patt, asExpr,
                                              auditors, script, null)
                    }
                }
            }

def freezeMap :DeepFrozen := [for `&&@k` => v in (safeScope) v.get().get() => k]

def uncallLiterals(node, maker, args, span) as DeepFrozen:
    "Turn any illegal literals into legal literals."

    return if (node.getNodeName() == "LiteralExpr") {
        switch (args[0]) {
            match obj :Static {
                obj._sealedDispatch(Static)().transform(uncallLiterals)
            }
            match broken ? (Ref.isBroken(broken)) {
                # Generate the uncall for broken refs by hand.
                def problem := astBuilder.LiteralExpr(Ref.optProblem(broken),
                                                      span)
                m`Ref.broken($problem)`
            }
            match ==null { m`null` }
            match b :Bool { b.pick(m`true`, m`false`) }
            match _ :Any[Char, Double, Int, Str] { node }
            match l :List {
                # Generate the uncall for lists by hand.
                def newArgs := [for v in (l)
                                astBuilder.LiteralExpr(v,
                                span).transform(uncallLiterals)]
                astBuilder.MethodCallExpr(m`_makeList`, "run", newArgs, [], span)
            }
            match k ? (freezeMap.contains(k)) {
                # traceln(`Found $k in freezeMap`)
                return astBuilder.NounExpr(freezeMap[k], span)
            }
            match obj {
                if (obj._uncall() =~ [newMaker, newVerb, newArgs,
                                      newNamedArgs]) {
                    def wrappedArgs := [for arg in (newArgs)
                                        astBuilder.LiteralExpr(arg, span)]
                    def wrappedNamedArgs := [for k => v in (newNamedArgs)
                                             astBuilder.NamedArg(astBuilder.LiteralExpr(k,
                                             null),
                                                        astBuilder.LiteralExpr(v,
                                                        null),
                                                        span)]
                    def call := astBuilder.MethodCallExpr(astBuilder.LiteralExpr(newMaker,
                                                               span),
                                                 newVerb, wrappedArgs,
                                                 wrappedNamedArgs, span)
                    call.transform(uncallLiterals)
                } else {
                    throw(`Warning: Couldn't freeze $obj: Bad uncall ${obj._uncall()}`)
                }
            }
        }
    } else { M.call(maker, "run", args + [span], [].asMap()) }

def mix(expr, baseScope) as DeepFrozen:
    def neededOuters := expr.getStaticScope().namesUsed()
    # Only propagate exactly those values needed, to make reasoning and
    # debugging easier.
    def topValueScope := [for `&&@k` => v in (baseScope)
                          ? (neededOuters.contains(k)) k => v]
    def staticOuters := topValueScope.getKeys().asSet() - [
        # Needs to be reimplemented as unfoldable code.
        # "_loop",
        # Can cause code explosion.
        # "_iterForever",
        # Hard to tame directly.
        # "throw",
        # Has side effects.
        "traceln",
    ].asSet()
    def fixpoint := staticFixpoint(staticOuters)
    def [exprAnnos, methodKits] := fixpoint.annotate(expr)
    traceln("Pretty", pretty(expr, exprAnnos))
    def reducer := makeReducer(exprAnnos, methodKits, topValueScope)
    def mixed := reducer(expr)
    # traceln("Mixed", mixed)
    def uncalled := mixed.transform(uncallLiterals)
    traceln("Uncalled", uncalled)
    return uncalled

def mixSafeScope(expr) as DeepFrozen:
    return mix(expr, safeScope)


def makeEvalCase(expr):
    def expanded := expr.expand()
    return def testEvalEquivalence(assert):
        def mixed := mix(expanded, safeScope)
        assert.equal(eval(mixed, safeScope), eval(expanded, safeScope))

unittest([for expr in ([
    # Literals.
    m`null`,
    m`42`,
    m`"¡Olé for Monte!"`,
    # Collections.
    m`[1, 2, 3, 4]`,
    m`["everybody" => "walk", "the" => "dinosaur"]`,
    m`def l := [1, 2, 3, 4]; l[2]`,
    m`def l := [].diverge(); l.push(0); l.push(1); l.snapshot()`,
    # Objects.
    m`(fn x { x + 1 })(4)`,
    # Arithmetic.
    m`def a := 5; def b := 7; a * b`,
    # Conditionals.
    m`if (true) { 2 } else { 4 }`,
    # Recursive functions.
    m`def fact(x :Int) {
        return if (x < 2) { x } else { x * fact(x - 1) }
    }; fact(5)`,
    # Finite loops.
    m`def triangle(x :Int) {
        var a := 0
        for i in (0..x) { a += i }
        return a
    }; [triangle(5), triangle(10)]`,
    m`def fb(upper :Int) :List[Str] {
        return [for i in (0..upper) {
            if (i % 15 == 0) {
                "FizzBuzz"
            } else if (i % 5 == 0) {
                "Fizz"
            } else if (i % 3 == 0) {
                "Buzz"
            } else {``$$i``}
        }]
    }; fb(20)`,
]) makeEvalCase(expr)])

def main(_argv :List[Str]) as DeepFrozen:
    def bf := m`def bf(insts :Str) {
        def jumps := {
            def m := [].asMap().diverge()
            def stack := [].diverge()
            for i => c in (insts) {
                if (c == '[') { stack.push(i) } else if (c == ']') {
                    def j := stack.pop()
                    m[i] := j
                    m[j] := i
                }
            }
            m.snapshot()
        }

        return def interpret() {
            var i := 0
            var pointer := 0
            def tape := [0].diverge()
            def output := [].diverge()
            while (i < insts.size()) {
                switch(insts[i]) {
                    match =='>' {
                        pointer += 1
                        while (pointer > tape.size()) { tape.push(0) }
                    }
                    match =='<' { pointer -= 1 }
                    match =='+' { tape[pointer] += 1 }
                    match =='-' { tape[pointer] -= 1 }
                    match =='.' { output.push(tape[pointer]) }
                    match ==',' { tape[pointer] := 0 }
                    match =='[' {
                        if (tape[pointer] == 0) { i := jumps[i] }
                    }
                    match ==']' {
                        if (tape[pointer] != 0) { i := jumps[i] }
                    }
                }
                i += 1
            }
            return output.snapshot()
        }
    }; bf("+++>>[-]<<[->>+<<]")`.expand()
    mix(bf, safeScope)
    0
