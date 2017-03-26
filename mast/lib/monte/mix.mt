import "unittest" =~ [=> unittest]
exports (main, mix)

# The partial evaluator.

# We must reify ejectors in order to permit pauses in:
# m`escape ej { pause(); ej() }`

# goal: debugger a la pdb.set_trace() or debug() in js, R

def Scope :DeepFrozen := Map[Str, Binding]
# def emptyScope :DeepFrozen := [].asMap()
def Expr :DeepFrozen := astBuilder.getExprGuard()
def Pattern :DeepFrozen := astBuilder.getPatternGuard()

object noSpecimen as DeepFrozen {}
object dynamic as DeepFrozen {}


def makeInterpObject(_doc, _name, script, scopes: List[Scope], makeEvaluator) as DeepFrozen:
    # KLUDGE: pass makeEvaluator to avoid fwd ref
    # TODO: fqdn?
    # TODO: auditors
    # TODO: def miranda := eval(`object $name {}`, [].asMap())
    def dispatch := [for m in (script.getMethods())
                     [m.getVerb(), m.getPatterns().size()] => m]

    def runMethod(meth, args, _namedArgs):
        def e := makeEvaluator(scopes)
        def ps := meth.getPatterns()
        for ix in (0..!ps.size()):
            e.matchBind(ps[ix], args[ix])
        # TODO: namedargs
        # TODO: result guard
        def v := e(meth.getBody())
        return v

    return object interpObject:
        to _respondsTo(verb, arity):
            return dispatch.contains([verb, arity])

        match [verb, args, nargs]:
            # TODO: noSuchMethod
            def atom := [verb, args.size()]
            runMethod(dispatch[atom], args, nargs)
            #catch _:
            #    # TODO: matchers
            #    # TODO: miranda
            #    M.call(miranda, verb, args, nargs)

def allLiteral(exprs :List[Expr]) :Bool as DeepFrozen:
    for expr in (exprs):
        if (expr.getNodeName() != "LiteralExpr"):
            return false
    return true

def mainMix(expr :Expr, baseScope :Map, var locals :Map) as DeepFrozen:
    # cribbed from
    # https://github.com/monte-language/typhon/blob/master/typhon/nano/interp.py#L276

    var specimen := noSpecimen
    var patternFailure := throw

    def builder := ::"m``".getAstBuilder()

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

    def opt(subExpr):
        return if (subExpr == null) { null } else { remix(subExpr) }

    def matchBind(patt :Pattern, val, => ej := throw):
        def oldSpecimen := specimen
        def oldPatternFailure := patternFailure
        specimen := val
        patternFailure := ej

        try:
            switch (patt.getNodeName()):
                match =="IgnorePattern":
                    def guard := opt(patt.getGuard())
                    if (guard != null):
                        guard.coerce(specimen, patternFailure)

                match =="BindingPattern":
                    def key := "&&" + patt.getNoun().getName()
                    locals with= (key, specimen)

                match =="FinalPattern":
                    # TODO: check that name is not already taken
                    def key := "&&" + patt.getNoun().getName()
                    def guard := opt(patt.getGuard())
                    def val := _slotToBinding(_makeFinalSlot(guard, specimen, patternFailure),
                                              # should this 2nd arg be patternFailure too?
                                              null)
                    locals with= (key, val)

                match =="VarPattern":
                    # TODO: check that name is not already taken
                    def key := "&&" + patt.getNoun().getName()
                    def guard := opt(patt.getGuard())
                    def val := _slotToBinding(_makeVarSlot(guard, specimen, patternFailure),
                                              # should this 2nd arg be patternFailure too?
                                              null)
                    locals with= (key, val)

                match =="ListPattern":
                    # Kernel list patterns have no tail.
                    def patts := patt.getPatterns()
                    def l :List exit patternFailure := specimen
                    if (patts.size() != l.size()):
                        throw.eject(patternFailure,
                                    `Failed list pattern (needed ${patts.size()}, got ${l.size()})`)
                    def ej := patternFailure
                    for ix => patt in (patts):
                        matchBind(patt, specimen[ix], => ej)

                match =="ViaPattern":
                    def ej := patternFailure
                    def v := remix(patt.getExpr())
                    def newSpec := v(specimen, ej)
                    # semantics could be clearer that we use the same ejector below.
                    matchBind(patt.getPattern(), newSpec, => ej)
        finally:
            specimen := oldSpecimen
            patternFailure := oldPatternFailure

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
            def exExpr :NullOk[Expr] := expr.getExit()
            def ej := if (exExpr == null) { m`throw` } else { remix(exExpr) }
            matchBind(expr.getPattern(), val, => ej)
            val
        }

        match =="HideExpr" { fresh(expr.getBody()) }

        match =="MethodCallExpr" {
            def rxValue := remix(expr.getReceiver())
            def argVals := [for arg in (expr.getArgs()) remix(arg)]
            def nargVals := [for name => arg in (expr.getNamedArgs())
                             remix(name) => remix(arg)]
            def packedNamedArgs := [for k => v in (nargVals)
                                    builder.NamedArg(k, v, null)]
            def call := builder.MethodCallExpr(rxValue, expr.getVerb(),
                                               argVals, packedNamedArgs, null)
            if (rxValue.getNodeName() == "LiteralExpr" &&
                allLiteral(argVals) && allLiteral(nargVals.getValues())) {
                try {
                    builder.LiteralExpr(eval(call, [].asMap()), null)
                } catch _ {
                    staticError(`Evaluated literal m``$call`` failed during mix`)
                }
            } else { call }
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

        match =="FinallyExpr" { expr }
        # to FinallyExpr(body :Expr, tail :Expr, _pos):
        #     # bug in semantics.rst? it says the value of the tail expr is returned
        #     try:
        #         return inFreshScope(fn { evaluator(body) })
        #     finally:
        #         inFreshScope(fn { evaluator(tail) })

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

        match =="ObjectExpr" { expr }
        # to ObjectExpr(_doc :NullOk[Str], namePatt :Pattern, _objectAs :NullOk[Any],
        #               _implements_ :List, script, _pos):
        #     def name := if (namePatt.getNodeName() == "IgnorePattern") { "_" } else {
        #         namePatt.getNoun().getName()
        #     }
        #     # Forward-declare the object so that we can tie the recursive
        #     # knot. As a consequence, the object isn't callable during
        #     # match-bind...
        #     def obj
        #     evaluator.matchBind(namePatt, obj)
        #     bind obj := makeInterpObject(_doc, name, script, [locals] + scopes, makeEvaluator)
        #     return obj
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
