import "unittest" =~ [=> unittest]
exports (main, mix)

# The partial evaluator.
# We specialize Monte source to Monte source using straightforward offline
# partial evaluation:
# * Binding-time analysis (BTA)
# * Expression reduction
# * Literal serialization

# Current current goal: EscapeExpr optimization
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

object staticExpr as DeepFrozen:
    to _printOn(out):
        out.print(`<annotation on static expr>`)

    to merge(_anno):
        return staticExpr

def makeAnnotation(name :Str, => var values := []) as DeepFrozen:
    return object annotation:
        to _printOn(out):
            out.print(`<annotation on "$name", values $values>`)

        to observeValue(value):
            values with= (value)

        to values():
            return values

        to merge(anno):
            return try:
                makeAnnotation("values" => anno.values() + values)
            catch _:
                staticExpr

def annotateBindings(topExpr :Expr, staticOuters :Set[Str]) as DeepFrozen:
    "
    Do BTA on an expression by abstract interpretation.

    The computed annotation is `true` for static or `false` for dynamic, using
    the standard Boolean lattice with AND.
    "

    def rv := [].asMap().diverge()

    # Map of simple names to annotations, stacked to keep changes visible to
    # all levels.
    def scopeStack := [[].asMap().diverge()].diverge()

    def pushScope():
        scopeStack.push([].asMap().diverge())

    def popScope():
        return scopeStack.pop().snapshot()

    def addToScope(name, annotation):
        traceln(`addToScope($name, $annotation)`)
        scopeStack.last()[name] := annotation

    def fetchAnnotation(name):
        for ss in (scopeStack.reverse()):
            return ss.fetch(name, __continue)

    def observe(name, value):
        traceln(`observe($name, $value)`)
        var anno := fetchAnnotation(name)
        if (anno != null && anno != staticExpr):
            anno.observeValue(value)
            traceln("values", anno.values())

    def isStatic(name) :Bool:
        if (staticOuters.contains(name)):
            return true
        for scope in (scopeStack):
            if (scope.contains(name)):
                return true
        return false

    def annotate

    def annotateIfStatic(name):
        return isStatic(name).pick(makeAnnotation(name), null)

    def annotateAll(exprs):
        for expr in (exprs):
            if (annotate(expr) == null):
                return null
        return staticExpr

    object annotationSum:
        match [=="run", annotations, _]:
            escape ej:
                for anno in (annotations):
                    if (anno == null):
                        ej()
                staticExpr
            catch _:
                null

    def matchBind(patt, annotation):
        traceln(`matchBind($patt, $annotation)`)
        switch (patt.getNodeName()):
            match =="IgnorePattern":
                null
            match =="BindingPattern":
                addToScope(patt.getNoun().getName(), annotation)
            match =="FinalPattern":
                addToScope(patt.getNoun().getName(), annotation)
            match =="VarPattern":
                # Whether VarPatts may be static.
                addToScope(patt.getNoun().getName(), null)
            match =="ListPattern":
                for subPatt in (patt.getPatterns()):
                    # This could be more specific. It would require doing some
                    # more aggressive value analysis.
                    matchBind(subPatt, null)
            match =="ViaPattern":
                annotate(patt.getExpr())
                # The transformation wipes out the value, unfortunately.
                matchBind(patt.getPattern(), null)

    bind annotate(expr):
        def truish(expr):
            return if (expr == null) { staticExpr } else { annotate(expr) }

        def annotation := switch (expr.getNodeName()) {
            match =="LiteralExpr" { staticExpr }
            match =="BindingExpr" { annotateIfStatic(expr.getName()) }
            match =="NounExpr" { annotateIfStatic(expr.getName()) }
            match =="AssignExpr" {
                annotationSum(annotateIfStatic(expr.getLvalue().getName()),
                              annotate(expr.getRvalue()))
            }
            match =="DefExpr" {
                def rhs := expr.getExpr()
                def rhsAnno := annotate(rhs)
                var anno := annotationSum(rhsAnno, truish(expr.getExit()))
                # Look for `match ==value`.
                if (rhs != null &&
                    expr =~ m`def via (_matchSame.run(@val)) _ exit @_ := @rhs` &&
                    rhs.getNodeName() == "NounExpr") {
                    traceln("scopeStack", scopeStack)
                    def name := rhs.getName()
                    observe(name, val)
                }
                def patt := expr.getPattern()
                matchBind(patt, rhsAnno)
                anno
            }
            match =="HideExpr" {
                pushScope()
                def anno := annotate(expr.getBody())
                popScope()
                anno
            }
            match =="MethodCallExpr" {
                annotationSum(annotate(expr.getReceiver()),
                              annotateAll(expr.getArgs()),
                              annotateAll(expr.getNamedArgs()))
            }
            match =="EscapeExpr" {
                pushScope()
                # Whether ejectors can be statically discharged.
                matchBind(expr.getEjectorPattern(), staticExpr)
                var anno := annotate(expr.getBody())
                popScope()
                if (expr.getCatchPattern() != null) {
                    pushScope()
                    matchBind(expr.getCatchPattern(), staticExpr)
                    anno := annotationSum(anno, annotate(expr.getCatchBody()))
                    popScope()
                }
                anno
            }
            match =="FinallyExpr" {
                pushScope()
                var anno := annotate(expr.getBody())
                popScope()
                pushScope()
                if (anno != null) {
                    anno merge= (annotate(expr.getUnwinder()))
                }
                popScope()
                anno
            }
            match =="IfExpr" {
                annotationSum(annotate(expr.getTest()),
                              annotate(expr.getThen()),
                              truish(expr.getElse()))
            }
            match =="SeqExpr" { annotateAll(expr.getExprs()) }
            match =="CatchExpr" {
                pushScope()
                var anno := annotate(expr.getBody())
                popScope()
                pushScope()
                # Whether exceptions can be static.
                matchBind(expr.getPattern(), null)
                if (anno != null) {
                    anno merge= (annotate(expr.getCatcher()))
                }
                popScope()
                anno
            }
            match =="ObjectExpr" {
                def patt := expr.getName()
                var anno := annotationSum(truish(expr.getAsExpr()),
                    annotateAll(expr.getAuditors()))
                # Annotate the script but do not use its annotation directly.
                def script := expr.getScript()
                for m in (script.getMethods()) { annotate(m) }
                for m in (script.getMatchers()) { annotate(m) }
                # Instead, consider whether the script's scope will be fully
                # bound at reduction time. If so, then the object can be
                # enlivened; its guts will be fully static, so it can be
                # safely applied to static values to produce new static
                # values. Additionally, the object will be fully virtualized
                # away from the residual program, since all of its actions are
                # taken at reduction time.
                def namesUsed := script.getStaticScope().namesUsed()
                def freeNames := namesUsed - selfNames(patt) - staticOuters
                traceln("namesUsed", namesUsed, "freeNames", freeNames)
                if (!freeNames.isEmpty()) { anno := null }
                # Whether this object will be static.
                matchBind(patt, anno)
                anno
            }
            match =="Method" {
                pushScope()
                # Not bothering to match-bind patterns here. Assuming that all
                # patterns will start off as dynamic, and we'll respecialize
                # them later upon binding.
                def anno := annotationSum(truish(expr.getResultGuard()),
                    annotate(expr.getBody()))
                popScope()
                anno
            }
            match =="Script" {
                annotationSum(annotateAll(expr.getMethods()),
                              annotateAll(expr.getMatchers()))
            }
        }
        return rv[expr] := annotation

    annotate(topExpr)
    return rv.snapshot()

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

