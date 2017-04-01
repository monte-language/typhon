import "unittest" =~ [=> unittest]
exports (main, mix)

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
def Expr :DeepFrozen := astBuilder.getExprGuard()
def Patt :DeepFrozen := astBuilder.getPatternGuard()

def seq(exprs) as DeepFrozen:
    return if (exprs =~ [e]) { e } else { astBuilder.SeqExpr(exprs, null) }

def selfNames(patt :Patt) :Set[Str] as DeepFrozen:
    return switch (patt.getNodeName()) {
        match =="IgnorePattern" { [].asSet() }
        match =="BindingPattern" { [patt.getNoun().getName()].asSet() }
        match =="FinalPattern" { [patt.getNoun().getName()].asSet() }
        match =="VarPattern" { [patt.getNoun().getName()].asSet() }
        match =="ListPattern" {
            var s := [].asSet()
            for subPatt in (patt.getPatterns()) { s |= selfNames(subPatt) }
            s
        }
        match =="ViaPattern" { selfNames(patt.getPattern()) }
    }

def makeAnnotation(name :Str, => var isStatic :Bool) as DeepFrozen:
    var canEscape :Bool := false
    def values := [].asSet().diverge()

    return object annotation:
        to _printOn(out):
            out.print("<anno")
            out.print(isStatic.pick("s", "d"))
            out.print(` "$name" | canEscape? $canEscape | values $values>`)

        to generalize():
            isStatic := false

        to escapes():
            canEscape := true

        to isStatic():
            return isStatic

        to observeValue(value):
            values.include(value)

        to snapshot():
            return if (isStatic):
                def ce :Bool := canEscape
                def vs :Set := values.snapshot()

                object staticAnnotation:
                    to _printOn(out):
                        out.print(`<static "$name" | canEscape? $ce | values $vs>`)

                    to isStatic() :Bool:
                        return true

                    to canEscape() :Bool:
                        return ce

                    to values() :Set:
                        return vs
            else:
                object dynamicAnnotation:
                    to _printOn(out):
                        out.print(`<dynamic "$name">`)

                    to isStatic() :Bool:
                        return false

                    to canEscape() :Bool:
                        return true

def all(bs :List[Bool]) :Bool as DeepFrozen:
    for b in (bs):
        if (!b):
            return false
    return true

def any(bs :List[Bool]) :Bool as DeepFrozen:
    for b in (bs):
        if (b):
            return true
    return false

