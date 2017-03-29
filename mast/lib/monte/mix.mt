import "unittest" =~ [=> unittest]
exports (main, mix)

# The partial evaluator.

# Current goal: Refactor to offline
# Current goal: Unfolding
# Next goal: Switch -> If
# Goal: cogen

# def Scope :DeepFrozen := Map[Str, Binding]
# def emptyScope :DeepFrozen := [].asMap()
def Ast :DeepFrozen := astBuilder.getAstGuard()
def Expr :DeepFrozen := astBuilder.getExprGuard()

def and(bools :List[Bool]) :Bool as DeepFrozen:
    for b in (bools):
        if (!b):
            return false
    return true

def annotateBindings(topExpr :Expr, staticOuters :Set[Str]) :Map[Ast, Bool] as DeepFrozen:
    "
    Do BTA on an expression by abstract interpretation.

    The computed annotation is `true` for static or `false` for dynamic, using
    the standard Boolean lattice with AND.
    "

    def rv := [].asMap().diverge()

    def truish(b) :Bool:
        return if (b == null) { true } else { b }

    def annotate(node, _maker, args :List, _span) :Bool:
        def annotation := switch (node.getNodeName()) {
            match =="LiteralExpr" { true }
            match =="BindingExpr" { staticOuters.contains(args[0]) }
            match =="NounExpr" { staticOuters.contains(args[0]) }
            match =="AssignExpr" { false }
            match =="DefExpr" {
                args[0] && truish(args[1]) && args[2]
            }
            match =="HideExpr" { args[0] }
            match =="MethodCallExpr" {
                args[0] && and(args[2]) && and(args[3])
            }
            match =="EscapeExpr" {
                args[0] && args[1] && truish(args[2]) && truish(args[3])
            }
            match =="FinallyExpr" { and(args) }
            match =="IfExpr" {
                args[0] && args[1] && truish(args[2])
            }
            match =="SeqExpr" { and(args[0]) }
            match =="CatchExpr" { and(args) }
            match =="ObjectExpr" {
                args[1] && truish(args[2]) && and(args[3]) && args[4]
            }
            match =="Method" {
                and(args[2]) && and(args[3]) && truish(args[4]) && args[5]
            }
            match =="Script" {
                and(args[1]) && and(args[2])
            }
            match =="IgnorePattern" { truish(args[0]) }
            match =="BindingPattern" { true }
            match =="FinalPattern" { truish(args[1]) }
            # XXX someday
            match =="VarPattern" { false }
            # Kernel list patterns have no tail.
            match =="ListPattern" { and(args[0]) }
            match =="ViaPattern" { and(args) }
        }
        return rv[node] := annotation

    topExpr.transform(annotate)
    return rv.snapshot()

def makeScopeStack(baseScope :Map) as DeepFrozen:
    def locals := [].asMap().diverge()

    return object scopeStack:
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

def reduce(expr :Expr, annotations, scopeStack) as DeepFrozen:
    "
    Close `expr` over the given scope and constant-fold aggressively.
    "

    def seq(exprs):
        return if (exprs =~ [e]) { e } else { astBuilder.SeqExpr(exprs, null) }

    def rere(ex):
        return reduce(ex, annotations, scopeStack)

    def fresh(ex):
        return reduce(ex, annotations, scopeStack.fresh())

    # XXX if the annotations were more reliable, then we would do `if
    # (annotations[expr])` or something.
    return switch (expr.getNodeName()) {
        match =="LiteralExpr" { expr }
        match =="BindingExpr" {
            def name := expr.getNoun().getName()
            if (name =~ via (scopeStack.lookup) binding) {
                astBuilder.LiteralExpr(binding, null)
            } else { expr }
        }
        match =="NounExpr" {
            def name := expr.getName()
            if (name =~ via (scopeStack.lookup) binding) {
                astBuilder.LiteralExpr(binding.get().get(), null)
            } else { expr }
        }
        match =="AssignExpr" {
            def rhs := rere(expr.getRvalue())
            def target := expr.getLvalue().getNoun().getName()
            if (isLiteral(rhs) && target =~ via (scopeStack.lookup) binding) {
                binding.put(rhs.getValue())
                rhs
            } else { astBuilder.AssignExpr(expr.getLvalue(), rhs, null) }
        }
        match =="DefExpr" {
            def patt := expr.getPattern()
            def ex := expr.getExit()
            def rhs := rere(expr.getExpr())
            astBuilder.DefExpr(patt, ex, rhs, null)
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
            if (isLiteral(receiver) && allLiteral(args) &&
                allLiteral(namedArgs)) {
                def r := receiver.getValue()
                def a := [for arg in (args) arg.getValue()]
                def na := [for namedArg in (namedArgs)
                           namedArg.getKey().getValue() =>
                           namedArg.getValue().getValue()]
                astBuilder.LiteralExpr(M.call(r, verb, a, na), null)
            } else {
                astBuilder.MethodCallExpr(receiver, verb, args, namedArgs, null)
            }
        }
        match =="EscapeExpr" { expr }
        match =="FinallyExpr" {
            def body := fresh(expr.getBody())
            def unwinder := fresh(expr.getUnwinder())
            astBuilder.FinallyExpr(body, unwinder, null)
        }
        match =="IfExpr" { expr }
        match =="SeqExpr" {
            var last := null
            def rv := [].diverge()
            for subExpr in (expr.getExprs()) {
                last := rere(subExpr)
                def trivialExprs := ["BindingExpr", "LiteralExpr", "NounExpr"]
                if (!trivialExprs.contains(last.getNodeName())) {
                    rv.push(last)
                }
            }
            if (rv.isEmpty()) { last } else { seq(rv.snapshot()) }
        }
        match =="CatchExpr" { expr }
        match =="ObjectExpr" { expr }
    }


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
            # match k ? (freezeMap.contains(k)) {
            #     traceln(`Found $k in freezeMap`)
            #     return a.NounExpr(freezeMap[k], span)
            # }
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
        # Has side effects.
        "traceln",
    ].asSet()
    def annotations := annotateBindings(expr, staticOuters)
    traceln("Interesting Annotations", [for k => v in (annotations) ? (v) k])
    def scopeStack := makeScopeStack(safeScope)
    def mixed := reduce(expr, annotations, scopeStack)
    traceln("Mixed", mixed)
    return mixed.transform(uncallLiterals)


def makeEvalCase(expr):
    def expanded := expr.expand()
    return def testEvalEquivalence(assert):
        assert.equal(mix(expanded, safeScope), eval(expanded, safeScope))

unittest([for expr in ([
    # Literals.
    m`null`,
    m`42`,
    m`"¡Olé for Monte!"`,
    # Collections.
    m`[1, 2, 3, 4]`,
    m`["everybody" => "walk", "the" => "dinosaur"]`,
    # Objects.
    m`(fn x { x + 1 })(4)`,
    # Arithmetic.
    m`def a := 5; def b := 7; a * b`,
    # Conditionals.
    m`if (true) { 2 } else { 4 }`,
]) makeEvalCase(expr)])

def derp(expr) as DeepFrozen:
    def mixed := mix(expr, safeScope)
    traceln("Mixed", mixed)

def main(_argv :List[Str]) as DeepFrozen:
    def index := m`def l := [1, 2, 3, 4]; l[2]`.expand()
    derp(index)
    def factorial := m`def fact(x :Int) {
        return if (x < 2) { x } else { x * fact(x - 1) }
    }; fact(5)`.expand()
    derp(factorial)
    def _bf := m`def bf(insts) {
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
    # derp(bf)
