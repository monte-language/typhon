import "unittest" =~ [=> unittest]
exports (main, mix)

# The partial evaluator.

# Current goal: Unfolding
# Goal: cogen

# def Scope :DeepFrozen := Map[Str, Binding]
# def emptyScope :DeepFrozen := [].asMap()
def Ast :DeepFrozen := astBuilder.getAstGuard()
def Expr :DeepFrozen := astBuilder.getExprGuard()
def Pattern :DeepFrozen := astBuilder.getPatternGuard()

object noSpecimen as DeepFrozen {}
object dynamic as DeepFrozen {}

interface Ghost :DeepFrozen {}

def makeGhostObject(methods, _matchers) as DeepFrozen:
    def builder := ::"m``".getAstBuilder()

    return object ghostObject as Ghost:
        to unfold(remix, verb, args, _namedArgs):
            # Look for matching methods.
            for m in (methods):
                def patts := m.getPatterns()
                if (m.getVerb() != verb || patts.size() != args.size()):
                    continue
                # If the pattern is refutable, then we don't have to generate
                # any code; we can just substitute the incoming value
                # directly. However, .refutable/0 isn't quite right here,
                # because we have to reify things like VarSlots. So, instead,
                # we just codegen each pattern and let the mixer sort it out.
                def margs := [for i => patt in (patts)
                              m`def $patt := ${args[i]}`]
                # XXX codegen for named args would go here
                def g := m.getResultGuard()
                def mainBody := remix(m`{
                    ${builder.SeqExpr(margs, null)}
                    m.getBody()
                }`)
                return if (g != null) {
                    m`{
                        def _rv := $mainBody
                        def _resultGuard := $g
                        _resultGuard.coerce(_rv, null)
                    }`
                } else { mainBody }

def isLiteral(expr) :Bool as DeepFrozen:
    return expr =~ _ :Ghost || expr.getNodeName() == "LiteralExpr"

def allLiteral(exprs :List[Expr]) :Bool as DeepFrozen:
    for expr in (exprs):
        if (!isLiteral(expr)):
            return false
    return true

