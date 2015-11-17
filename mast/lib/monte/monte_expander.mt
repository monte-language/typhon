# Maybe Python isn't so bad after all.
object zip as DeepFrozen:
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


def reversed(it) as DeepFrozen:
    def items := __makeList.fromIterable(it)
    return items.reverse()

def buildQuasi(builder, name, inputs) as DeepFrozen:
    def parts := ["parts" => [].diverge(),
                  "expr" => [].diverge(),
                  "patt" => [].diverge()]
    for [typ, node, span] in inputs:
        if (typ == "expr"):
            parts["parts"].push(builder.MethodCallExpr(
                builder.NounExpr(name, span),
                "valueHole",
                [builder.LiteralExpr(parts["expr"].size(), span)], [],
                 span))
            parts["expr"].push(node)
        else if (typ == "patt"):
            parts["parts"].push(builder.MethodCallExpr(
                builder.NounExpr(name, span),
                "patternHole",
                [builder.LiteralExpr(parts["patt"].size(), span)], [],
                 span))
            parts["patt"].push(node)
        else if (typ == "text"):
            parts["parts"].push(node)
    var ps := []
    for p in parts:
        ps with= (p.snapshot())
    return ps

def putVerb(verb, fail, span) as DeepFrozen:
    switch (verb):
        match =="get":
            return "put"
        match =="run":
            return "setRun"
        match _:
            fail(["Unsupported verb for assignment", span])

def renameCycles(node, renamings, builder) as DeepFrozen:
    def renamer(node, maker, args, span):
        return switch (node.getNodeName()) {
            match =="NounExpr" {
                renamings.fetch(node.getName(), fn {node})
            }
            match _ {
                M.call(maker, "run", args + [span], [].asMap())
            }
        }
    return node.transform(renamer)


def ifAnd(ast, maker, args, span) as DeepFrozen:
    "Expand and-expressions inside if-expressions."

    if (ast.getNodeName() == "IfExpr"):
        def [test, consequent, alternative] := args

        if (test.getNodeName() == "AndExpr"):
            def left := test.getLeft()
            def right := test.getRight()

            # The name occurrence check is not required.
            return maker(left, maker(right, consequent, alternative, span),
                         alternative, span)

    return M.call(maker, "run", args + [span], [].asMap())


def ifOr(ast, maker, args, span) as DeepFrozen:
    "Expand or-expressions inside if-expressions."

    if (ast.getNodeName() == "IfExpr"):
        def [test, consequent, alternative] := args

        if (test.getNodeName() == "OrExpr"):
            def left := test.getLeft()
            def right := test.getRight()

            # left must not define any name used by right; otherwise, if
            # left's test fails, right's test will try to access undefined
            # names.
            if ((left.getStaticScope().outNames() &
                 right.getStaticScope().namesUsed()).size() == 0):
                return maker(left, consequent, maker(right, consequent,
                                                     alternative, span), span)

    return M.call(maker, "run", args + [span], [].asMap())


def modPow(ast, maker, args, span) as DeepFrozen:
    "Expand modular exponentation method calls."

    if (ast.getNodeName() == "MethodCallExpr"):
        escape ej:
            def [receiver, verb ? (verb :Str == "mod"), [m], []] exit ej := args
            if (receiver.getNodeName() == "MethodCallExpr"):
                def x := receiver.getReceiver()
                def verb ? (verb :Str == "pow") exit ej := receiver.getVerb()
                def [e] exit ej := receiver.getArgs()
                return maker(x, "modPow", [e, m], [], span)

    return M.call(maker, "run", args + [span], [].asMap())

# Commented out since there's no global AST builder here at the moment. The
# code worked fine when it was in monte_optimizer though. ~ C.
# def testModPow(assert):
#     def ast := a.MethodCallExpr(a.MethodCallExpr(a.LiteralExpr(7, null), "pow",
#                                                  [a.LiteralExpr(11, null)], [],
#                                                  null),
#                                 "mod", [a.LiteralExpr(13, null)], null)
#     def result := a.MethodCallExpr(a.LiteralExpr(7, null), "modPow",
#                                    [a.LiteralExpr(11, null), a.LiteralExpr(13,
#                                    null)], [], null)
#     assert.equal(ast.transform(modPow), result)
#
# unittest([testModPow])