def makeScopeStack(baseScope :Map) as DeepFrozen:
    def locals := [].asMap().diverge()

    return object scopeStack:
        to reanno(expr, reduce):
            "
            Recursively re-annotate and re-specialize from the current frame.

            This recursion is performed in a fresh frame, as if a hide-expr
            were wrapped.
            "

            def staticOuters := [for `&&@k` in ((baseScope | locals).getKeys()) k].asSet()
            # traceln("Annotating with static outers", staticOuters)
            def annos := annotateBindings(expr, staticOuters)
            traceln("Polyvariants", [for _ => v in (annos)
                ? (v != null && v != staticExpr && !v.values().isEmpty()) v])
            return reduce(expr, annos, scopeStack.fresh())

        to fresh():
            return makeScopeStack(baseScope | locals)

        to addName(name :Str, value):
            locals["&&" + name] := value

        to lookup(name :Str, ej):
            def key := "&&" + name
            return if (locals.contains(key)):
                locals[key]
            else if (baseScope.contains(key)):
                baseScope[key]
            else:
                throw.eject(ej, `Key $key not actually in static scope`)

interface Static :DeepFrozen {}

def makeStaticObject(scopeStack, script, selfName) as DeepFrozen:
    def methods := [for m in (script.getMethods())
                    [m.getVerb(), m.getPatterns().size()] => m]
    object staticObject as Static:
        to unfold(verb, args, _namedArgs, reduce):
            "
            Unfold a call to this object.

            The returned method body will be recursively specialized.
            "

            def m := methods[[verb, args.size()]]
            def patts := m.getPatterns()
            def binds := [for i => arg in (args)
                          m`def ${patts[i]} := ${astBuilder.LiteralExpr(arg, null)}`]
            def resultGuard := m.getResultGuard()
            def body := m`{ ${seq(binds + [m.getBody()])} }`
            return scopeStack.reanno(if (resultGuard != null) {
                m`{
                    def _mix_body_result := $body
                    def _mix_resultGuard := $resultGuard
                    _mix_resultGuard.coerce(_mix_body_result, null)
                }`
            } else { body }, reduce)
    # Tie the knot.
    if (selfName != null):
        scopeStack.addName(selfName, &&staticObject)
    return staticObject