def annotateBindings(topExpr :Expr, staticOuters :Set[Str]) as DeepFrozen:
    "
    Do BTA on an expression by abstract interpretation.

    The simple computed per-expression annotation is `true` for static or
    `false` for dynamic, using the standard Boolean lattice with AND. This
    process also computes a per-scope map of names to richer lifetime
    annotations.
    "

    # The per-expression Boolean annotation.
    def exprAnnos := [].asMap().diverge()
    # The per-scope rich annotations.
    def scopeAnnos := [].asMap().diverge()

    # Map of simple names to annotations, stacked to keep changes visible to
    # all levels.
    def outerScope := [for k in (staticOuters)
                       k => makeAnnotation(k, "isStatic" => true)]
    def scopeStack := [outerScope.diverge()].diverge()

    def pushScope():
        scopeStack.push([].asMap().diverge())

    def popScope():
        # Freeze annotations when the scope is frozen.
        return [for k => v in (scopeStack.pop()) k => v.snapshot()]

    def annotate

    object withScopesOn:
        match [=="run", [expr] + thunks, _]:
            def rv := [].diverge()
            def scopes := [for thunk in (thunks) {
                pushScope()
                rv.push(thunk())
                popScope()
            }]
            # Put them in the vault.
            scopeAnnos[expr] := scopes
            all(rv.snapshot())

    def addToScope(name, annotation):
        scopeStack.last()[name] := annotation

    def fetchAnnotation(name):
        for ss in (scopeStack.reverse()):
            return ss.fetch(name, __continue)
        # All annotations start out static and must be generalized if found to
        # be dynamic.
        def anno := makeAnnotation(name, "isStatic" => true)
        addToScope(name, anno)
        return anno

    def observe(name, value):
        traceln(`observe($name, $value)`)
        var anno := fetchAnnotation(name)
        anno.observeValue(value)

    def generalize(name):
        # traceln(`generalize($name)`)
        fetchAnnotation(name).generalize()

    def escapes(name):
        # traceln(`escapes($name)`)
        fetchAnnotation(name).escapes()

    def isStatic(name) :Bool:
        if (staticOuters.contains(name)):
            return true
        for scope in (scopeStack):
            if (scope.contains(name)):
                return scope[name].isStatic()
        # These names are things like `traceln` which are dynamic in all
        # contexts and must always be residualized.
        return false

    def annotateAll(exprs) :Bool:
        var rv :Bool := true
        for expr in (exprs):
            rv &= annotate(expr)
        return rv

    def matchBind(patt, annotation):
        # traceln(`matchBind($patt, $annotation)`)
        switch (patt.getNodeName()):
            match =="IgnorePattern":
                annotate(patt.getGuard())
            match =="BindingPattern":
                annotate(patt.getGuard())
                addToScope(patt.getNoun().getName(), annotation)
            match =="FinalPattern":
                annotate(patt.getGuard())
                addToScope(patt.getNoun().getName(), annotation)
            match =="VarPattern":
                annotate(patt.getGuard())
                # Whether VarPatts may be static.
                addToScope(patt.getNoun().getName(),
                           makeAnnotation(`$patt`, "isStatic" => false))
            match =="ListPattern":
                for subPatt in (patt.getPatterns()):
                    # This could be more specific. It would require doing some
                    # more aggressive value analysis.
                    matchBind(subPatt,
                              makeAnnotation(`$patt`, "isStatic" => false))
            match =="ViaPattern":
                annotate(patt.getExpr())
                # The transformation wipes out the value, unfortunately.
                matchBind(patt.getPattern(),
                          makeAnnotation(`$patt`, "isStatic" => false))

    def matchBindTop(patt, isStatic):
        matchBind(patt, makeAnnotation(`$patt`, => isStatic))

    def nullOk(expr):
        return if (expr == null) { true } else { annotate(expr) }

    def annoMethod(m, pattsAreStatic):
        return withScopesOn(m, fn {
            for patt in (m.getPatterns()) {
                matchBindTop(patt, pattsAreStatic)
            }
            def anno := nullOk(m.getResultGuard())
            anno & annotate(m.getBody())
        })

    def annoMatcher(m, pattsAreStatic):
        return withScopesOn(m, fn {
            # Same rationale as methods.
            matchBindTop(m.getPattern(), pattsAreStatic)
            annotate(m.getBody())
        })

    def annoEscape(expr, ejIsStatic):
        return withScopesOn(expr, fn {
            # Whether ejectors can be statically discharged.
            matchBindTop(expr.getEjectorPattern(), ejIsStatic)
            annotate(expr.getBody())
        }, fn {
            def catchPatt := expr.getCatchPattern()
            if (catchPatt != null) {
                matchBindTop(catchPatt, ejIsStatic)
                annotate(expr.getCatchBody())
            } else { true }
        })

    bind annotate(expr) :Bool:
        if (expr == null):
            return true

        def annotation := switch (expr.getNodeName()) {
            match =="LiteralExpr" { true }
            match =="BindingExpr" {
                # BindingExprs can devirtualize VarSlots, so we consider them
                # to be escape points. Note that this applies even when the
                # name is already known to be static, because a reified
                # VarSlot can be subject to further opaque redirection.
                def name := expr.getName()
                escapes(name)
                isStatic(name)
            }
            match =="NounExpr" { isStatic(expr.getName()) }
            match =="AssignExpr" {
                def rhs := annotate(expr.getRvalue())
                # If the RHS isn't static, then we must generalize the entire
                # VarSlot's name, since we can no longer predict its values.
                if (!rhs) { generalize(expr.getLvalue().getName()) }
                rhs
            }
            match =="DefExpr" {
                def rhs := expr.getExpr()
                def rhsAnno := annotate(rhs)
                var anno := rhsAnno & nullOk(expr.getExit())
                # Look for `match ==value`.
                if (rhs != null && rhs.getNodeName() == "NounExpr" &&
                    # XXX mpatt`` someday
                    expr =~ m`def via (_matchSame.run(@val)) _ exit @_ := @_`) {
                    def name := rhs.getName()
                    observe(name, val)
                }
                def patt := expr.getPattern()
                matchBindTop(patt, rhsAnno)
                anno
            }
            match =="HideExpr" {
                withScopesOn(expr, fn { annotate(expr.getBody()) })
            }
            match =="MethodCallExpr" {
                (annotate(expr.getReceiver()) &
                 annotateAll(expr.getArgs()) &
                 annotateAll(expr.getNamedArgs()))
            }
            match =="EscapeExpr" {
                # We must double-annotate since we have a circular premise;
                # for some escapes, they are static iff the ejector is static.
                # But for all escapes, if they are dynamic then the ejector
                # must be dynamic as well. Thus, we annotate twice if
                # necessary, once to discover static escapes and once to
                # ensure that the ejector is dynamic for dynamic escapes.

                # However! This can lead to obvious combinatorial explosion,
                # since Monte tends to have nested escapes in expanded code.
                # Therefore, we guess by examining the scope of the escape
                # whether it actually closes over any known-dynamic names. If
                # so, then we don't bother trying a static annotation, since
                # it's known to be doomed.

                # The specific guess we use is that we guess an escape might
                # be static if all of its used names are annotated static.
                def namesUsed := expr.getStaticScope().namesUsed()
                def guessedStatic := all([for name in (namesUsed)
                                          isStatic(name)])
                if (guessedStatic) {
                    traceln(`Guessed static escape`)
                    def anno := annoEscape(expr, true)
                    if (anno) { anno } else {
                        traceln(`Double-annotating escape`)
                        annoEscape(expr, false)
                    }
                } else {
                    traceln(`Guessed dynamic escape`)
                    annoEscape(expr, false)
                }
            }
            match =="FinallyExpr" {
                withScopesOn(expr, fn {
                    annotate(expr.getBody())
                }, fn {
                    annotate(expr.getUnwinder())
                })
            }
            match =="IfExpr" {
                # We must hack because a single IfExpr technically has three
                # scopes, with the two branch scopes being nested within the
                # test scope.
                pushScope()
                def anno := annotate(expr.getTest()) & withScopesOn(expr, fn {
                    annotate(expr.getThen())
                }, fn {
                    nullOk(expr.getElse())
                })
                def testScope := popScope()
                # The hack.
                scopeAnnos[expr] := [testScope] + scopeAnnos[expr]
                anno
            }
            match =="SeqExpr" { annotateAll(expr.getExprs()) }
            match =="CatchExpr" {
                withScopesOn(expr, fn {
                    annotate(expr.getBody())
                }, fn {
                    # Whether exceptions can be static in the catcher.
                    matchBindTop(expr.getPattern(), false)
                    annotate(expr.getCatcher())
                })
            }
            match =="ObjectExpr" {
                def patt := expr.getName()
                var anno := (nullOk(expr.getAsExpr()) &
                             annotateAll(expr.getAuditors()))
                # Annotate the script pieces. In order to be unfoldable, we
                # must have only static scripts.
                def script := expr.getScript()
                # From the POV of a method, its patterns are always static,
                # since they are static on every invocation of the method.
                # Ditto with matchers.
                for m in (script.getMethods()) {
                    anno &= annoMethod(m, true)
                }
                for m in (script.getMatchers()) {
                    anno &= annoMatcher(m, true)
                }
                # Consider whether the script's scope will be fully bound
                # at reduction time. If so, then the object can be
                # virtualized; its guts will be fully static, so it can be
                # safely applied to static values to produce new static
                # values. Additionally, the object will be fully removed
                # from the residual program, since all of its actions are
                # taken at reduction time.
                def namesUsed := script.getStaticScope().namesUsed()
                def freeNames := (namesUsed - selfNames(patt) -
                                  staticOuters).diverge()
                if (anno) {
                    # Free names are only a problem if they aren't static.
                    for name in (freeNames) {
                        if (isStatic(name)) { freeNames.remove(name) }
                    }
                    if (!freeNames.isEmpty()) {
                        traceln(`Object '$patt' had free names $freeNames`)
                        anno := false
                    }
                }
                if (!anno) {
                    traceln(`Devirtualizing object '$patt'`)
                    # Devirtualize the methods and matchers by reannotating.
                    for m in (script.getMethods()) { annoMethod(m, false) }
                    for m in (script.getMatchers()) { annoMatcher(m, false) }
                    # Mark all of the free names as escaping.
                    if (!anno) { for name in (freeNames) { escapes(name) } }
                }
                # Whether this object will be static.
                matchBindTop(patt, anno)
                anno
            }
        }
        return exprAnnos[expr] := annotation

    annotate(topExpr)
    return [exprAnnos.snapshot(), scopeAnnos.snapshot(), popScope()]

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

