# goal: debugger a la pdb.set_trace() or debug() in js, R

import "unittest" =~ [=> unittest]
import "lib/monte/monte_parser" =~ [
    => parseModule :DeepFrozen,
]

import "doctests" =~ [=> suite]
exports (main, makeEvaluator)

def Scope :DeepFrozen := Map[Str, Any]  # TODO map to binding
def emptyScope :DeepFrozen := [].asMap() :Scope
def Expr :DeepFrozen := astBuilder.getExprGuard()
def Pattern :DeepFrozen := astBuilder.getPatternGuard()

def makeM :DeepFrozen := m`0`._uncall()[0]
object noSpecimen as DeepFrozen {}


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


def makeEvaluator(var scopes: List[Scope]) as DeepFrozen:
    # cribbed from
    # https://github.com/monte-language/typhon/blob/master/typhon/nano/interp.py#L276

    def var locals := emptyScope
    def var specimen := noSpecimen
    def var patternFailure := throw
    def inFreshScope(thunk):
        scopes := [locals] + scopes
        locals := emptyScope
        return try:
            thunk()
        finally:
            locals := scopes[0]
            scopes := scopes.slice(1)

    def lookupBinding(name :Str):
        def key := "&&" + name
        if (locals.contains(key)):
            return locals[key]

        for scope in (scopes):
            if (scope.contains(key)):
                return scope[key]
        throw(`not bound: $name`)

    return object evaluator:
        to run(expr :Expr):
            def unwrap(uncall :List):
                return if (uncall =~ [==makeM, _, args, _]) {
                    args[0]._uncall()
                } else { uncall }

            def [_, =="run", args, _namedArgs] := unwrap(expr._uncall())
            # traceln(`interp: ${expr.getNodeName()}($args)`)

            return M.call(evaluator, expr.getNodeName(), args, [].asMap())

        to getScope():
            "just for testing?"
            return locals

        to LiteralExpr(value, _pos):
            return value

        to BindingExpr(noun :Expr, _pos):
            return lookupBinding(noun.getName())

        to NounExpr(name :Str, _pos):
            return lookupBinding(name).get().get()

        to AssignExpr(lval :Expr, rhs :Expr, _pos):
            def slot := lookupBinding(lval.getName()).get()
            def val := evaluator(rhs)
            slot.put(val)
            return val

        to DefExpr(patt :Pattern, exExpr :NullOk[Expr], rhs :Expr, _pos):
            def ex := if (exExpr == null) { throw } else { evaluator(exExpr) }
            def val := evaluator(rhs)
            evaluator.matchBind(patt, val, "ej" => ex)
            return val

        to HideExpr(inner :Expr, _pos):
            return inFreshScope(fn { evaluator(inner) })

        to MethodCallExpr(rxExpr :Expr, verb: Str, args, nargs, _pos):
            def rxValue := evaluator(rxExpr)
            def argVals := [for arg in (args) evaluator(arg) ]
            def nargVals := [for name => expr in (nargs) name => evaluator(expr)]
            return M.call(rxValue, verb, argVals, nargVals)

        to EscapeExpr(patt :Pattern, body :Expr,
                      catchPatt :NullOk[Pattern], catchBody :NullOk[Expr], _pos):
            return escape ej:
                # TODO: mustMatch
                inFreshScope(fn { evaluator.matchBind(patt, ej);
                                  evaluator(body) })
            catch ejected:
                if (catchPatt == null):
                    ejected
                else:
                    inFreshScope(fn { evaluator.matchBind(catchPatt, ejected);
                                      evaluator(catchBody) })

        to FinallyExpr(body :Expr, tail :Expr, _pos):
            # bug in semantics.rst? it says the value of the tail expr is returned
            try:
                return inFreshScope(fn { evaluator(body) })
            finally:
                inFreshScope(fn { evaluator(tail) })

        to IfExpr(test: Expr, cons :Expr, alt :NullOk[Expr], _pos):
            # semantics.rst seems to say alt :Expr, but IfExpr._uncall() says otherwise.
            def testVal := evaluator(test)
            if (testVal =~ outcome :Bool):
                return if (outcome):
                    inFreshScope(fn { evaluator(cons) })
                else:
                    if (alt != null):
                        inFreshScope(fn { evaluator(alt) })
                    else:
                        null
            else:
                throw(["not a boolean", testVal])

        to SeqExpr(exprs: List[Expr], _pos):
            var result := null
            for expr in (exprs):
                result := evaluator(expr)
            return result

        to CatchExpr(body :Expr, catchPatt :Pattern, catchBody :Expr, _pos):
            return try:
                inFreshScope(fn { evaluator(body) })
            catch ex:
                inFreshScope(fn { evaluator.matchBind(catchPatt, ex);
                                  evaluator(catchBody) })

        to ObjectExpr(_doc :NullOk[Str], namePatt :Pattern, _objectAs :NullOk[Any],
                      _implements_ :List, script, _pos):
            def name := if (namePatt.getNodeName() == "IgnorePattern") { "_" } else {
                namePatt.getNoun().getName()
            }
            def [p, r] := Ref.promise()
            evaluator.matchBind(namePatt, p)
            def obj := makeInterpObject(_doc, name, script, [locals] + scopes, makeEvaluator)
            r.resolve(obj)
            return obj

        to matchBind(patt :Pattern, val, => ej := throw):
            def oldSpecimen := specimen
            def oldPatternFailure := patternFailure
            specimen := val
            patternFailure := ej
            def [_, =="run", args, _namedArgs] := patt._uncall()
            # traceln(`matchBind: $specimen =~ ${patt.getNodeName()}($args})`)
            try:
                M.call(evaluator, patt.getNodeName(), args, [].asMap())
            finally:
                specimen := oldSpecimen
                patternFailure := oldPatternFailure

        to guardOpt(guardOpt :NullOk[Expr]):
            return if (guardOpt != null):
                evaluator(guardOpt)
            else:
                null

        to IgnorePattern(guardOpt, _pos):
            if (evaluator.guardOpt(guardOpt) =~ guard ? (guard != null)):
                guard.coerce(specimen, patternFailure)

        to BindingPattern(noun :Expr, _pos):
            def key := "&&" + noun.getName()
            locals with=(key, specimen)

        to namePattern(noun :Expr, guardExprOpt :NullOk[Expr], slotMaker):
            def key := "&&" + noun.getName()
            # TODO: check that name is not already taken
            def guardOpt := evaluator.guardOpt(guardExprOpt)
            def val := _slotToBinding(slotMaker(guardOpt, specimen, patternFailure),
                                      # should this 2nd arg be patternFailure too?
                                      null)
            locals with=(key, val)

        to FinalPattern(noun, guardExprOpt :NullOk[Expr], _pos):
            evaluator.namePattern(noun, guardExprOpt, _makeFinalSlot)

        to VarPattern(noun, guardExprOpt :NullOk[Expr], _pos):
            evaluator.namePattern(noun, guardExprOpt, _makeVarSlot)

        to ListPattern(patts :List[Pattern], _tail :Void, _pos):
            # Kernel list patterns have no tail.
            List.coerce(specimen, patternFailure)
            if (patts.size() != specimen.size()):
                throw.eject(patternFailure,
                            `Failed list pattern (needed ${patts.size()}, got ${specimen.size()})`)
            def ej := patternFailure
            for ix in (0..!patts.size()):
                evaluator.matchBind(patts[ix], specimen[ix], "ej" => ej)

        to ViaPattern(trans :Expr, patt :Pattern, _pos):
            def ej := patternFailure
            def v := evaluator(trans)
            def newSpec := v(specimen, ej)
            # semantics could be clearer that we use the same ejector below.
            evaluator.matchBind(patt, newSpec, "ej" => ej)