def reduce(expr, annotations, scopeStack) as DeepFrozen:
    "
    Close `expr` over the given scope and constant-fold aggressively.
    "

    def rere(ex):
        return if (ex == null) { null } else {
            reduce(ex, annotations, scopeStack)
        }

    def fresh(ex):
        return if (ex == null) { null } else {
            reduce(ex, annotations, scopeStack.fresh())
        }

    def withFresh(f):
        def ss := scopeStack.fresh()
        def re(ex):
            return if (ex == null) { null } else {
                reduce(ex, annotations, ss)
            }
        return f(re, ss)

    def movable(ex):
        return (ex == null || isLiteral(ex) ||
                ["BindingExpr", "NounExpr"].contains(ex.getNodeName()))

    def isStatic(ex):
        return annotations.contains(ex) && annotations[ex] != null

    def allStatic(exprs):
        for ex in (exprs):
            if (!isStatic(ex)):
                return false
        return true

    return switch (expr.getNodeName()) {
        match =="LiteralExpr" { expr }
        match =="BindingExpr" {
            def name := expr.getNoun().getName()
            if (isStatic(expr) && name =~ via (scopeStack.lookup) binding) {
                traceln("binding is static", expr)
                astBuilder.LiteralExpr(binding, null)
            } else { expr }
        }
        match =="NounExpr" {
            def name := expr.getName()
            if (isStatic(expr) && name =~ via (scopeStack.lookup) binding) {
                traceln("noun is static", expr)
                astBuilder.LiteralExpr(binding.get().get(), null)
            } else { expr }
        }
        match =="AssignExpr" {
            def rhs := rere(expr.getRvalue())
            def target := expr.getLvalue().getName()
            if (isStatic(expr) && isLiteral(rhs) &&
                target =~ via (scopeStack.lookup) binding) {
                traceln("assign is static", expr)
                binding.put(rhs.getValue())
                rhs
            } else { astBuilder.AssignExpr(expr.getLvalue(), rhs, null) }
        }
        match =="DefExpr" {
            var patt := expr.getPattern()
            def ex := rere(expr.getExit())
            var rhs := rere(expr.getExpr())
            # Can we simplify this assignment at all?
            if (isLiteral(rhs) && movable(ex)) {
                traceln("def is literal", expr)
                def realExit := if (ex == null) { m`null` } else { ex }
                while (patt.refutable()) {
                    switch (patt.getNodeName()) {
                        # XXX cases
                        match =="FinalPattern" {
                            # Only refutable because of a guard, so we must
                            # handle the guard.
                            def guard := patt.getGuard()
                            rhs := scopeStack.reanno(m`$guard.coerce($rhs,
                                                       $realExit)`, reduce)
                            patt withGuard= (null)
                        }
                    }
                }
                switch (patt.getNodeName()) {
                    match =="IgnorePattern" { rhs }
                    match =="FinalPattern" ? (isLiteral(rhs)) {
                        # Propagate a new constant.
                        traceln("propagating constant", patt, rhs)
                        def binding := { def derp := rhs.getValue(); &&derp }
                        scopeStack.addName(patt.getNoun().getName(), binding)
                        rhs
                    }
                    match _ {
                        # Irrefutable but not yet usable by us.
                        astBuilder.DefExpr(patt, ex, rhs, null)
                    }
                }
            } else { astBuilder.DefExpr(patt, ex, rhs, null) }
        }
        match =="HideExpr" {
            fresh(expr.getBody())
        }
        match =="MethodCallExpr" {
            def receiver := rere(expr.getReceiver())
            def verb := expr.getVerb()
            def args := [for arg in (expr.getArgs()) rere(arg)]
            def namedArgs := [for namedArg in (expr.getNamedArgs())
                              rere(namedArg)]
            if (isLiteral(receiver)) {
                def r := receiver.getValue()
                if (allLiteral(args) && allLiteral(namedArgs)) {
                    traceln("call is static", expr)
                    def a := [for arg in (args) arg.getValue()]
                    def na := [for namedArg in (namedArgs)
                               namedArg.getKey().getValue() =>
                               namedArg.getValue().getValue()]
                    if (r =~ static :Static) {
                        def rv := static.unfold(verb, a, na, reduce)
                        traceln(`unfold($verb, $a, $na) -> $rv`)
                        rv
                    } else {
                        def rv := M.call(r, verb, a, na)
                        traceln(`M.call($r, $verb, $a, $na) -> $rv`)
                        astBuilder.LiteralExpr(rv, null)
                    }
                } else if (r == _loop) {
                    # Let's unroll the loop!
                    for arg in (args) {
                        traceln("unroll arg", arg)
                        traceln("isStatic isLiteral", isStatic(arg),
                        isLiteral(arg))
                    }
                    astBuilder.MethodCallExpr(receiver, verb, args, namedArgs, null)
                } else {
                    astBuilder.MethodCallExpr(receiver, verb, args, namedArgs, null)
                }
            } else {
                astBuilder.MethodCallExpr(receiver, verb, args, namedArgs, null)
            }
        }
        match =="EscapeExpr" {
            def ejPatt := expr.getEjectorPattern()
            def catchPatt := expr.getCatchPattern()
            if (isStatic(expr)) {
                traceln("starting static ejector", expr)
                # We create a live ejector here.
                escape ej {
                    withFresh(fn re, ss {
                        ss.addName(ejPatt.getNoun().getName(), &&ej)
                        re(expr.getBody())
                    })
                } catch val {
                    if (catchPatt == null) {
                        astBuilder.LiteralExpr(val, null)
                    } else {
                        withFresh(fn re, ss {
                            ss.addName(catchPatt.getNoun().getName(), &&val)
                            re(expr.getCatchBody())
                        })
                    }
                }
            } else {
                def ejBody := fresh(expr.getBody())
                def catchBody := fresh(expr.getCatchBody())
                astBuilder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody,
                                      null)
            }
        }
        match =="FinallyExpr" {
            def body := fresh(expr.getBody())
            def unwinder := fresh(expr.getUnwinder())
            astBuilder.FinallyExpr(body, unwinder, null)
        }
        match =="IfExpr" {
            # It is crucial for pruning that we only recurse into a branch if
            # we need to generate its code; otherwise, we must avoid dead
            # branches.
            withFresh(fn re, _ss {
                def oldTest := expr.getTest()
                def test := re(oldTest)
                if (isStatic(oldTest) && isLiteral(test)) {
                    traceln("if is static", expr)
                    def whether :Bool := test.getValue()
                    re(whether.pick(expr.getThen(), expr.getElse()))
                } else {
                    def alt := re(expr.getThen())
                    def cons := re(expr.getElse())
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
                if (subExpr.getNodeName() == "DefExpr") {
                    def anno := annotations.fetch(subExpr.getExpr(),
                                                  fn { null })
                    if (anno != null && anno != staticExpr) {
                        traceln("found poly", anno)
                    }
                }
                last := rere(subExpr)
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
            def asExpr := rere(expr.getAsExpr())
            def auditors := [for a in (expr.getAuditors()) rere(a)]
            def script := {
                def s := expr.getScript()
                def methods := [for m in (s.getMethods()) fresh(m)]
                def matchers := [for m in (s.getMatchers()) fresh(m)]
                astBuilder.Script(null, methods, matchers, null)
            }
            def patt := expr.getName()
            if (isStatic(expr) && patt.getNodeName() == "FinalPattern") {
                traceln("Binding static object", patt)
                def noun := patt.getNoun()
                def name := noun.getName()
                def live := makeStaticObject(scopeStack.fresh(), script, name)
                scopeStack.addName(name, &&live)
                noun
            } else {
                astBuilder.ObjectExpr(expr.getDocstring(), patt, asExpr,
                                      auditors, script, null)
            }
        }
        match =="Method" {
            def resultGuard := rere(expr.getResultGuard())
            def body := fresh(expr.getBody())
            astBuilder."Method"(expr.getDocstring(), expr.getVerb(),
                                expr.getPatterns(), expr.getNamedPatterns(),
                                resultGuard, body, null)
        }
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
    def staticOuters := [for `&&@k` => _ in (safeScope) k].asSet() - [
        # Hard to tame directly.
        "throw",
        # Has side effects.
        "traceln",
    ].asSet()
    def annotations := annotateBindings(expr, staticOuters)
    def scopeStack := makeScopeStack(safeScope)
    def mixed := reduce(expr, annotations, scopeStack)
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