def makeStaticObject(reducer, scopeAnnos, script) as DeepFrozen:
    def methods := [for m in (script.getMethods())
                    [m.getVerb(), m.getPatterns().size()] => m]
    return object staticObject as Static:
        to unfold(verb, args, _namedArgs):
            "
            Unfold a call to this object.

            The returned method body will be recursively specialized.
            "

            def m := methods[[verb, args.size()]]
            def annos := scopeAnnos[m][0]
            return reducer.withScope(annos, fn {
                for i => patt in (m.getPatterns()) {
                    reducer.matchBind(patt, args[i])
                }
                def body := reducer(m.getBody())
                def resultGuard := reducer(m.getResultGuard())
                if (resultGuard == null) { body } else {
                    m`$resultGuard.coerce($body, null)`
                }
            })

def makeReducer(exprAnnos, scopeAnnos, topAnnoScope, topValueScope) as DeepFrozen:
    def annoStack := [topAnnoScope].diverge()
    def valueStack := [topValueScope].diverge()
    var locals := [].asMap().diverge()

    def pushScope(annos):
        annoStack.push(annos)
        valueStack.push(locals.snapshot())
        locals := [].asMap().diverge()

    def popScope():
        annoStack.pop()
        locals := valueStack.pop().diverge()

    def freezeScope():
        var annos := [].asMap()
        for s in (annoStack.reverse()):
            annos |= s
        var values := locals.snapshot()
        for s in (valueStack.reverse()):
            values |= s
        return [annos, values]

    def addName(name, value):
        traceln(`addName($name, $value)`)
        locals[name] := value
        traceln("local keys", locals.getKeys())

    def lookupAnno(name):
        for scope in (annoStack.reverse()):
            return scope.fetch(name, __continue)
        def stackDump := [for frame in (annoStack) frame.getKeys()]
        throw(`Unannotated name $name, searched $stackDump`)

    def lookupValue(name):
        if (locals.contains(name)):
            return locals[name]
        for scope in (valueStack.reverse()):
            return scope.fetch(name, __continue)
        def stackDump := [for frame in (valueStack + [locals]) frame.getKeys()]
        throw(`Unassigned name $name, searched $stackDump`)

    def movable(ex):
        return (ex == null || isLiteral(ex) ||
                ["BindingExpr", "NounExpr"].contains(ex.getNodeName()))

    def isStatic(ex):
        return exprAnnos.fetch(ex, fn {
            traceln("isStatic failed", ex)
            false
        })

    def maybeValue(expr):
        return if (expr == null) { null } else { expr.getValue() }

    def allStatic(exprs):
        for ex in (exprs):
            if (!isStatic(ex)):
                return false
        return true

    return object reducer:
        to withScope(scope, thunk):
            pushScope(scope)
            def rv := thunk()
            popScope()
            return rv

        to runGuard(guardExpr, specimen, ej):
            def guard := maybeValue(reducer(guardExpr))
            return if (guard == null) { specimen } else {
                guard.coerce(specimen, ej)
            }

        to escapes(patt):
            def rv := switch (patt.getNodeName()) {
                match =="IgnorePattern" { false }
                match =="BindingPattern" { false }
                match =="FinalPattern" { false }
                match =="VarPattern" {
                    def name := patt.getNoun().getName()
                    lookupAnno(name).canEscape()
                }
                match =="ListPattern" {
                    any([for p in (patt.getPatterns()) reducer.escapes(p)])
                }
                match =="ViaPattern" {
                    reducer.escapes(patt.getPattern())
                }
            }
            traceln(`reducer.escapes($patt) -> $rv`)
            return rv

        to matchBind(patt, specimen, => ej := null):
            traceln(`reducer.matchBind($patt, $specimen, $ej)`)
            switch (patt.getNodeName()):
                match =="IgnorePattern":
                    reducer.runGuard(patt.getGuard(), specimen, ej)
                match =="BindingPattern":
                    def prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    addName(patt.getNoun().getName(), prize)
                match =="FinalPattern":
                    def prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    traceln("propagating constant", patt, prize)
                    addName(patt.getNoun().getName(), &&prize)
                match =="VarPattern":
                    var prize := reducer.runGuard(patt.getGuard(), specimen, ej)
                    traceln("propagating variable", patt, prize)
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

        to run(expr):
            if (expr == null):
                return null

            traceln(`reducer(${expr.getNodeName()})`)

            return switch (expr.getNodeName()) {
                match =="LiteralExpr" { expr }
                match =="BindingExpr" {
                    def name := expr.getNoun().getName()
                    def anno := lookupAnno(name)
                    if (anno.isStatic() &! anno.canEscape()) {
                        def binding := lookupValue(name)
                        traceln(`Static binding: &&$name := $binding`)
                        astBuilder.LiteralExpr(binding, null)
                    } else { expr }
                }
                match =="NounExpr" {
                    def name := expr.getName()
                    def anno := lookupAnno(name)
                    if (anno.isStatic() &! anno.canEscape()) {
                        def noun := lookupValue(name).get().get()
                        traceln(`Static noun: &&$name := $noun`)
                        astBuilder.LiteralExpr(noun, null)
                    } else { expr }
                }
                match =="AssignExpr" {
                    def rhs := reducer(expr.getRvalue())
                    def lhs := expr.getLvalue()
                    def target := lhs.getName()
                    def anno := lookupAnno(target)
                    if (anno.isStatic() &! anno.canEscape()) {
                        def binding := lookupValue(target)
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
                    if (isStatic(expr) && !reducer.escapes(patt)) {
                        traceln(`Static def: def $patt exit $ex := $rhs`)
                        reducer.matchBind(patt, rhs.getValue(),
                                          "ej" => maybeValue(ex))
                        # And the return value of a DefExpr is the RHS.
                        rhs
                    } else { astBuilder.DefExpr(patt, ex, rhs, null) }
                }
                match =="HideExpr" {
                    def [scope] := scopeAnnos[expr]
                    reducer.withScope(scope, fn { reducer(expr.getBody()) })
                }
                match =="MethodCallExpr" {
                    def receiver := reducer(expr.getReceiver())
                    def verb := expr.getVerb()
                    def args := [for arg in (expr.getArgs()) reducer(arg)]
                    def namedArgs := [for namedArg in (expr.getNamedArgs())
                                      reducer(namedArg)]
                    if (isStatic(expr)) {
                        def r := receiver.getValue()
                        def a := [for arg in (args) arg.getValue()]
                        def na := [for namedArg in (namedArgs)
                                   namedArg.getKey().getValue() =>
                                   namedArg.getValue().getValue()]
                        if (r =~ static :Static) {
                            def rv := static.unfold(verb, a, na)
                            traceln(`unfold($verb, $a, $na) -> $rv`)
                            rv
                        } else {
                            def rv := M.call(r, verb, a, na)
                            traceln(`M.call($r, $verb, $a, $na) -> $rv`)
                            astBuilder.LiteralExpr(rv, null)
                        }
                    } else {
                        astBuilder.MethodCallExpr(receiver, verb, args, namedArgs, null)
                    }
                }
                match =="EscapeExpr" {
                    def ejPatt := expr.getEjectorPattern()
                    def catchPatt := expr.getCatchPattern()
                    def [ejScope, catchScope] := scopeAnnos[expr]
                    if (isStatic(expr)) {
                        traceln("starting static ejector", expr)
                        # We create a live ejector here.
                        escape ej {
                            def body := expr.getBody()
                            reducer.withScope(ejScope, fn {
                                addName(ejPatt.getNoun().getName(), &&ej)
                                reducer(body)
                            })
                        } catch val {
                            if (catchPatt == null) {
                                astBuilder.LiteralExpr(val, null)
                            } else {
                                def catchBody := expr.getCatchBody()
                                reducer.withScope(catchScope, fn {
                                    addName(catchPatt.getNoun().getName(), &&val)
                                    reducer(catchBody)
                                })
                            }
                        }
                    } else {
                        def ejBody := reducer.withScope(ejScope, fn {
                            reducer(expr.getBody())
                        })
                        def catchBody := reducer.withScope(catchScope, fn {
                            reducer(expr.getCatchBody())
                        })
                        astBuilder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody,
                                              null)
                    }
                }
                match =="FinallyExpr" {
                    def [bodyScope, unwinderScope] := scopeAnnos[expr]
                    def body := reducer.withScope(bodyScope, fn {
                        reducer(expr.getBody())
                    })
                    def unwinder := reducer.withScope(unwinderScope, fn {
                        reducer(expr.getUnwinder())
                    })
                    astBuilder.FinallyExpr(body, unwinder, null)
                }
                match =="IfExpr" {
                    # It is crucial for pruning that we only recurse into a branch if
                    # we need to generate its code; otherwise, we must avoid dead
                    # branches.
                    def oldTest := expr.getTest()
                    def [testScope, thenScope, elseScope] := scopeAnnos[expr]
                    reducer.withScope(testScope, fn {
                        def test := reducer(oldTest)
                        if (isStatic(oldTest) && isLiteral(test)) {
                            traceln("if is static", expr)
                            if (test.getValue()) {
                                reducer.withScope(thenScope, fn {
                                    reducer(expr.getThen())
                                })
                            } else {
                                reducer.withScope(elseScope, fn {
                                    reducer(expr.getElse())
                                })
                            }
                        } else {
                            def alt := reducer.withScope(thenScope, fn {
                                reducer(expr.getThen())
                            })
                            def cons := reducer.withScope(elseScope, fn {
                                reducer(expr.getElse())
                            })
                            astBuilder.IfExpr(test, alt, cons, null)
                        }
                    })
                }
                match =="SeqExpr" {
                    var last := null
                    def rv := [].diverge()
                    for subExpr in (expr.getExprs()) {
                        # If we have a polyvariant annotation on a definition, then
                        # substitute and expand.
                        if (subExpr =~ m`def @_ exit @_ := @rhs` &&
                            rhs.getNodeName() == "NounExpr") {
                            def anno := lookupAnno(rhs.getName())
                            if (anno != null) {
                                traceln("found poly", anno)
                            }
                        }
                        last := reducer(subExpr)
                        def trivialExprs := ["BindingExpr", "LiteralExpr", "NounExpr"]
                        if (!trivialExprs.contains(last.getNodeName())) {
                            rv.push(last)
                        }
                    }
                    if (rv.isEmpty()) { last } else { seq(rv.snapshot()) }
                }
                match =="CatchExpr" {
                    traceln("not entering catch", expr)
                    expr
                }
                match =="ObjectExpr" {
                    def asExpr := reducer(expr.getAsExpr())
                    def auditors := [for a in (expr.getAuditors()) reducer(a)]
                    def patt := expr.getName()
                    if (isStatic(expr) && !patt.refutable()) {
                        traceln("Binding static object", patt)
                        # Bind starting from the current closure.
                        def [annoScope, valueScope] := freezeScope()
                        def reducer := makeReducer(exprAnnos, scopeAnnos,
                            annoScope, valueScope)
                        # NB: The script must be reduced at unfold time, *not*
                        # at bind time. This is because the script's execution
                        # is actually suspended at bind time and it only runs
                        # during each unfold. Since we reduce in the order of
                        # operations, we must suspend here.
                        def live := makeStaticObject(reducer, scopeAnnos,
                            expr.getScript())
                        # Tie the knot, if necessary.
                        if (patt.getNodeName() != "IgnorePattern") {
                            def noun := patt.getNoun()
                            def name := noun.getName()
                            addName(name, &&live)
                        }
                        astBuilder.LiteralExpr(live, null)
                    } else {
                        def script := {
                            # Since we are residualizing, we need to optimize
                            # under our method/matcher bindings.
                            def s := expr.getScript()
                            def methods := [for m in (s.getMethods()) reducer(m)]
                            def matchers := [for m in (s.getMatchers()) reducer(m)]
                            astBuilder.Script(null, methods, matchers, null)
                        }
                        astBuilder.ObjectExpr(expr.getDocstring(), patt, asExpr,
                                              auditors, script, null)
                    }
                }
                match =="Method" {
                    def [scope] := scopeAnnos[expr]
                    # XXX lazy
                    reducer.withScope(scope, fn {
                        def body := reducer(expr.getBody())
                        def resultGuard := reducer(expr.getResultGuard())
                        astBuilder."Method"(expr.getDocstring(), expr.getVerb(),
                                            expr.getPatterns(), expr.getNamedPatterns(),
                                            resultGuard, body, null)
                    })
                }
                # XXX lazy
                match =="Matcher" { expr }
            }