def testFor(case):
    def [=>section, =>lineno, =>source, =>want] | _ := case

    def fixAST := want.contains("m`").pick(fn ast { ast.canonical() },
                                           fn v { v })

    return object test:
        to _printOn(p):
            p.print(`<test: $section:$lineno>`)

        to run(assert):
            def e := makeEvaluator([safeScope])

            def expected := fixAST(eval(want, safeScope))
            def input := ::"m``".fromStr(source).expand()
            def actual := e(input)

            return when (actual) ->
                assert.equal(fixAST(actual), fixAST(expected))

unittest([for case in (suite) testFor(case)])


def main(argv :List[Str], =>makeFileResource) as DeepFrozen:
    # should start with 1, but argv[0] is "eval" rather than the script name
    var done := 2
    def go := fn ast { traceln(makeEvaluator([safeScope])(ast.expand())) }
    while (done < argv.size()):
        def todo := argv.slice(done)
        traceln(["done", done, "todo", todo])
        if (todo =~ [=="--module", filename] + _):
            traceln("evaluting module:", filename)
            when(def src := makeFileResource(filename).getContents()) ->
                traceln("got source")
                go(parseModule(src))  # not so fast, buster! see #153
            catch oops:
                trace.exception(oops)
            done += 2
        else if (todo =~ [src] + _):
            go(::"m``".fromStr(src))
            done += 1