def expand(node, builder, fail) as DeepFrozen:

    def nounFromScopeName(n, span):
        if (n =~ _ :Str):
            return builder.NounExpr(n, span)
        return n

    def emitList(items, span):
        return builder.MethodCallExpr(
            builder.NounExpr("__makeList", span),
            "run", items, [], span)

    def emitMap(items, span):
        return builder.MethodCallExpr(
            builder.NounExpr("__makeMap", span),
            "fromPairs", [emitList(items, span)], [], span)

    def makeSlotPatt(n, span):
        return builder.ViaPattern(builder.NounExpr("__slotToBinding", span),
             builder.BindingPattern(n, span), span)

    def makeFn(doc, args, body, span):
        return builder.ObjectExpr(doc,
             builder.IgnorePattern(null, span), null, [],
             builder.Script(null,
                 [builder."Method"(null, "run",
                                   args,
                                   [], null, body, span)], [], span),
             span)

    def expandMatchBind(args, span, fail):
        def [spec, patt] := args
        def pattScope := patt.getStaticScope()
        def specScope := spec.getStaticScope()
        if ((pattScope.outNames() & specScope.namesUsed()).size() > 0):
            fail(["Use on left isn't really in scope of matchbind pattern: ${conflicts.getKeys()}", span])
        def [sp, ejector, result, problem, broken] :=  [
            builder.TempNounExpr("sp", span),
            builder.TempNounExpr("fail", span),
            builder.TempNounExpr("ok", span),
            builder.TempNounExpr("problem", span),
            builder.TempNounExpr("broken", span)
            ]

        var bindingpatts := []
        var bindingexprs := []
        for nn in pattScope.outNames():
            def noun := builder.NounExpr(nn, span)
            bindingpatts with= (builder.BindingPattern(noun, span))
            bindingexprs with= (builder.BindingExpr(noun, span))

        return builder.SeqExpr([
            builder.DefExpr(builder.FinalPattern(sp, null, span), null, spec, span),
            builder.DefExpr(builder.ListPattern([builder.FinalPattern(result, null, span)] +
                                        bindingpatts, null, span),
                null,
                builder.EscapeExpr(
                    builder.FinalPattern(ejector, null, span),
                    builder.SeqExpr([
                        builder.DefExpr(patt, ejector, sp, span),
                        emitList([builder.NounExpr("true", span)] +
                            bindingexprs, span)], span),
                    builder.FinalPattern(problem, null, span),
                    builder.SeqExpr([
                        builder.DefExpr(builder.ViaPattern(
                            builder.NounExpr("__slotToBinding", span),
                        builder.BindingPattern(broken, span), span),
                            null,
                            builder.MethodCallExpr(builder.NounExpr("Ref", span),
                                "broken", [problem], [], span), span),
                            emitList([builder.NounExpr("false", span)] +
                                [builder.BindingExpr(broken, span)] * bindingexprs.size(), span)],
                                span),
                    span),
                span),
            result],
            span)

    def expandLogical(leftNames, rightNames, f, span):
        var bindingpatts := []
        var bindingexprs := []
        for n in leftNames | rightNames:
            bindingpatts with= (builder.BindingPattern(nounFromScopeName(n, span), span))
            bindingexprs with= (builder.BindingExpr(nounFromScopeName(n, span), span))

        def result := builder.TempNounExpr("ok", span)
        def success := emitList([builder.NounExpr("true", span)] +
            bindingexprs, span)
        def failure := builder.MethodCallExpr(builder.NounExpr("_booleanFlow", span),
            "failureList", [builder.LiteralExpr(bindingexprs.size(), span)], [], span)
        return builder.SeqExpr([
            builder.DefExpr(
                builder.ListPattern([builder.FinalPattern(result, null, span)] +
                    bindingpatts, null, span),
                null,
                f(success, failure), span),
                result], span)

    def expandCallAssign([rcvr, verb, margs, namedArgs], right, fail, span):
        def ares := builder.TempNounExpr("ares", span)
        return builder.SeqExpr([
            builder.MethodCallExpr(rcvr, putVerb(verb, fail, span),
                margs + [builder.DefExpr(builder.FinalPattern(ares,
                        null, span),
                null, right, span)], [], span),
            ares], span)

    def expandVerbAssign(verb, target, vargs, fail, span):
        def [_, _, leftargs, _] := target._uncall()
        switch (target.getNodeName()):
            match =="NounExpr":
                return builder.AssignExpr(target, builder.MethodCallExpr(target, verb, vargs, [], span), span)
            match =="MethodCallExpr":
                def [rcvr, methverb, margs, mnamedargs, lspan] := leftargs
                def recip := builder.TempNounExpr("recip", lspan)
                def seq := [builder.DefExpr(builder.FinalPattern(recip,
                                null, lspan),
                            null, rcvr, lspan)].diverge()
                def setArgs := [].diverge()
                for arg in margs:
                    def a := builder.TempNounExpr("arg", span)
                    seq.push(builder.DefExpr(builder.FinalPattern(a, null, lspan),
                         null, arg, lspan))
                    setArgs.push(a)
                seq.extend(expandCallAssign([recip, methverb, setArgs.snapshot(), []], builder.MethodCallExpr(builder.MethodCallExpr(recip, methverb, setArgs.snapshot(), [], span), verb, vargs, [], span), fail, span).getExprs())
                return builder.SeqExpr(seq.snapshot(), span)
            match =="QuasiLiteralExpr":
                fail(["Can't use update-assign syntax on a \"$\"-hole. Use explicit \":=\" syntax instead.", span])
            match =="QuasiPatternExpr":
                fail(["Can't use update-assign syntax on a \"@\"-hole. Use explicit \":=\" syntax instead.", span])
            match _:
                fail(["Can only update-assign nouns and calls", span])

    def expandMessageDesc(doco, verb, paramDescs, resultGuard, span):
        def docExpr := if (doco == null) {builder.NounExpr("null", span)} else {builder.LiteralExpr(doco, span)}
        def guardExpr := if (resultGuard == null) {builder.NounExpr("Any", span)} else {
            resultGuard}
        return builder.HideExpr(builder.MethodCallExpr(builder.NounExpr("_makeMessageDesc", span),
            "run", [docExpr, builder.LiteralExpr(verb, span),
                 emitList(paramDescs, span), guardExpr], [],
             span), span)

    def expandObject(doco, name, asExpr, auditors, [xtends, methods, matchers], span):
        # Easy case: There's no object being extended, so the object's fine
        # as-is. Just assemble it.
        if (xtends == null):
            return builder.ObjectExpr(doco, name, asExpr, auditors,
                                      builder.Script(null, methods, matchers,
                                                     span),
                                      span)

        def p := builder.TempNounExpr("pair", span)
        def superExpr := if (xtends.getNodeName() == "NounExpr") {
            builder.DefExpr(builder.BindingPattern(builder.NounExpr("super", span), span), null,
                builder.BindingExpr(xtends, span), span)
        } else {
            builder.DefExpr(builder.FinalPattern(builder.NounExpr("super", span), null, span), null, xtends, span)
        }

        # We need to get the result of the asExpr into the guard for the
        # overall defExpr. If (and only if!) we have the auditor as a single
        # noun (e.g. DeepFrozen), then we should use it directly; otherwise,
        # put it into an antecedent DefExpr and reference that defined name. A
        # similar but subtler logic was used in superExpr. ~ C.
        if (asExpr == null):
            return builder.DefExpr(name, null, builder.HideExpr(builder.SeqExpr([superExpr,
                builder.ObjectExpr(doco, name, null, auditors, builder.Script(null, methods,
                    matchers + [builder.Matcher(builder.FinalPattern(p, null, span),
                         builder.MethodCallExpr(builder.NounExpr("M", span), "callWithMessage",
                              [builder.NounExpr("super", span), p], [], span), span)], span), span)], span),
                span), span)
        else if (asExpr.getNodeName() == "NounExpr"):
            return builder.DefExpr(name.withGuard(asExpr), null, builder.HideExpr(builder.SeqExpr([superExpr,
                builder.ObjectExpr(doco, name, asExpr, auditors, builder.Script(null, methods,
                    matchers + [builder.Matcher(builder.FinalPattern(p, null, span),
                         builder.MethodCallExpr(builder.NounExpr("M", span), "callWithMessage",
                              [builder.NounExpr("super", span), p], [], span), span)], span), span)], span),
                span), span)
        else:
            def auditorNoun := builder.TempNounExpr("auditor", span)
            def auditorExpr := builder.DefExpr(builder.FinalPattern(auditorNoun, null, span),
                                               null, asExpr, span)
            # The auditorExpr must be evaluated early enough to be used as the
            # definition guard. Unfortunately, I cannot think of any simple
            # nor convoluted way to evaluate the superExpr first while still
            # scoping it correctly. ~ C.
            return builder.HideExpr(builder.SeqExpr([auditorExpr,
                builder.DefExpr(name.withGuard(auditorNoun), null, builder.HideExpr(builder.SeqExpr([superExpr,
                    builder.ObjectExpr(doco, name, auditorNoun, auditors, builder.Script(null, methods,
                        matchers + [builder.Matcher(builder.FinalPattern(p, null, span),
                             builder.MethodCallExpr(builder.NounExpr("M", span), "callWithMessage",
                                  [builder.NounExpr("super", span), p], [], span), span)], span), span)], span),
                    span), span)], span), span)


    def expandInterface(doco, name, guard, xtends, mplements, messages, span):
        def verb := if (guard == null) {"run"} else {"makePair"}
        def docExpr := if (doco == null) { builder.NounExpr("null", span) } else {builder.LiteralExpr(doco, span)}
        def ifaceExpr := builder.HideExpr(builder.MethodCallExpr(
            builder.NounExpr("_makeProtocolDesc", span), verb,
                [docExpr, builder.MethodCallExpr(
                    builder.MethodCallExpr(
                        builder.MetaContextExpr(span),
                        "getFQNPrefix", [], [], span),
                    "add", [builder.LiteralExpr(name.getNoun().getName() + "_T", span)], [], span),
                emitList(xtends, span),
                emitList(mplements, span),
                emitList(messages, span)], [], span), span)
        if (guard == null):
            return builder.DefExpr(name, null, ifaceExpr, span)
        else:
            return builder.MethodCallExpr(
                builder.DefExpr(builder.ListPattern([name, guard],
                                                    null, span),
                         null, ifaceExpr, span),
                "get", [builder.LiteralExpr(0, span)], [], span)

    def validateFor(left, right, fail, span):
        if ((left.outNames() & right.namesUsed()).size() > 0):
            fail(["Use on right isn't really in scope of definition", span])
        if ((right.outNames() & left.namesUsed()).size() > 0):
            fail(["Use on left would get captured by definition on right", span])

    def expandFor(optKey, value, coll, block, catchPatt, catchBlock, span):
        def key := if (optKey == null) {builder.IgnorePattern(null, span)} else {optKey}
        validateFor(key.getStaticScope() + value.getStaticScope(),
                    coll.getStaticScope(), fail, span)
        def fTemp := builder.TempNounExpr("validFlag", span)
        def kTemp := builder.TempNounExpr("key", span)
        def vTemp := builder.TempNounExpr("value", span)
        def obj := builder.ObjectExpr("For-loop body",
            builder.IgnorePattern(null, span), null, [], builder.Script(
                null,
                [builder."Method"(null, "run",
                    [builder.FinalPattern(kTemp, null, span),
                     builder.FinalPattern(vTemp, null, span)],
                    [], null,
                builder.SeqExpr([
                    builder.MethodCallExpr(
                        builder.NounExpr("_validateFor", span),
                        "run", [fTemp], [], span),
                    builder.EscapeExpr(
                        builder.FinalPattern(builder.NounExpr("__continue", span), null, span),
                        builder.SeqExpr([
                            builder.DefExpr(key, null, kTemp, span),
                            builder.DefExpr(value, null, vTemp, span),
                            block,
                            builder.NounExpr("null", span)
                        ], span),
                    null, null, span),
                ], span), span)],
            [], span), span)
        return builder.EscapeExpr(
            builder.FinalPattern(builder.NounExpr("__break", span), null, span),
            builder.SeqExpr([
                builder.DefExpr(builder.VarPattern(fTemp, null, span), null,
                    builder.NounExpr("true", span), span),
                builder.FinallyExpr(
                    builder.MethodCallExpr(builder.NounExpr("__loop", span),
                        "run", [coll, obj], [], span),
                    builder.AssignExpr(fTemp, builder.NounExpr("false", span), span), span),
                builder.NounExpr("null", span)
            ], span),
            catchPatt,
            catchBlock,
            span)

    def expandComprehension(optKey, value, coll, filter, exp, collector, span):
        def key := if (optKey == null) {builder.IgnorePattern(null, span)} else {optKey}
        validateFor(exp.getStaticScope(), coll.getStaticScope(), fail, span)
        validateFor(key.getStaticScope() + value.getStaticScope(), coll.getStaticScope(), fail, span)
        def fTemp := builder.TempNounExpr("validFlag", span)
        def kTemp := builder.TempNounExpr("key", span)
        def vTemp := builder.TempNounExpr("value", span)
        def skip := builder.TempNounExpr("skip", span)
        def kv := []
        def maybeFilterExpr := if (filter != null) {
            builder.IfExpr(filter, exp, builder.MethodCallExpr(skip, "run", [], [], span), span)
        } else {exp}
        def obj := builder.ObjectExpr("For-loop body",
            builder.IgnorePattern(null, span), null, [], builder.Script(
                null,
                [builder."Method"(null, "run",
                    [builder.FinalPattern(kTemp, null, span),
                     builder.FinalPattern(vTemp, null, span),
                     builder.FinalPattern(skip, null, span)],
                    [], null,
                builder.SeqExpr([
                    builder.MethodCallExpr(
                        builder.NounExpr("_validateFor", span),
                        "run", [fTemp], [], span),
                    builder.DefExpr(key, null, kTemp, span),
                    builder.DefExpr(value, null, vTemp, span),
                    maybeFilterExpr
                ], span), span)],
            [], span), span)
        return builder.SeqExpr([
            builder.DefExpr(builder.VarPattern(fTemp, null, span), null,
                builder.NounExpr("true", span), span),
            builder.FinallyExpr(
                builder.MethodCallExpr(builder.NounExpr(collector, span),
                    "run", [coll, obj], [], span),
                builder.AssignExpr(fTemp, builder.NounExpr("false", span), span), span),
            ], span)

    def expandTransformer(node, maker, args, span):
        # traceln(`expander: ${node.getNodeName()}: Expanding $node`)

        def nodeName := node.getNodeName()
        if (nodeName == "LiteralExpr"):
            return builder.LiteralExpr(args[0], span)

        else if (nodeName == "NounExpr"):
            def [name] := args
            return builder.NounExpr(name, span)
        else if (nodeName == "SlotExpr"):
            def [noun] := args
            return builder.MethodCallExpr(builder.BindingExpr(noun, span), "get", [], [], span)
        else if (nodeName == "BindingExpr"):
            def [noun] := args
            return builder.BindingExpr(noun, span)
        else if (nodeName == "MethodCallExpr"):
            def [rcvr, verb, arglist, namedArgs] := args
            return builder.MethodCallExpr(rcvr, verb, arglist, namedArgs, span)
        else if (nodeName == "NamedArg"):
            return builder.NamedArg(args[0], args[1], span)
        else if (nodeName == "NamedArgExport"):
            def [val] := args
            def orig := node.getValue()
            def name := if (orig.getNodeName() == "BindingExpr") {
                "&&" + orig.getNoun().getName()
            } else if (orig.getNodeName() == "SlotExpr") {
                "&" + orig.getNoun().getName()
            } else {
                orig.getName()
            }
            return builder.NamedArg(builder.LiteralExpr(name, span), val, span)
        else if (nodeName == "ListExpr"):
            def [items] := args
            return emitList(items, span)
        else if (nodeName == "MapExpr"):
            def [assocs] := args
            var lists := []
            for a in assocs:
                lists with= (emitList(a, span))
            return builder.MethodCallExpr(
                builder.NounExpr("__makeMap", span), "fromPairs",
                [emitList(lists, span)], [], span)
        else if (nodeName == "MapExprAssoc"):
            return args
        else if (nodeName == "MapExprExport"):
            def [subnode] := args
            def [submaker, subargs, subspan, _] := subnode._uncall()
            def n := node.getValue()
            def subnodeName := n.getNodeName()
            if (subnodeName == "NounExpr"):
                return [builder.LiteralExpr(n.getName(), span), subnode]
            else if (subnodeName == "SlotExpr"):
                return [builder.LiteralExpr("&" + n.getNoun().getName(), span), subnode]
            else if (subnodeName == "BindingExpr"):
                return [builder.LiteralExpr("&&" + n.getNoun().getName(), span), subnode]

        else if (nodeName == "QuasiText"):
            def [text] := args
            return ["text", builder.LiteralExpr(text, span), span]
        else if (nodeName == "QuasiExprHole"):
            def [expr] := args
            return ["expr", expr, span]
        else if (nodeName == "QuasiPatternHole"):
            def [patt] := args
            return ["patt", patt, span]
        else if (nodeName == "QuasiParserExpr"):
            def [name, quasis] := args
            def qprefix := if (name == null) {"simple"} else {name}
            def qname := qprefix + "__quasiParser"
            def [parts, exprs, _] := buildQuasi(builder, qname, quasis)
            return builder.MethodCallExpr(
                builder.MethodCallExpr(
                    builder.NounExpr(qname, span), "valueMaker",
                    [emitList(parts, span)], [], span),
                "substitute",
                [emitList(exprs, span)], [], span)
        else if (nodeName == "Module"):
            def [importsList, exportsList, expr] := args
            def exportExpr := emitMap([for noun in (exportsList)
                               emitList([builder.LiteralExpr(noun.getName(),
                                                    noun.getSpan()), noun],
                                        span)], span)
            def body := builder.SeqExpr([expr, exportExpr], span)
            def DF := builder.NounExpr("DeepFrozen", span)
            def DFMap := builder.MethodCallExpr(builder.NounExpr("Map", span),
                "get", [builder.NounExpr("Str", span),
                        builder.NounExpr("DeepFrozen", span)], [], span)
            return builder.ObjectExpr(null,
                builder.IgnorePattern(null, span),
                builder.NounExpr("DeepFrozen", span), [],
                builder.Script(null,
                     [builder."Method"(null, "run", [], importsList, DFMap, body, span)],
                     [], span), span)
        else if (nodeName == "SeqExpr"):
            def [exprs] := args
            #XXX some parsers have emitted nested SeqExprs, should that
            #flattening be done here or in the parser?
            return builder.SeqExpr(exprs, span)
        else if (nodeName == "CurryExpr"):
            def [receiver, verb, isSend] := args
            return builder.MethodCallExpr(
                builder.NounExpr("_makeVerbFacet", span),
                "curryCall",
                [receiver, builder.LiteralExpr(verb, span)], [],
                span)
        else if (nodeName == "GetExpr"):
            def [receiver, index] := args
            return builder.MethodCallExpr(receiver, "get", index, [], span)
        else if (nodeName == "FunCallExpr"):
            def [receiver, fargs, namedArgs] := args
            return builder.MethodCallExpr(receiver, "run", fargs, namedArgs, span)
        else if (nodeName == "FunSendExpr"):
            def [receiver, fargs, namedArgs] := args
            return builder.MethodCallExpr(builder.NounExpr("M", span),
                "send", [receiver, builder.LiteralExpr("run", span),
                         emitList(fargs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                span)
        else if (nodeName == "SendExpr"):
            def [receiver, verb, margs, namedArgs] := args
            return builder.MethodCallExpr(builder.NounExpr("M", span),
                "send", [receiver, builder.LiteralExpr(verb, span),
                         emitList(margs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                 span)
        else if (nodeName == "SendCurryExpr"):
            def [receiver, verb] := args
            return builder.MethodCallExpr(
            builder.NounExpr("_makeVerbFacet", span),
                "currySend", [receiver, builder.LiteralExpr(verb, span)], [],
                span)
        else if (nodeName == "PrefixExpr"):
            return builder.MethodCallExpr(args[1], node.getOpName(), [], [], span)
        else if (nodeName == "BinaryExpr"):
            return builder.MethodCallExpr(args[0], node.getOpName(), [args[2]], [], span)
        else if (nodeName == "RangeExpr"):
            return builder.MethodCallExpr(builder.NounExpr("_makeOrderedSpace", span),
                "op__" + node.getOpName(), [args[0], args[2]], [], span)
        else if (nodeName == "CompareExpr"):
            return builder.MethodCallExpr(builder.NounExpr("_comparer", span),
                node.getOpName(), [args[0], args[2]], [], span)
        else if (nodeName == "CoerceExpr"):
            def [spec, guard] := args
            return builder.MethodCallExpr(guard, "coerce",
                [spec, builder.NounExpr("throw", span)], [], span)
        else if (nodeName == "MatchBindExpr"):
            return expandMatchBind(args, span, fail)
        else if (nodeName == "MismatchExpr"):
            return builder.MethodCallExpr(expandMatchBind(args, span, fail), "not", [], [], span)
        else if (nodeName == "SameExpr"):
            def [left, right, same] := args
            if (same):
                return builder.MethodCallExpr(builder.NounExpr("__equalizer", span), "sameEver",
                    [left, right], [], span)
            else:
                return builder.MethodCallExpr(builder.MethodCallExpr(builder.NounExpr("__equalizer", span), "sameEver", [left, right], [], span), "not", [], [], span)
        else if (nodeName == "AndExpr"):
            def [left, right] := args
            return expandLogical(
                left.getStaticScope().outNames(),
                right.getStaticScope().outNames(),
                fn s, f {builder.IfExpr(left, builder.IfExpr(right, s, f, span), f, span)},
                span)
        else if (nodeName == "OrExpr"):
            def [left, right] := args

            def leftmap := left.getStaticScope().outNames()
            def rightmap := right.getStaticScope().outNames()
            def partialFail(failed, s, broken):
                var failedDefs := []
                for n in failed:
                    failedDefs with= (builder.DefExpr(
                        builder.BindingPattern(builder.NounExpr(n, span), span), null, broken, span))
                return builder.SeqExpr(failedDefs + [s], span)
            return expandLogical(
                leftmap, rightmap,
                fn s, f {
                    def broken := builder.MethodCallExpr(
                        builder.NounExpr("_booleanFlow", span),
                        "broken", [], [], span)
                    var rightOnly := []
                    for n in rightmap - leftmap {
                        rightOnly with= (n)
                    }
                    var leftOnly := []
                    for n in leftmap - rightmap {
                        leftOnly with= (n)
                    }
                    builder.IfExpr(left, partialFail(rightOnly, s, broken),
                        builder.IfExpr(right, partialFail(leftOnly, s, broken), f, span), span)},
                span)
        else if (nodeName == "DefExpr"):
            def [patt, ej, rval] := args
            def pattScope := patt.getStaticScope()
            def defPatts := pattScope.getDefNames()
            def varPatts := pattScope.getVarNames()
            def rvalScope := if (ej == null) {
                rval.getStaticScope()
            } else {
                ej.getStaticScope() + rval.getStaticScope()
            }
            def rvalUsed := rvalScope.namesUsed()
            if ((varPatts & rvalUsed).size() != 0):
                fail(["Circular 'var' definition not allowed", span])
            if ((pattScope.namesUsed() & rvalScope.outNames()).size() != 0):
                fail(["Pattern may not used var defined on the right", span])
            def conflicts := pattScope.outNames() & rvalUsed
            if (conflicts.size() == 0):
                return builder.DefExpr(patt, ej, rval, span)
            else:
                def promises := [].diverge()
                def resolvers := [].diverge()
                def renamings := [].asMap().diverge()
                for oldname in conflicts:
                    # Not calling nounFromScope because temp names won't conflict
                    def newname := builder.TempNounExpr(oldname, span)
                    def newnameR := builder.TempNounExpr(oldname + "R", span)
                    renamings[oldname] := newname
                    def pair := [builder.FinalPattern(newname, null, span),
                                 builder.FinalPattern(newnameR, null, span)]
                    promises.push(builder.DefExpr(builder.ListPattern(pair, null, span),
                        null, builder.MethodCallExpr(builder.NounExpr("Ref", span), "promise",
                            [], [], span), span))
                    resolvers.push(builder.MethodCallExpr(newnameR, "resolve",
                         [builder.NounExpr(oldname, span)], [], span))
                def resName := builder.TempNounExpr("value", span)
                resolvers.push(resName)
                def renamedEj := if (ej == null) {null} else {renameCycles(ej, renamings, builder)}
                def renamedRval := renameCycles(rval, renamings, builder)
                def resPatt := builder.FinalPattern(resName, null, span)
                def resDef := builder.DefExpr(resPatt, null,
                     builder.DefExpr(patt, renamedEj, renamedRval, span), span)
                return builder.SeqExpr(promises.snapshot() + [resDef] + resolvers.snapshot(), span)
        else if (nodeName == "ForwardExpr"):
            def [patt] := args
            def rname := builder.NounExpr(patt.getNoun().getName() + "_Resolver", span)
            return builder.SeqExpr([
                builder.DefExpr(builder.ListPattern([
                        patt,
                        builder.FinalPattern(rname, null, span)],
                    null, span),
                    null,
                    builder.MethodCallExpr(builder.NounExpr("Ref", span), "promise", [], [], span), span),
                    rname], span)
        else if (nodeName == "AssignExpr"):
            def [left, right] := args
            def [_, _, leftargs, _] := left._uncall()
            def leftNodeName := left.getNodeName()
            if (leftNodeName == "NounExpr"):
                return builder.AssignExpr(left, right, span)
            else if (leftNodeName == "MethodCallExpr"):
                return expandCallAssign(leftargs.slice(0, 4), right, fail, span)
            else:
                fail(["Assignment can only be done to nouns and collection elements",
                     span])
        else if (nodeName == "VerbAssignExpr"):
            def [verb, target, vargs] := args
            return expandVerbAssign(verb, target, vargs, fail, span)
        else if (nodeName == "AugAssignExpr"):
            def [op, left, right] := args
            return expandVerbAssign(node.getOpName(), left, [right], fail, span)
        else if (nodeName == "ExitExpr"):
            if (args[1] == null):
                return builder.MethodCallExpr(builder.NounExpr("__" + args[0], span), "run", [], [], span)
            else:
                return builder.MethodCallExpr(builder.NounExpr("__" + args[0], span), "run", [args[1]], [], span)
        else if (nodeName == "IgnorePattern"):
            return builder.IgnorePattern(args[0], span)
        else if (nodeName == "FinalPattern"):
            def [noun, guard] := args
            return builder.FinalPattern(noun, guard, span)
        else if (nodeName == "SamePattern"):
            def [value, isSame] := args
            if (isSame):
                return builder.ViaPattern(
                    builder.MethodCallExpr(builder.NounExpr("_matchSame", span),
                        "run", [value], [], span),
                    builder.IgnorePattern(null, span), span)
            else:
                return builder.ViaPattern(
                    builder.MethodCallExpr(builder.NounExpr("_matchSame", span),
                        "different", [value], [], span),
                    builder.IgnorePattern(null, span). span)
        else if (nodeName == "VarPattern"):
            return builder.VarPattern(args[0], args[1], span)
        else if (nodeName == "BindPattern"):
            def [noun, guard] := args
            def g := if (guard == null) {builder.NounExpr("null", span)} else {guard}
            return builder.ViaPattern(
                builder.MethodCallExpr(builder.NounExpr("_bind", span),
                    "run", [builder.NounExpr(noun.getName() + "_Resolver", span), g], [],
                    span),
                builder.IgnorePattern(null, span), span)
        else if (nodeName == "SlotPattern"):
            def [noun, guard] := args
            if (guard == null):
                return builder.ViaPattern(builder.NounExpr("__slotToBinding", span),
                    builder.BindingPattern(noun, span), span)
            else:
                return builder.ViaPattern(
                    builder.MethodCallExpr(builder.NounExpr("__slotToBinding", span),
                        "run", [guard], [],
                        span),
                    builder.BindingPattern(noun, span), span)
        else if (nodeName == "MapPattern"):
            def [assocs, tail] := args
            var nub := if (tail == null) {
                  builder.IgnorePattern(builder.NounExpr("_mapEmpty", span), span)
                  } else {tail}
            for [left, right] in assocs.reverse():
                nub := builder.ViaPattern(
                    left,
                    builder.ListPattern([right, nub], null, span), span)
            return nub
        else if (nodeName == "MapPatternAssoc"):
            def [k, v, default] := args
            if (default == null):
                return [builder.MethodCallExpr(builder.NounExpr("_mapExtract", span),
                                               "run", [k], [], span), v]
            else:
                return [builder.MethodCallExpr(builder.NounExpr("_mapExtract", span),
                                               "depr", [k, default], [], span), v]

        else if (nodeName == "MapPatternImport"):
            def [subnode, default] := args
            def pattName := node.getPattern().getNodeName()
            def [k, v] := if (pattName == "FinalPattern") {
                [builder.LiteralExpr(node.getPattern().getNoun().getName(), span), subnode]
            } else if (pattName == "SlotPattern") {
                [builder.LiteralExpr("&" + node.getPattern().getNoun().getName(), span), subnode]
            } else if (pattName == "BindingPattern") {
                [builder.LiteralExpr("&&" + node.getPattern().getNoun().getName(), span), subnode]
            }
            if (default == null):
                return [builder.MethodCallExpr(builder.NounExpr("_mapExtract", span),
                                               "run", [k], [], span), v]
            else:
                return [builder.MethodCallExpr(builder.NounExpr("_mapExtract", span),
                                               "depr", [k, default], [], span), v]

        else if (nodeName == "ListPattern"):
            def [patterns, tail] := args
            if (tail == null):
                return builder.ListPattern(patterns, null, span)
            else:
                return builder.ViaPattern(
                    builder.MethodCallExpr(builder.NounExpr("_splitList", span), "run",
                        [builder.LiteralExpr(patterns.size(), span)], [], span),
                    builder.ListPattern(patterns + [tail], null, span), span)
        else if (nodeName == "SuchThatPattern"):
            def [pattern, expr] := args
            return builder.ViaPattern(builder.NounExpr("_suchThat", span),
                builder.ListPattern([pattern, builder.ViaPattern(
                    builder.MethodCallExpr(builder.NounExpr("_suchThat", span), "run",
                         [expr], [], span),
                    builder.IgnorePattern(null, span), span)], null, span), span)
        else if (nodeName == "QuasiParserPattern"):
            def [name, quasis] := args
            def qprefix := if (name == null) {"simple"} else {name}
            def qname := qprefix + "__quasiParser"
            def [parts, exprs, patterns] := buildQuasi(builder, qname, quasis)
            return builder.ViaPattern(
                builder.MethodCallExpr(
                    builder.NounExpr("_quasiMatcher", span), "run",
                    [builder.MethodCallExpr(builder.NounExpr(qname, span), "matchMaker",
                        [emitList(parts, span)], [], span), emitList(exprs, span)], [], span),
                builder.ListPattern(patterns, null, span), span)
        else if (nodeName == "FunctionInterfaceExpr"):
            def [doco, name, guard, xtends, mplements, messageDesc] := args
            return expandInterface(doco, name, guard, xtends,
                mplements, [messageDesc], span)
        else if (nodeName == "InterfaceExpr"):
            def [doco, name, guard, xtends, mplements, messages] := args
            return expandInterface(doco, name, guard, xtends,
                mplements, messages, span)
        else if (nodeName == "MessageDesc"):
            def [doco, verb, params, resultGuard] := args
            return expandMessageDesc(doco, verb, params, resultGuard, span)
        else if (nodeName == "ParamDesc"):
            def [name, guard] := args
            return builder.MethodCallExpr(builder.NounExpr("_makeParamDesc", span),
                "run", [builder.LiteralExpr(name, span),
                    if (guard == null) {builder.NounExpr("Any", span)} else {guard}], [], span)
        else if (nodeName == "FunctionExpr"):
            def [patterns, block] := args
            return builder.ObjectExpr(null, builder.IgnorePattern(null, span), null, [],
                builder.Script(null,
                     [builder."Method"(null, "run", patterns, [], null, block, span)],
                     [],
                     span), span)
        else if (nodeName == "ObjectExpr"):
            def [doco, patt, asExpr, auditors, script] := args
            def pattKind := node.getName().getNodeName()
            if (pattKind == "BindPattern"):
                def name := builder.FinalPattern(node.getName().getNoun(), null, span)
                def o := expandObject(doco, name, asExpr, auditors, script, span)
                return builder.DefExpr(patt, null, builder.HideExpr(o, span), span)
            if (pattKind == "FinalPattern" || pattKind == "IgnorePattern"):
                return expandObject(doco, patt, asExpr, auditors, script, span)
            fail(["Unknown pattern type in object expr: " + pattKind, patt.getSpan()])
        else if (nodeName == "Script"):
            #def [xtends, methods, matchers] := args
            return args
        else if (nodeName == "FunctionScript"):
            def [params, namedParams, guard, block] := args
            return [null, [builder."Method"(null, "run", params, namedParams, guard,
                builder.EscapeExpr(builder.FinalPattern(builder.NounExpr("__return", span), null, span),
                    builder.SeqExpr([block, builder.NounExpr("null", span)], span), null, null, span),
                        span)], []]
        else if (nodeName == "To"):
            def [doco, verb, params, namedParams, guard, block] := args
            return builder."Method"(doco, verb, params, namedParams, guard,
                builder.EscapeExpr(builder.FinalPattern(builder.NounExpr("__return", span), null, span),
                    builder.SeqExpr([block, builder.NounExpr("null", span)], span), null, null, span),
                        span)
        else if (nodeName == "Method"):
            def [doco, verb, params, namedParams, guard, block] := args
            return builder."Method"(doco, verb, params, namedParams, guard, block, span)
        else if (nodeName == "NamedParamImport"):
            def [pattern, default] := args
            def k := if (pattern.getNodeName() == "BindingPattern") {
                builder.LiteralExpr("&&" + pattern.getNoun().getName(), span)
            ## via (__slotToBinding) &&foo
            } else if (pattern.getNodeName() == "ViaPattern" &&
                       pattern.getExpr().getNodeName() == "NounExpr" &&
                       pattern.getExpr().getName() == "__slotToBinding" &&
                       pattern.getPattern().getNodeName() == "BindingPattern") {
                builder.LiteralExpr("&" + pattern.getPattern().getNoun().getName(), span)
            } else if (["BindPattern", "VarPattern", "FinalPattern"].contains(pattern.getNodeName())) {
                builder.LiteralExpr(pattern.getNoun().getName(), span)
            }
            return builder.NamedParam(k, pattern, default, span)
        else if (nodeName == "ForExpr"):
            def [coll, key, value, block, catchPatt, catchBlock] := args
            return expandFor(key, value, coll, block, catchPatt, catchBlock, span)
        else if (nodeName == "ListComprehensionExpr"):
            def [coll, filter, key, value, exp] := args
            return expandComprehension(key, value, coll, filter, exp, "_accumulateList", span)
        else if (nodeName == "MapComprehensionExpr"):
            def [coll, filter, key, value, kExp, vExp] := args
            return expandComprehension(key, value, coll, filter,
                emitList([kExp, vExp], span), "_accumulateMap", span)
        else if (nodeName == "SwitchExpr"):
            def [expr, matchers] := args
            def sp := builder.TempNounExpr("specimen", span)
            var failures := []
            var ejs := []
            for _ in matchers:
                failures with= (builder.TempNounExpr("failure", span))
                ejs with= (builder.TempNounExpr("ej", span))
            var block := builder.MethodCallExpr(builder.NounExpr("_switchFailed", span), "run",
                [sp] + failures, [], span)
            for [m, fail, ej] in reversed(zip(matchers, failures, ejs)):
                block := builder.EscapeExpr(
                    builder.FinalPattern(ej, null, span),
                    builder.SeqExpr([
                        builder.DefExpr(m.getPattern(), ej, sp, span),
                        m.getBody()], span),
                    builder.FinalPattern(fail, null, span),
                    block, span)
            return builder.HideExpr(builder.SeqExpr([
                builder.DefExpr(builder.FinalPattern(sp, null, span), null, expr, span),
                block], span), span)
        else if (nodeName == "TryExpr"):
            def [tryblock, catchers, finallyblock] := args
            var block := tryblock
            for cat in catchers:
                block := builder.CatchExpr(block, cat.getPattern(), cat.getBody(), span)
            if (finallyblock != null):
                block := builder.FinallyExpr(block, finallyblock, span)
            return block
        else if (nodeName == "WhileExpr"):
            def [test, block, catcher] := args
            return builder.EscapeExpr(
                builder.FinalPattern(builder.NounExpr("__break", span), null, span),
                    builder.MethodCallExpr(builder.NounExpr("__loop", span), "run",
                        [builder.NounExpr("_iterForever", span),
                         builder.ObjectExpr(null, builder.IgnorePattern(null, span), null, [],
                            builder.Script(null,
                                [builder."Method"(null, "run",
                                     [builder.IgnorePattern(null, span),
                                     builder.IgnorePattern(null, span)],
                                     [],
                                     builder.NounExpr("Bool", span),
                                         builder.IfExpr(
                                             test,
                                             builder.SeqExpr([
                                                 builder.EscapeExpr(
                                                     builder.FinalPattern(
                                                         builder.NounExpr("__continue", span),
                                                         null, span),
                                                     block, null, null, span),
                                                 builder.NounExpr("true", span)],
                                            span), builder.MethodCallExpr(builder.NounExpr("__break", span), "run", [], [], span), span), span)],
                                 [], span), span)], [], span),
                if (catcher !=null) {catcher.getPattern()},
                 if (catcher !=null) {catcher.getBody()}, span)
        else if (nodeName == "WhenExpr"):
            def [promiseExprs, block, catchers, finallyblock] := args
            def expr := if (promiseExprs.size() > 1) {
                builder.MethodCallExpr(builder.NounExpr("promiseAllFulfilled", span), "run",
                    [emitList(promiseExprs, span)], [], span)
            } else {promiseExprs[0]}
            def prob1 := builder.TempNounExpr("problem", span)
            def tryExpr := builder.CatchExpr(
                    expr, builder.FinalPattern(prob1, null, span),
                    builder.MethodCallExpr(builder.NounExpr("Ref", span),
                                           "broken", [prob1], [], span), span)
            def resolution := builder.TempNounExpr("resolution", span)
            def whenblock := builder.IfExpr(
                builder.MethodCallExpr(builder.NounExpr("Ref", span), "isBroken",
                     [resolution], [], span),
                resolution, block, span)
            def wr := builder.MethodCallExpr(builder.NounExpr("Ref", span),
                "whenResolved", [tryExpr,
                                 makeFn("when-catch 'done' function",
                                        [builder.FinalPattern(resolution, null, span)],
                                        whenblock,
                                        expr.getSpan())], [], span)
            def prob2 := builder.TempNounExpr("problem", span)
            var handler := prob2
            if (catchers.size() == 0):
                return wr
            for cat in catchers:
                def fail := builder.TempNounExpr("fail", cat.getSpan())
                handler := builder.EscapeExpr(
                    builder.FinalPattern(fail, null, cat.getSpan()),
                    builder.SeqExpr([
                        builder.DefExpr(cat.getPattern(),
                                        fail,
                                        prob2, cat.getSpan()),
                        cat.getBody()], cat.getSpan()),
                    builder.IgnorePattern(null, cat.getSpan()), handler, cat.getSpan())
            def broken := builder.TempNounExpr("broken", span)
            def wb := builder.MethodCallExpr(
                    builder.NounExpr("Ref", span), "whenBroken", [
                        wr, makeFn(
                            "when-catch 'catch' function",
                            [builder.FinalPattern(broken, null, span)],
                            builder.SeqExpr([
                                builder.DefExpr(
                                    builder.FinalPattern(prob2, null, span),
                                    null,
                                    builder.MethodCallExpr(
                                        builder.NounExpr("Ref", span), "optProblem",
                                        [broken], [], span), span), handler], span), span)],
                    [], span)
            if (finallyblock == null):
                return wb
            return builder.MethodCallExpr(
                wb, "_whenMoreResolved",
                [makeFn("when-catch 'finally' function",
                        [builder.IgnorePattern(null, span)],
                        finallyblock, span)], [], span)
        else:
            return M.call(builder, nodeName, args + [span], [].asMap())

    def reifyTemporaries(tree):
        def nameList := [].diverge()
        def seen := [].asMap().diverge()
        var i := 0
        def nameFinder(node, maker, args, span):
            if (node.getNodeName() == "NounExpr"):
                nameList.push(args[0])
            return node

        tree.transform(nameFinder)
        def names := nameList.asSet()

        def renameTransformer(node, maker, args, span):
            def nodeName := node.getNodeName()
            if (nodeName == "TempNounExpr"):
                return seen.fetch(node, fn {
                    var noun := null
                    while (true) {
                        i += 1
                        def name := `${args[0]}_$i`
                        if (!names.contains(name)) {
                             noun := builder.NounExpr(name, span)
                            break
                        }
                    }
                    seen[node] := noun
                    noun
                })
            else:
                return M.call(builder, nodeName, args + [span], [].asMap())
        return tree.transform(renameTransformer)

    var ast := node

    # Appetizers.

    # Pre-expand certain simple if-expressions. The transformation isn't total
    # but covers many easy cases and doesn't require temporaries.
    ast transform= (ifAnd)
    ast transform= (ifOr)

    # The main course. Expand everything not yet expanded.
    ast := reifyTemporaries(ast.transform(expandTransformer))

    # Dessert.

    # "Expand" modular exponentation. There is extant Monte code which only
    # runs to completion in reasonable time when this transformation is
    # applied.
    ast transform= (modPow)

    return ast

[=> expand]