def freezeMap :DeepFrozen := [for `&&@k` => v in (safeScope) v.get().get() => k]

def uncallLiterals(node, maker, args, span) as DeepFrozen:
    "Turn any illegal literals into legal literals."

    return if (node.getNodeName() == "LiteralExpr") {
        switch (args[0]) {
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
                traceln(`Found $k in freezeMap`)
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

def mix(expr, _baseScope) as DeepFrozen:
    # XXX doesn't use the custom baseScope at all
    def topValueScope := [for `&&@k` => v in (safeScope) k => v]
    def staticOuters := topValueScope.getKeys().asSet() - [
        # Needs to be reimplemented as unfoldable code.
        "_loop",
        # Ill-behaved.
        "``",
        # Hard to tame directly.
        "throw",
        # Has side effects.
        "traceln",
    ].asSet()
    def [exprAnnos, scopeAnnos, topAnnoScope] := annotateBindings(expr,
        staticOuters)
    def reducer := makeReducer(exprAnnos, scopeAnnos, topAnnoScope,
        topValueScope)
    def mixed := reducer(expr)
    traceln("Mixed", mixed)
    return mixed.transform(uncallLiterals)


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
]) makeEvalCase(expr)])

def derp(expr) as DeepFrozen:
    def mixed := mix(expr, safeScope)
    traceln("Mixed", mixed)

def main(_argv :List[Str]) as DeepFrozen:
    def triangle := m`def triangle(x :Int) {
        var a := 0
        for i in (0..x) { a += i }
        return a
    }; [triangle(5), triangle(10)]`.expand()
    derp(triangle)
    def fb := m`def fb(upper :Int) :List[Str] {
        return [for i in (0..upper) {
            if (i % 15 == 0) {
                "FizzBuzz"
            } else if (i % 5 == 0) {
                "Fizz"
            } else if (i % 3 == 0) {
                "Buzz"
            } else {``$$i``}
        }]
    }; fb(20)`.expand()
    derp(fb)
    def bf := m`def bf(insts) {
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
                    if (tape[pointer] == 0) {
                        while (insts[i] != ']') { i += 1 }
                    }
                }
                match ==']' {
                    if (tape[pointer] != 0) {
                        while (insts[i] != '[') { i -= 1 }
                    }
                }
            }
            i += 1
        }
        return output
    }; bf("+++>>[-]<<[->>+<<]")`.expand()
    derp(bf)