def mainMix(expr :NullOk[Ast], baseScope :Map, var locals :Map,
            => var serial :Int := 0) as DeepFrozen:
    # cribbed from
    # https://github.com/monte-language/typhon/blob/master/typhon/nano/interp.py#L276

    if (expr == null):
        return [expr, locals]

    def builder := ::"m``".getAstBuilder()

    def tempNoun(label :Str) :Expr:
        return builder.NounExpr(`_mix_${label}_$serial`, null)

    def staticError(problem :Str):
        def p := builder.LiteralExpr(problem, null)
        return m`Ref.broken($p)`

    def seq(exprs):
        return if (exprs =~ [e]) { e } else { builder.SeqExpr(exprs, null) }

    def remix(subExpr):
        if (subExpr == null):
            return null
        def [rv, newLocals] := mainMix(subExpr, baseScope, locals)
        locals |= newLocals
        return rv

    def fresh(subExpr):
        if (subExpr == null):
            return null
        def [rv, _] := mainMix(subExpr, baseScope | locals, [].asMap())
        return rv

    def withFresh(block):
        var ls := [].asMap()
        def freshScope := baseScope | locals
        return block(def callFresh(subExpr) {
            def [rv, newLocals] := mainMix(subExpr, freshScope, ls)
            ls := newLocals
            return rv
        })

    def opt(subExpr):
        return if (subExpr == null) { null } else { remix(subExpr) }

    # XXX should be used in matchBind?
    def _staticThrow(problem :Str):
        def p := builder.LiteralExpr(problem, null)
        return m`throw($p)`

    def matchBind(patt :Pattern, specimen, => ej := throw):
        switch (patt.getNodeName()):
            match =="IgnorePattern":
                def guard := opt(patt.getGuard())
                if (guard != null):
                    guard.coerce(specimen, ej)

            match =="BindingPattern":
                def key := "&&" + patt.getNoun().getName()
                locals with= (key, specimen)

            match =="FinalPattern":
                # TODO: check that name is not already taken
                def key := "&&" + patt.getNoun().getName()
                def guard := opt(patt.getGuard())
                def val := _slotToBinding(_makeFinalSlot(guard, specimen, ej),
                                          ej)
                locals with= (key, val)

            match =="VarPattern":
                # TODO: check that name is not already taken
                def key := "&&" + patt.getNoun().getName()
                def guard := opt(patt.getGuard())
                def val := _slotToBinding(_makeVarSlot(guard, specimen, ej),
                                          ej)
                locals with= (key, val)

            match =="ListPattern":
                # Kernel list patterns have no tail.
                def patts := patt.getPatterns()
                def l :List exit ej := specimen
                if (patts.size() != l.size()):
                    ej(`Failed list pattern (needed ${patts.size()}, got ${l.size()})`)
                for ix => patt in (patts):
                    matchBind(patt, specimen[ix], => ej)

            match =="ViaPattern":
                def v := remix(patt.getExpr())
                def newSpec := v(specimen, ej)
                # semantics could be clearer that we use the same ejector below.
                matchBind(patt.getPattern(), newSpec, => ej)

    def newExpr := switch (expr.getNodeName()) {
        match =="LiteralExpr" { expr }

        match =="BindingExpr" {
            def name := expr.getNoun().getName()
            traceln("binding name", name)
            if (locals.contains(name)) {
                # Synthesize a binding.
                def value := locals[name]
                m`_slotToBinding(_makeFinalSlot(Any, $value, null), null)`
            } else if (locals.contains("&&" + name)) {
                locals["&&" + name]
            } else { expr }
        }

        match =="NounExpr" {
            def name := expr.getName()
            if (locals.contains(name)) {
                locals[name]
            } else if (locals.contains("&&" + name)) {
                locals["&&" + name].get().get()
            } else { expr }
        }

        match =="AssignExpr" {
            def m`@lhs := @rhs` := expr
            m`$lhs := ${remix(rhs)}`
        }

        match =="DefExpr" {
            def val := remix(expr.getExpr())
            def ej :NullOk[Expr] := remix(expr.getExit())
            def patt := remix(expr.getPattern())
            # XXX we can eventually generalize the latter
            if (isLiteral(val) && ej == null) {
                if (ej == null) { matchBind(patt, val) } else {
                    matchBind(patt, val, => ej)
                }
                val
            } else { builder.DefExpr(patt, ej, val, null) }
        }

        match =="HideExpr" { fresh(expr.getBody()) }

        match =="MethodCallExpr" {
            def verb := expr.getVerb()
            def rxValue := remix(expr.getReceiver())
            def argVals := [for arg in (expr.getArgs()) remix(arg)]
            def nargVals := [for name => arg in (expr.getNamedArgs())
                             remix(name) => remix(arg)]
            def packedNamedArgs := [for k => v in (nargVals)
                                    builder.NamedArg(k, v, null)]
            if (rxValue =~ ghost :Ghost) {
                # Note that the remixer we pass in has fresh scope. This is
                # analogous to hygenic macro expansion.
                ghost.unfold(fresh, verb, argVals, nargVals)
            } else {
                def call := builder.MethodCallExpr(rxValue, verb, argVals,
                                                   packedNamedArgs, null)
                if (rxValue.getNodeName() == "LiteralExpr" &&
                           allLiteral(argVals) &&
                           allLiteral(nargVals.getValues())) {
                    try {
                        builder.LiteralExpr(eval(call, [].asMap()), null)
                    } catch _ {
                        staticError(`Evaluated literal m``$call`` failed during mix`)
                    }
                } else { call }
            }
        }

        match =="EscapeExpr" { expr }
        # to EscapeExpr(patt :Pattern, body :Expr,
        #               catchPatt :NullOk[Pattern], catchBody :NullOk[Expr], _pos):
        #     return escape ej:
        #         # TODO: mustMatch
        #         inFreshScope(fn { evaluator.matchBind(patt, ej);
        #                           evaluator(body) })
        #     catch ejected:
        #         if (catchPatt == null):
        #             ejected
        #         else:
        #             inFreshScope(fn { evaluator.matchBind(catchPatt, ejected);
        #                               evaluator(catchBody) })

        match =="FinallyExpr" {
            def body := fresh(expr.getBody())
            def unwinder := fresh(expr.getUnwinder())
            m`try { $body } finally { $unwinder }`
        }

        match =="IfExpr" {
            # semantics.rst seems to say alt :Expr, but IfExpr._uncall() says otherwise.
            def testVal := remix(expr.getTest())
            switch (testVal) {
                match m`true` { fresh(expr.getThen()) }
                match m`false` { fresh(expr.getElse()) }
                match _ {
                    m`if ($testVal) {
                        ${remix(expr.getThen())}
                    } else {
                        ${remix(expr.getElse())}
                    }`
                }
            # } else {
            #     staticError("If-expr test did not conform to Bool")
            }
        }

        match =="SeqExpr" {
            seq([for e in (expr.getExprs()) remix(e)])
        }

        match =="CatchExpr" { expr }
        # to CatchExpr(body :Expr, catchPatt :Pattern, catchBody :Expr, _pos):
        #     return try:
        #         inFreshScope(fn { evaluator(body) })
        #     catch ex:
        #         inFreshScope(fn { evaluator.matchBind(catchPatt, ex);
        #                           evaluator(catchBody) })

        match =="ObjectExpr" {
            def asExpr := remix(expr.getAsExpr())
            def auditors := [for a in (expr.getAuditors()) remix(a)]
            def script := expr.getScript()
            traceln("Script", script)
            def methods := [for m in (script.getMethods()) withFresh(fn f {
                def patts := [for patt in (m.getPatterns()) f(patt)]
                def namedPatts := [for np in (m.getNamedPatterns()) f(np)]
                def guard := f(m.getResultGuard())
                def body := f(m.getBody())
                traceln("body scope", body.getStaticScope())
                builder."Method"(m.getDocstring(), m.getVerb(), patts,
                                 namedPatts, guard, body, null)
            })]
            traceln("Methods", methods)
            def matchers := [for m in (script.getMatchers()) withFresh(fn f {
                def patt := f(m.getPattern())
                def body := f(m.getBody())
                builder.Matcher(patt, body, null)
            })]
            # Deal with this last, so that the object's self-reference is
            # always dynamic. We can try to make it static another time.
            def name := remix(expr.getName())
            # Assign a ghost object which can be specialized as required.
            matchBind(name, makeGhostObject(methods, matchers))
            def newScript := builder.Script(null, methods, matchers, null)
            builder.ObjectExpr(expr.getDocstring(), name, asExpr, auditors,
                               newScript, null)
        }

        match =="IgnorePattern" { expr.withGuard(remix(expr.getGuard())) }

        match =="FinalPattern" { expr.withGuard(remix(expr.getGuard())) }

        match =="VarPattern" { expr.withGuard(remix(expr.getGuard())) }

        match =="ListPattern" {
            def l := [for patt in (expr.getPatterns()) remix(patt)]
            # Kernel list patterns have no tail.
            builder.ListPattern(l, null, null)
        }

        match =="ViaPattern" {
            builder.ViaPattern(remix(expr.getExpr()),
                               remix(expr.getPattern()))
        }
    }
    return [newExpr, locals]


def mix(expr, baseScope) as DeepFrozen:
    def [rv, _] := mainMix(expr, baseScope, [].asMap())
    return rv


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

def main(_argv :List[Str]) as DeepFrozen:
    def factorial := m`def fact(x :Int) {
        return if (x < 2) { x } else { x * fact(x - 1) }
    }; fact(5)`.expand()
    def mixed := mix(factorial, safeScope)
    traceln("Mixed", mixed)
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
    def mixed2 := mix(bf, safeScope)
    traceln("Mixed", mixed2)
