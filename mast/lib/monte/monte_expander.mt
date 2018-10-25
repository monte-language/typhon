exports (expand)

def putVerb(verb, fail, span) as DeepFrozen:
    switch (verb):
        match =="get":
            return "put"
        match =="run":
            return "setRun"
        match _:
            fail(["Unsupported verb for assignment", span])

def renameCycles(node, renamings) as DeepFrozen:
    def renamer(node, maker, args, span):
        return switch (node.getNodeName()) {
            match =="NounExpr" {
                renamings.fetch(node.getName(), fn {node})
            }
            match =="TempNounExpr" {
                node
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
    def sw := astBuilder.makeScopeWalker()
    if (ast.getNodeName() == "IfExpr"):
        def [test, consequent, alternative] := args

        if (test.getNodeName() == "OrExpr"):
            def left := test.getLeft()
            def right := test.getRight()

            # left must not define any name used by right; otherwise, if
            # left's test fails, right's test will try to access undefined
            # names.
            if ((sw.getStaticScope(left).outNames() &
                 sw.getStaticScope(right).namesUsed()).isEmpty()):
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


def expand(node, builder, fail) as DeepFrozen:
    def sw := builder.makeScopeWalker()
    def defExpr := builder.DefExpr
    def ignorePatt := builder.IgnorePattern
    def litExpr := builder.LiteralExpr
    def callExpr := builder.MethodCallExpr
    def nounExpr := builder.NounExpr
    def seqExpr := builder.SeqExpr
    def tempNounExpr := builder.TempNounExpr
    def viaPatt := builder.ViaPattern

    def plainPatt(n, span):
        return builder.FinalPattern(n, null, span)

    def nounFromScopeName(n, span):
        if (n =~ _ :Str):
            return nounExpr(n, span)
        return n

    def emitList(items, span):
        return callExpr(
            nounExpr("_makeList", span),
            "run", items, [], span)

    def emitMap(items, span):
        return callExpr(
            nounExpr("_makeMap", span),
            "fromPairs", [emitList(items, span)], [], span)

    def emitIf(test, cons, alt, span):
        "Smart version of `builder.IfExpr`."

        return if (test.getNodeName() == "NounExpr") {
            switch (test.getName()) {
                match =="true" { cons }
                match =="false" { alt }
                match _ { builder.IfExpr(test, cons, alt, span) }
            }
        } else {
            builder.IfExpr(test, cons, alt, span)
        }

    def sameEver(left, right, isSame :Bool, span):
        def call := callExpr(nounExpr("_equalizer", span),
                             "sameEver", [left, right], [], span)
        return if (isSame) { call } else { callExpr(call, "not", [], [], span) }

    def seqSendOnly(ast, maker, args, span):
        "Expand send-expressions inside seq-expressions to use M.sendOnly()."

        if (ast.getNodeName() == "SeqExpr"):
            def exprs := args[0].diverge()
            def last := exprs.size() - 1
            for i => var expr in (exprs):
                if (i != last):
                    if (expr.getNodeName() == "SendExpr"):
                        def receiver := expr.getReceiver()
                        def verb := expr.getVerb()
                        def margs := expr.getArgs()
                        def namedArgs := expr.getNamedArgs()
                        expr := callExpr(nounExpr("M", span),
                            "sendOnly", [receiver, litExpr(verb, span),
                                     emitList(margs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                             span)
                    else if (expr.getNodeName() == "FunSendExpr"):
                        def receiver := expr.getReceiver()
                        def margs := expr.getArgs()
                        def namedArgs := expr.getNamedArgs()
                        expr := callExpr(nounExpr("M", span),
                            "sendOnly", [receiver, litExpr("run", span),
                                     emitList(margs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                            span)
                exprs[i] := expr
            return maker(exprs.snapshot(), span)

        return M.call(maker, "run", args + [span], [].asMap())

    def buildQuasi(name, inputs):
        def parts := ["parts" => [].diverge(),
                      "expr" => [].diverge(),
                      "patt" => [].diverge()]
        for [typ, node, span] in (inputs):
            if (typ == "expr"):
                parts["parts"].push(callExpr(
                    nounExpr(name, span),
                    "valueHole",
                    [litExpr(parts["expr"].size(), span)], [],
                     span))
                parts["expr"].push(node)
            else if (typ == "patt"):
                parts["parts"].push(callExpr(
                    nounExpr(name, span),
                    "patternHole",
                    [litExpr(parts["patt"].size(), span)], [],
                     span))
                parts["patt"].push(node)
            else if (typ == "text"):
                parts["parts"].push(node)
        var ps := []
        for p in (parts):
            ps with= (p.snapshot())
        return ps

    def makeEscapeExpr(ejPatt, ejExpr, catchPatt, catchExpr, span):
        if (catchPatt == null && catchExpr == null):
            # Stage one looks good. Let's do the scope check.
            def pattNames := sw.getStaticScope(ejPatt).outNames()
            def exprNames := sw.getStaticScope(ejExpr).namesUsed()
            if ((pattNames & exprNames).isEmpty()):
                # Stage two succeeded: The expr doesn't use the ejector at
                # all. Elide.
                # traceln(`Eliding: $ejPatt isn't used by $ejExpr`)
                # traceln(`pattNames := $pattNames`)
                # traceln(`exprNames := $exprNames`)
                return ejExpr
        return builder.EscapeExpr(ejPatt, ejExpr, catchPatt, catchExpr, span)

    def makeSlotPatt(n, span):
        return viaPatt(nounExpr("_slotToBinding", span),
             builder.BindingPattern(n, span), span)

    def makeFn(flavor, args, namedArgs, body, span):
        "Like m`fn $args { $body }`, but in Kernel-Monte."

        def out := nounExpr("out", span)
        def repr := if (flavor.isEmpty()) { `<fn at $span>` } else {
            `<$flavor fn at $span>`
        }
        def print := callExpr(out, "print", [litExpr(repr, span)], [], span)
        # Just use the (short) flavor as the docstring. They're not examined
        # often and the M.toString/1 will be more informative to folks anyway.
        def rv := builder.ObjectExpr(flavor,
             ignorePatt(null, span), null, [],
             builder.Script(null, [
                 builder."Method"(null, "run", args, namedArgs, null, body,
                                  span),
                 builder."Method"(null, "_printOn", [plainPatt(out, span)],
                                  [], null, print, span),
             ], [], span), span)
        return rv

    def expandMatchBind(sw, args, span, fail):
        def [spec, patt] := args
        def pattScope := sw.getStaticScope(patt)
        def specScope := sw.getStaticScope(spec)
        def conflicts := pattScope.outNames() & specScope.namesUsed()
        if (!conflicts.isEmpty()):
            fail([`Use on left isn't really in scope of matchbind pattern: ${conflicts.getKeys()}`, span])
        def [sp, ejector, result, problem, broken] :=  [
            tempNounExpr("sp", span),
            tempNounExpr("fail", span),
            tempNounExpr("ok", span),
            tempNounExpr("problem", span),
            tempNounExpr("broken", span)
            ]

        var bindingpatts := []
        var bindingexprs := []
        for nn in (pattScope.outNames()):
            def noun := nounFromScopeName(nn, span)
            bindingpatts with= (builder.BindingPattern(noun, span))
            bindingexprs with= (builder.BindingExpr(noun, span))

        return seqExpr([
            defExpr(plainPatt(sp, span), null, spec, span),
            defExpr(builder.ListPattern([plainPatt(result, span)] +
                                        bindingpatts, null, span),
                null,
                makeEscapeExpr(
                    plainPatt(ejector, span),
                    seqExpr([
                        defExpr(patt, ejector, sp, span),
                        emitList([nounExpr("true", span)] +
                            bindingexprs, span)], span),
                    plainPatt(problem, span),
                    seqExpr([
                        defExpr(viaPatt(
                            nounExpr("_slotToBinding", span),
                        builder.BindingPattern(broken, span), span),
                            null,
                            callExpr(nounExpr("Ref", span),
                                "broken", [problem], [], span), span),
                            emitList([nounExpr("false", span)] +
                                [builder.BindingExpr(broken, span)] * bindingexprs.size(), span)],
                                span),
                    span),
                span),
            result],
            span)

    def expandLogical(leftNames, rightNames, f, span):
        var bindingpatts := []
        var bindingexprs := []
        for n in (leftNames | rightNames):
            bindingpatts with= (builder.BindingPattern(nounFromScopeName(n, span), span))
            bindingexprs with= (builder.BindingExpr(nounFromScopeName(n, span), span))

        if (!bindingexprs.isEmpty()):
            # Annoying path; we must consider the possibility that some names
            # are conditionally defined and must be broken.
            def result := tempNounExpr("ok", span)
            def success := emitList([nounExpr("true", span)] +
                bindingexprs, span)
            def failure := callExpr(nounExpr("_booleanFlow", span),
                "failureList", [litExpr(bindingexprs.size(), span)], [], span)
            return seqExpr([
                defExpr(
                    builder.ListPattern([plainPatt(result, span)] +
                        bindingpatts, null, span),
                    null,
                    f(success, failure), span),
                    result], span)
        else:
            # Awesome path! _booleanFlow.failureList(0) constant-folds to
            # [false], so we can elide almost all of the scaffolding.
            def success := nounExpr("true", span)
            def failure := nounExpr("false", span)
            return f(success, failure)

    def expandCallAssign([rcvr, verb, margs, _namedArgs], right, fail, span):
        def ares := tempNounExpr("ares", span)
        return seqExpr([
            callExpr(rcvr, putVerb(verb, fail, span),
                margs + [defExpr(plainPatt(ares, span),
                null, right, span)], [], span),
            ares], span)

    def expandVerbAssign(verb, target, vargs, fail, span):
        def [_, _, leftargs, _] := target._uncall()
        switch (target.getNodeName()):
            match =="NounExpr":
                return builder.AssignExpr(target, callExpr(target, verb, vargs, [], span), span)
            match =="MethodCallExpr":
                def [rcvr, methverb, margs, _mnamedargs, lspan] := leftargs
                def recip := tempNounExpr("recip", lspan)
                def seq := [defExpr(plainPatt(recip, lspan),
                            null, rcvr, lspan)].diverge()
                def setArgs := [].diverge()
                for arg in (margs):
                    def a := tempNounExpr("arg", span)
                    seq.push(defExpr(plainPatt(a, lspan),
                         null, arg, lspan))
                    setArgs.push(a)
                seq.extend(expandCallAssign([recip, methverb, setArgs.snapshot(), []], callExpr(callExpr(recip, methverb, setArgs.snapshot(), [], span), verb, vargs, [], span), fail, span).getExprs())
                return seqExpr(seq.snapshot(), span)
            match =="QuasiLiteralExpr":
                fail(["Can't use update-assign syntax on a \"$\"-hole. Use explicit \":=\" syntax instead.", span])
            match =="QuasiPatternExpr":
                fail(["Can't use update-assign syntax on a \"@\"-hole. Use explicit \":=\" syntax instead.", span])
            match _:
                fail(["Can only update-assign nouns and calls", span])

    def expandMessageDesc(doco, verb, paramDescs, namedParamDescs, resultGuard, span):
        def docExpr := if (doco == null) {nounExpr("null", span)} else {litExpr(doco, span)}
        def guardExpr := if (resultGuard == null) {nounExpr("Any", span)} else {
            resultGuard}
        return builder.HideExpr(callExpr(nounExpr("_makeMessageDesc", span),
            "run", [docExpr, litExpr(verb, span),
                    emitList(paramDescs, span),
                    emitList(namedParamDescs, span), guardExpr], [],
             span), span)

    def refPromise(span):
        return callExpr(nounExpr("Ref", span), "promise", [], [], span)

    def buildRefCycle(conflicts, makeInnerExpr, span):
        def promises := [].diverge()
        def resolvers := [].diverge()
        def renamings := [].asMap().diverge()
        for oldname in (conflicts):
            # Not calling nounFromScope because temp names won't conflict
            def newname := tempNounExpr(oldname, span)
            def newnameR := tempNounExpr(oldname + "R", span)
            renamings[oldname] := newname
            def pair := [plainPatt(newname, span),
                         plainPatt(newnameR, span)]
            promises.push(defExpr(builder.ListPattern(pair, null, span),
                null, refPromise(span), span))
            resolvers.push(callExpr(newnameR, "resolve",
                 [nounExpr(oldname, span)], [], span))
        def resName := tempNounExpr("value", span)
        resolvers.push(resName)
        def resPatt := plainPatt(resName, span)
        def resDef := defExpr(resPatt, null, makeInnerExpr(renamings), span)
        return seqExpr(promises.snapshot() + [resDef] + resolvers.snapshot(), span)

    def _expandObject(renamings, doco, name, asExpr, auditors, [xtends, methods, matchers], span):
        def p := tempNounExpr("message", span)

        def superExpr := if (xtends.getNodeName() == "NounExpr") {
            defExpr(builder.BindingPattern(nounExpr("super", span), span), null,
                builder.BindingExpr(xtends, span), span)
        } else {
            defExpr(plainPatt(nounExpr("super", span), span), null, renameCycles(xtends, renamings), span)
        }

        # Offer a better selection of Miranda methods than the runtime.
        def newMethods := methods + {
            var needPrintOn :Bool := true
            for m in (methods) {
                switch ([m.getVerb(), m.getParams().size()]) {
                    match ==["_printOn", 1] { needPrintOn := false }
                    match _ { null }
                }
            }
            def l := [].diverge()
            if (needPrintOn) {
                # method _printOn(out) { out.print("<name>") ; null }
                def out := tempNounExpr("out", span)
                def n := name.getNoun().getName()
                def label := litExpr(`<$n>`, span)
                def seq := [
                    callExpr(out, "print", [label], [], span),
                    nounExpr("null", span),
                ]
                def m := builder."Method"(null, "_printOn",
                                          [plainPatt(out, span)], [], null,
                                          seqExpr(seq, span), span)
                l.push(m)
            }
            l
        }
        def newMatchers := matchers + [
            # match message { M.callWithMessage(super, message) }
            builder.Matcher(plainPatt(p, span),
                callExpr(nounExpr("M", span), "callWithMessage",
                         [nounExpr("super", span), p], [], span), span)
        ]
        def script := builder.Script(null, newMethods, newMatchers, span)

        # We need to get the result of the asExpr into the guard for the
        # overall defExpr. If (and only if!) we have the auditor as a single
        # noun (e.g. DeepFrozen), then we should use it directly; otherwise,
        # put it into an antecedent DefExpr and reference that defined name. A
        # similar but subtler logic was used in superExpr. ~ C.
        if (asExpr == null):
            return defExpr(name, null, builder.HideExpr(seqExpr([superExpr,
                builder.ObjectExpr(doco, name, null, auditors, script, span)], span),
                span), span)
        else if (asExpr.getNodeName() == "NounExpr"):
            return defExpr(name.withGuard(asExpr), null, builder.HideExpr(seqExpr([superExpr,
                builder.ObjectExpr(doco, name, asExpr, auditors, script, span)], span),
                span), span)
        else:
            def auditorNoun := tempNounExpr("auditor", span)
            def auditorExpr := defExpr(plainPatt(auditorNoun, span),
                                       null, asExpr, span)
            # The auditorExpr must be evaluated early enough to be used as the
            # definition guard. Unfortunately, I cannot think of any simple
            # nor convoluted way to evaluate the superExpr first while still
            # scoping it correctly. ~ C.
            return builder.HideExpr(seqExpr([auditorExpr,
                defExpr(name.withGuard(auditorNoun), null, builder.HideExpr(seqExpr([superExpr,
                    builder.ObjectExpr(doco, name, auditorNoun, auditors,
                    script, span)], span),
                    span), span)], span), span)

    def expandObject(doco, name, asExpr, auditors, [xtends, methods, matchers], span):
        # Easy case: There's no object being extended, so the object's fine
        # as-is. Just assemble it.
        def objNameScope := sw.getStaticScope(name)
        var auditorScope := if (asExpr == null) { sw.getEmptyScope()
                            } else { sw.getStaticScope(asExpr) }
        for a in (auditors):
            auditorScope += sw.getStaticScope(a)
        if (!(objNameScope.outNames() & auditorScope.namesUsed()).isEmpty()):
            fail(["Auditors cannot use self", span])
        if (xtends == null):
            return builder.ObjectExpr(doco, name, asExpr, auditors,
                                      builder.Script(null, methods, matchers,
                                                     span),
                                      span)
        def extendScope := sw.getStaticScope(xtends)
        def conflicts := objNameScope.outNames() & extendScope.namesUsed()
        return if (!conflicts.isEmpty()) {
            buildRefCycle(conflicts, fn renamings {_expandObject(renamings, doco, name, asExpr, auditors, [xtends, methods, matchers], span)}, span)
        } else {
            _expandObject([].asMap(), doco, name, asExpr, auditors, [xtends, methods, matchers], span)
        }

    def expandInterface(doco, name, guard, xtends, mplements, messages, span):
        def verb := if (guard == null) {"run"} else {"makePair"}
        def docExpr := if (doco == null) { nounExpr("null", span) } else {litExpr(doco, span)}
        def ifaceExpr := builder.HideExpr(callExpr(
            nounExpr("_makeProtocolDesc", span), verb,
                [docExpr, callExpr(
                    callExpr(
                        builder.MetaContextExpr(span),
                        "getFQNPrefix", [], [], span),
                    "add", [litExpr(name.getNoun().getName() + "_T", span)], [], span),
                emitList(xtends, span),
                emitList(mplements, span),
                emitList(messages, span)], [], span), span)
        if (guard == null):
            return defExpr(name, null, ifaceExpr, span)
        else:
            return callExpr(
                defExpr(builder.ListPattern([name, guard],
                                                    null, span),
                         null, ifaceExpr, span),
                "get", [litExpr(0, span)], [], span)

    def validateFor(left, right, fail, span):
        if (!(left.outNames() & right.namesUsed()).isEmpty()):
            fail(["Use on right isn't really in scope of definition", span])
        if (!(right.outNames() & left.namesUsed()).isEmpty()):
            fail(["Use on left would get captured by definition on right", span])


    def expandFor(sw, optKey, value, coll, block, catchPatt, catchBlock, span):
        def key := if (optKey == null) {ignorePatt(null, span)} else {optKey}
        validateFor(sw.getStaticScope(key) + sw.getStaticScope(value),
                    sw.getStaticScope(coll), fail, span)
        # `key` and `value` are patterns. We cannot permit any code to run
        # within the loop until we've done _validateFor(), which normally
        # means that we use temp nouns and postpone actually unifying the key
        # and value until afterwards. This is a bit of a waste of time,
        # especially in very tight loops, and none of our optimizers can
        # improve it since it's (ironically) unsafe to move any defs around
        # the _validateFor() call! So, instead, we're considering whether the
        # patterns can be refuted. If a pattern is irrefutable, then we'll
        # unify it directly in the method's parameters. ~ C.
        def [patts, defs] := if (key.refutable()) {
            # The key is refutable, so we go with the traditional layout.
            def kTemp := tempNounExpr("key", span)
            def vTemp := tempNounExpr("value", span)
            [
                [plainPatt(kTemp, span),
                 plainPatt(vTemp, span)],
                [defExpr(key, null, kTemp, span),
                 defExpr(value, null, vTemp, span)],
            ]
        } else if (value.refutable()) {
            # Irrefutable key, refutable value. Split the difference.
            def vTemp := tempNounExpr("value", span)
            [
                [key, plainPatt(vTemp, span)],
                [defExpr(value, null, vTemp, span)],
            ]
        } else {
            # Yay, both are irrefutable!
            [
                [key, value], [],
            ]
        }
        def obj := builder.ObjectExpr("For-loop body",
            ignorePatt(null, span), null, [], builder.Script(
                null,
                [builder."Method"(null, "run", patts, [], null,
                seqExpr([
                    makeEscapeExpr(
                        plainPatt(nounExpr("__continue", span), span),
                        seqExpr(defs + [
                            block,
                            nounExpr("null", span)
                        ], span),
                    null, null, span),
                ], span), span)],
            [], span), span)
        return makeEscapeExpr(
            plainPatt(nounExpr("__break", span), span),
            seqExpr([
                callExpr(nounExpr("_loop", span),
                         "run", [coll, obj], [], span),
                nounExpr("null", span)
            ], span),
            catchPatt,
            catchBlock,
            span)

    def expandComprehension(sw, optKey, value, coll, filter, exp, collector, span):
        def key := if (optKey == null) {ignorePatt(null, span)} else {optKey}
        validateFor(sw.getStaticScope(exp), sw.getStaticScope(coll), fail, span)
        validateFor(sw.getStaticScope(key) + sw.getStaticScope(value), sw.getStaticScope(coll), fail, span)
        # Same concept as expandFor(). ~ C.
        def [patts, defs] := if (key.refutable()) {
            # The key is refutable, so we go with the traditional layout.
            def kTemp := tempNounExpr("key", span)
            def vTemp := tempNounExpr("value", span)
            [
                [plainPatt(kTemp, span),
                 plainPatt(vTemp, span)],
                [defExpr(key, null, kTemp, span),
                 defExpr(value, null, vTemp, span)],
            ]
        } else if (value.refutable()) {
            # Irrefutable key, refutable value. Split the difference.
            def vTemp := tempNounExpr("value", span)
            [
                [key, plainPatt(vTemp, span)],
                [defExpr(value, null, vTemp, span)],
            ]
        } else {
            # Yay, both are irrefutable!
            [
                [key, value], [],
            ]
        }
        # Same logic, applied to the filter/skip stuff. ~ C.
        def [skipPatt, maybeFilterExpr] := if (filter != null) {
            def skip := tempNounExpr("skip", span)
            [
                plainPatt(skip, span),
                emitIf(filter, exp, callExpr(skip, "run", [], [], span),
                       span),
            ]
        } else {
            [ignorePatt(null, span), exp]
        }
        def obj := builder.ObjectExpr("For-loop body",
            ignorePatt(null, span), null, [], builder.Script(
                null,
                [builder."Method"(null, "run", patts.with(skipPatt), [], null,
                seqExpr(defs.with(maybeFilterExpr), span), span)],
            [], span), span)
        return callExpr(nounExpr(collector, span),
                     "run", [coll, obj], [], span)


    def mapExtract(k, v, default, span):
        def n := nounExpr("_mapExtract", span)
        return if (default == null):
            [callExpr(n, "run", [k], [], span), v]
        else:
            [callExpr(n, "withDefault", [k, default], [], span), v]


    def expandTransformer(node, _maker, args, span):
        # traceln(`expander: ${node.getNodeName()}: Expanding $node`)

        return switch (node.getNodeName()):
            match =="LiteralExpr":
                litExpr(args[0], span)
            match =="NounExpr":
                def [name] := args
                nounExpr(name, span)
            match =="SlotExpr":
                def [noun] := args
                callExpr(builder.BindingExpr(noun, span), "get", [], [], span)
            match =="BindingExpr":
                def [noun] := args
                builder.BindingExpr(noun, span)
            match =="MethodCallExpr":
                def [rcvr, verb, arglist, namedArgs] := args
                callExpr(rcvr, verb, arglist, namedArgs, span)
            match =="NamedArg":
                builder.NamedArg(args[0], args[1], span)
            match =="NamedArgExport":
                def [val] := args
                def orig := node.getValue()
                def name := switch (orig.getNodeName()) {
                    match =="BindingExpr" { "&&" + orig.getNoun().getName() }
                    match =="SlotExpr" { "&" + orig.getNoun().getName() }
                    match _ { orig.getName() }
                }
                builder.NamedArg(litExpr(name, span), val, span)
            match =="ListExpr":
                def [items] := args
                emitList(items, span)
            match =="MapExpr":
                def [assocs] := args
                var lists := []
                for a in (assocs):
                    lists with= (emitList(a, span))
                callExpr(nounExpr("_makeMap", span), "fromPairs",
                    [emitList(lists, span)], [], span)
            match =="MapExprAssoc":
                args
            match =="MapExprExport":
                def [subnode] := args
                def n := node.getValue()
                switch (n.getNodeName()):
                    match =="NounExpr":
                        [litExpr(n.getName(), span), subnode]
                    match =="SlotExpr":
                        [litExpr("&" + n.getNoun().getName(), span), subnode]
                    match =="BindingExpr":
                        [litExpr("&&" + n.getNoun().getName(), span), subnode]
            match =="QuasiText":
                def [text] := args
                ["text", litExpr(text, span), span]
            match =="QuasiExprHole":
                def [expr] := args
                ["expr", expr, span]
            match =="QuasiPatternHole":
                def [patt] := args
                ["patt", patt, span]
            match =="QuasiParserExpr":
                def [name, quasis] := args
                def qprefix := if (name == null) {""} else {name}
                def qname := qprefix + "``"
                def [parts, exprs, _] := buildQuasi(qname, quasis)
                callExpr(
                    callExpr(nounExpr(qname, span), "valueMaker",
                        [emitList(parts, span)], [], span),
                    "substitute", [emitList(exprs, span)], [], span)
            match =="Module":
                def [importsList, exportsList, expr] := args
                def pkg := tempNounExpr("package", span)
                # Build the dependency list and import list at the same time.
                def dependencies := [].diverge()
                def importExprs := [].diverge()
                for im in (importsList):
                    def dependency := litExpr(im.getName(), im.getSpan())
                    dependencies.push(dependency)
                    importExprs.push(defExpr(im.getPattern(), null,
                        callExpr(pkg, "import", [dependency], [], im.getSpan()),
                        im.getSpan()))
                def exportExpr := emitMap([for noun in (exportsList)
                                   emitList([litExpr(noun.getName(),
                                                        noun.getSpan()), noun],
                                            span)], span)
                def runBody := seqExpr(importExprs.snapshot() +
                                               [expr, exportExpr], span)
                def DFMap := callExpr(nounExpr("Map", span),
                    "get", [nounExpr("Str", span),
                            nounExpr("DeepFrozen", span)], [], span)
                def ListOfStr := callExpr(
                    nounExpr("List", span), "get",
                    [nounExpr("Str", span)], [], span)
                def dependenciesMethod := builder."Method"(
                    "The dependencies of this module.",
                    "dependencies", [], [], ListOfStr,
                    emitList(dependencies.snapshot(), span), span)
                builder.ObjectExpr(null,
                    ignorePatt(null, span),
                    nounExpr("DeepFrozen", span), [],
                    builder.Script(null,
                         [builder."Method"(null, "run",
                                           [plainPatt(pkg, span)], [], DFMap,
                                           runBody, span),
                          dependenciesMethod],
                         [], span), span)
            match =="SeqExpr":
                def [exprs] := args
                #XXX some parsers have emitted nested SeqExprs, should that
                #flattening be done here or in the parser?
                seqExpr(exprs, span)
            match =="CurryExpr":
                def [receiver, verb, isSend] := args
                callExpr(
                    nounExpr("_makeVerbFacet", span),
                    isSend.pick("currySend", "curryCall"),
                    [receiver, litExpr(verb, span)], [],
                    span)
            match =="GetExpr":
                def [receiver, index] := args
                callExpr(receiver, "get", index, [], span)
            match =="FunCallExpr":
                def [receiver, fargs, namedArgs] := args
                callExpr(receiver, "run", fargs, namedArgs, span)
            match =="FunSendExpr":
                def [receiver, fargs, namedArgs] := args
                callExpr(nounExpr("M", span),
                    "send", [receiver, litExpr("run", span),
                             emitList(fargs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                    span)
            match =="SendExpr":
                def [receiver, verb, margs, namedArgs] := args
                callExpr(nounExpr("M", span),
                    "send", [receiver, litExpr(verb, span),
                             emitList(margs, span), emitMap([for na in (namedArgs) emitList([na.getKey(), na.getValue()], span)], span)], [],
                     span)
            match =="ControlExpr":
                def [target, operator, cargs, params, body, top] := args
                def t := if (node.getTarget().getNodeName() != "ControlExpr") {
                        callExpr(nounExpr("DeepFrozen", span), "coerce",
                                 [target, nounExpr("throw", span)], [], span)
                    } else {
                        target
                    }
                def fnEj := tempNounExpr("ej", span)
                def tempNouns := [for _ in (params) tempNounExpr("p", span)]
                def ejPatt := plainPatt(fnEj, span)
                def tempPatts := [for n in (tempNouns)
                                  plainPatt(n, span)]
                def pattsIn := if (params.isEmpty()) { [] } else {
                    tempPatts.with(ejPatt)
                }
                def outBody := if (params.isEmpty()) { body } else {
                    seqExpr([
                        defExpr(builder.ListPattern(params, null, span), fnEj,
                                emitList(tempNouns, span), span),
                        body], span)
                }
                def lambda := makeFn("control-lambda", pattsIn, [], outBody,
                                     span)
                def block := makeFn("control-block", [], [],
                    emitList([emitList(cargs, span), lambda], span), span)
                def cexpr := callExpr(
                    t, "control",
                    [litExpr(operator, span),
                     litExpr(cargs.size(), span),
                     litExpr(params.size(), span),
                     block], [], span)
                return if (top) {
                        callExpr(cexpr, "controlRun", [], [], span)
                    } else {
                        cexpr
                    }
            match =="PrefixExpr":
                callExpr(args[1], node.getOpName(), [], [], span)
            match =="BinaryExpr":
                callExpr(args[0], node.getOpName(), [args[2]], [], span)
            match =="RangeExpr":
                callExpr(nounExpr("_makeOrderedSpace", span),
                    "op__" + node.getOpName(), [args[0], args[2]], [], span)
            match =="CompareExpr":
                callExpr(nounExpr("_comparer", span),
                    node.getOpName(), [args[0], args[2]], [], span)
            match =="CoerceExpr":
                def [spec, guard] := args
                callExpr(guard, "coerce",
                    [spec, nounExpr("throw", span)], [], span)
            match =="MatchBindExpr":
                expandMatchBind(sw, args, span, fail)
            match =="MismatchExpr":
                callExpr(expandMatchBind(sw, args, span, fail), "not", [], [], span)
            match =="SameExpr":
                def [left, right, same :Bool] := args
                sameEver(left, right, same, span)
            match =="AndExpr":
                def [left, right] := args
                expandLogical(
                    sw.getStaticScope(left).outNames(),
                    sw.getStaticScope(right).outNames(),
                    fn s, f { emitIf(left, emitIf(right, s, f, span), f, span) },
                    span)
            match =="OrExpr":
                def [left, right] := args

                def leftmap := sw.getStaticScope(left).outNames()
                def rightmap := sw.getStaticScope(right).outNames()
                def partialFail(failed, s, broken):
                    var failedDefs := []
                    for n in (failed):
                        failedDefs with= (defExpr(
                            builder.BindingPattern(nounFromScopeName(n, span), span), null, broken, span))
                    return seqExpr(failedDefs + [s], span)
                expandLogical(
                    leftmap, rightmap,
                    fn s, f {
                        def broken := callExpr(
                            nounExpr("_booleanFlow", span),
                            "broken", [], [], span)
                        var rightOnly := []
                        for n in (rightmap - leftmap) {
                            rightOnly with= (n)
                        }
                        var leftOnly := []
                        for n in (leftmap - rightmap) {
                            leftOnly with= (n)
                        }
                        emitIf(left, partialFail(rightOnly, s, broken),
                            emitIf(right, partialFail(leftOnly, s, broken), f, span), span)
                    }, span)
            match =="DefExpr":
                def [patt, ej, rval] := args
                def pattScope := sw.getStaticScope(patt)
                def varPatts := pattScope.getVarNames()
                def rvalScope := if (ej == null) {
                    sw.getStaticScope(rval)
                } else {
                    sw.getStaticScope(ej) + sw.getStaticScope(rval)
                }
                def rvalUsed := rvalScope.namesUsed()
                if (!(varPatts & rvalUsed).isEmpty()):
                    fail(["Circular 'var' definition not allowed", span])
                if (!(pattScope.namesUsed() & rvalScope.outNames()).isEmpty()):
                    fail(["Pattern may not use var defined on the right", span])
                def conflicts := pattScope.outNames() & rvalUsed
                if (conflicts.isEmpty()):
                    defExpr(patt, ej, rval, span)
                else:
                    buildRefCycle(conflicts, fn renamings {
                        def renamedRval := renameCycles(rval, renamings)
                        def renamedEj := if (ej == null) {null} else {renameCycles(ej, renamings)}
                        defExpr(patt, renamedEj, renamedRval, span)
                        }, span)
            match =="ForwardExpr":
                def [patt] := args
                def rname := nounExpr(patt.getNoun().getName() + "_Resolver", span)
                seqExpr([
                    defExpr(builder.ListPattern([patt,
                            plainPatt(rname, span)], null,
                            span),
                        null, refPromise(span), span), rname], span)
            match =="AssignExpr":
                def [left, right] := args
                def [_, _, leftargs, _] := left._uncall()
                switch (left.getNodeName()):
                    match =="NounExpr":
                        builder.AssignExpr(left, right, span)
                    match =="MethodCallExpr":
                        expandCallAssign(leftargs.slice(0, 4), right, fail, span)
                    match _:
                        fail(["Assignment can only be done to nouns and collection elements",
                             span])
            match =="VerbAssignExpr":
                def [verb, target, vargs] := args
                expandVerbAssign(verb, target, vargs, fail, span)
            match =="AugAssignExpr":
                def [_op, left, right] := args
                expandVerbAssign(node.getOpName(), left, [right], fail, span)
            match =="ExitExpr":
                callExpr(nounExpr("__" + args[0], span), "run",
                         if (args[1] == null) { [] } else { [args[1]] }, [],
                         span)
            match =="IgnorePattern":
                ignorePatt(args[0], span)
            match =="FinalPattern":
                def [noun, guard] := args
                builder.FinalPattern(noun, guard, span)
            match =="SamePattern":
                def [value, isSame] := args
                # Note: We use `isSame` only to choose which verb is given to
                # `_matchSame`. ~ C.
                viaPatt(
                    callExpr(nounExpr("_matchSame", span),
                        isSame.pick("run", "different"), [value], [], span),
                    ignorePatt(null, span), span)
            match =="VarPattern":
                builder.VarPattern(args[0], args[1], span)
            match =="BindPattern":
                def [noun, guard] := args
                def g := if (guard == null) {nounExpr("null", span)} else {guard}
                viaPatt(
                    callExpr(nounExpr("_bind", span),
                        "run", [nounExpr(noun.getName() + "_Resolver", span), g], [],
                        span),
                    ignorePatt(null, span), span)
            match =="SlotPattern":
                def [noun, guard] := args
                def slotToBinding := nounExpr("_slotToBinding", span)
                if (guard == null):
                    viaPatt(slotToBinding, builder.BindingPattern(noun, span),
                            span)
                else:
                    viaPatt(callExpr(slotToBinding, "run", [guard], [], span),
                            builder.BindingPattern(noun, span), span)
            match =="MapPattern":
                def [assocs, tail] := args
                var nub := if (tail == null) {
                      ignorePatt(nounExpr("_mapEmpty", span), span)
                      } else {tail}
                for [left, right] in (assocs.reverse()):
                    nub := viaPatt(
                        left,
                        builder.ListPattern([right, nub], null, span), span)
                nub
            match =="MapPatternAssoc":
                def [k, v, default] := args
                mapExtract(k, v, default, span)
            match =="MapPatternImport":
                def [subnode, default] := args
                def patt := node.getValue()
                def pattName := patt.getNodeName()
                def [k, v] := if (pattName == "FinalPattern" || pattName == "VarPattern") {
                    [litExpr(patt.getNoun().getName(), span), subnode]
                } else if (pattName == "SlotPattern") {
                    [litExpr("&" + patt.getNoun().getName(), span), subnode]
                } else if (pattName == "BindingPattern") {
                    [litExpr("&&" + patt.getNoun().getName(), span), subnode]
                }
                mapExtract(k, v, default, span)
            match =="ListPattern":
                def [patterns, tail] := args
                if (tail == null):
                    builder.ListPattern(patterns, null, span)
                else:
                    viaPatt(
                        callExpr(nounExpr("_splitList", span), "run",
                            [litExpr(patterns.size(), span)], [], span),
                        builder.ListPattern(patterns + [tail], null, span), span)
            match =="SuchThatPattern":
                def [pattern, expr] := args
                def suchThat := nounExpr("_suchThat", span)
                viaPatt(suchThat,
                    builder.ListPattern([pattern, viaPatt(
                        callExpr(suchThat, "run", [expr], [], span),
                        ignorePatt(null, span), span)], null, span), span)
            match =="QuasiParserPattern":
                def [name, quasis] := args
                def qprefix := if (name == null) {""} else {name}
                def qname := qprefix + "``"
                def [parts, exprs, patterns] := buildQuasi(qname, quasis)
                viaPatt(
                    callExpr(
                        nounExpr("_quasiMatcher", span), "run",
                        [callExpr(nounExpr(qname, span), "matchMaker",
                            [emitList(parts, span)], [], span), emitList(exprs, span)], [], span),
                    builder.ListPattern(patterns, null, span), span)
            match =="FunctionInterfaceExpr":
                def [doco, name, guard, xtends, mplements, messageDesc] := args
                expandInterface(doco, name, guard, xtends,
                    mplements, [messageDesc], span)
            match =="InterfaceExpr":
                def [doco, name, guard, xtends, mplements, messages] := args
                expandInterface(doco, name, guard, xtends,
                    mplements, messages, span)
            match =="MessageDesc":
                def [doco, verb, params, namedParams, resultGuard] := args
                expandMessageDesc(doco, verb, params, namedParams, resultGuard, span)
            match =="ParamDesc":
                def [name, guard] := args
                callExpr(nounExpr("_makeParamDesc", span),
                    "run", [litExpr(name, span),
                        if (guard == null) {nounExpr("Any", span)} else {guard}], [], span)
            match =="FunctionExpr":
                def [patterns, namedPatts, block] := args
                makeFn("", patterns, namedPatts, block, span)
            match =="ObjectExpr":
                def [doco, patt, asExpr, auditors, script] := args
                switch (node.getName().getNodeName()):
                    match =="BindPattern":
                        def name := plainPatt(node.getName().getNoun(), span)
                        def o := expandObject(doco, name, asExpr, auditors, script, span)
                        defExpr(patt, null, builder.HideExpr(o, span), span)
                    match =="FinalPattern":
                        expandObject(doco, patt, asExpr, auditors, script, span)
                    match =="IgnorePattern":
                        expandObject(doco, patt, asExpr, auditors, script, span)
                    match pattKind:
                        fail(["Unknown pattern type in object expr: " + pattKind, patt.getSpan()])
            match =="Script":
                #def [xtends, methods, matchers] := args
                return args
            match =="FunctionScript":
                def [verb, params, namedParams, guard, block] := args
                [null, [builder."Method"(null, verb, params, namedParams, guard,
                    makeEscapeExpr(plainPatt(nounExpr("__return", span), span),
                        seqExpr([block, nounExpr("null", span)], span), null, null, span),
                            span)], []]
            match =="To":
                def [doco, verb, params, namedParams, guard, block] := args
                builder."Method"(doco, verb, params, namedParams, guard,
                    makeEscapeExpr(plainPatt(nounExpr("__return", span), span),
                        seqExpr([block, nounExpr("null", span)], span), null, null, span),
                            span)
            match =="Method":
                def [doco, verb, params, namedParams, guard, block] := args
                builder."Method"(doco, verb, params, namedParams, guard, block, span)
            match =="NamedParamImport":
                def [pattern, default] := args
                def k := if (pattern.getNodeName() == "BindingPattern") {
                    litExpr("&&" + pattern.getNoun().getName(), span)
                ## via (_slotToBinding) &&foo
                } else if (pattern.getNodeName() == "ViaPattern" &&
                           pattern.getExpr().getNodeName() == "NounExpr" &&
                           pattern.getExpr().getName() == "_slotToBinding" &&
                           pattern.getPattern().getNodeName() == "BindingPattern") {
                    litExpr("&" + pattern.getPattern().getNoun().getName(), span)
                } else if (["BindPattern", "VarPattern", "FinalPattern"].contains(pattern.getNodeName())) {
                    litExpr(pattern.getNoun().getName(), span)
                }
                builder.NamedParam(k, pattern, default, span)
            match =="ForExpr":
                def [coll, key, value, block, catchPatt, catchBlock] := args
                expandFor(sw, key, value, coll, block, catchPatt, catchBlock, span)
            match =="ListComprehensionExpr":
                def [coll, filter, key, value, exp] := args
                expandComprehension(sw, key, value, coll, filter, exp, "_accumulateList", span)
            match =="MapComprehensionExpr":
                def [coll, filter, key, value, kExp, vExp] := args
                expandComprehension(sw, key, value, coll, filter,
                    emitList([kExp, vExp], span), "_accumulateMap", span)
            match =="SwitchExpr":
                def [expr, matchers] := args
                def sp := tempNounExpr("specimen", span)
                def clauses := [for m in (matchers) {
                    def patt := m.getPattern()
                    def body := m.getBody()
                    if (patt.getNodeName() == "ViaPattern" &&
                        (def trans := patt.getExpr()).getNodeName() == "MethodCallExpr" &&
                        trans.getReceiver().getNodeName() == "NounExpr" &&
                        trans.getReceiver().getName() == "_matchSame") {
                        def isSame := trans.getVerb() == "run"
                        def [spec] := trans.getArgs()
                        def test := sameEver(sp, spec, isSame, span)
                        def f := if (isSame) { `Not same as $spec` } else {
                            `Same as $spec`
                        }
                        def failure := litExpr(f, span)
                        [test, body, failure, null]
                    } else {
                        def failure := tempNounExpr("failure", span)
                        def ej := tempNounExpr("ej", span)
                        [patt, body, failure, ej]
                    }
                }]
                var block := callExpr(nounExpr("_switchFailed", span), "run",
                    [sp] + [for [_, _, f, _] in (clauses) f], [], span)
                for [head, body, fail, ej] in (clauses.reverse()):
                    if (ej == null):
                        block := emitIf(head, body, block, span)
                    else:
                        block := makeEscapeExpr(
                            plainPatt(ej, span),
                            seqExpr([defExpr(head, ej, sp, span), body], span),
                            plainPatt(fail, span),
                            block, span)
                builder.HideExpr(seqExpr([
                    defExpr(plainPatt(sp, span), null, expr, span),
                    block], span), span)
            match =="TryExpr":
                def [tryblock, catchers, finallyblock] := args
                var block := tryblock
                for cat in (catchers):
                    block := builder.CatchExpr(block, cat.getPattern(), cat.getBody(), span)
                if (finallyblock != null):
                    block := builder.FinallyExpr(block, finallyblock, span)
                block
            match =="WhileExpr":
                def [test, block, catcher] := args
                makeEscapeExpr(
                    plainPatt(nounExpr("__break", span), span),
                        callExpr(nounExpr("_loop", span), "run",
                            [nounExpr("_iterForever", span),
                             builder.ObjectExpr(null, ignorePatt(null, span), null, [],
                                builder.Script(null,
                                    [builder."Method"(null, "run",
                                         [ignorePatt(null, span),
                                         ignorePatt(null, span)],
                                         [],
                                         nounExpr("Bool", span),
                                             emitIf(
                                                 test,
                                                 seqExpr([
                                                     makeEscapeExpr(
                                                         plainPatt(
                                                             nounExpr("__continue", span),
                                                             span),
                                                         block, null, null, span),
                                                     nounExpr("true", span)],
                                                span), callExpr(nounExpr("__break", span), "run", [], [], span), span), span)],
                                     [], span), span)], [], span),
                    if (catcher !=null) {catcher.getPattern()},
                     if (catcher !=null) {catcher.getBody()}, span)
            match =="WhenExpr":
                def [promiseExprs, block, catchers, finallyblock] := args
                def expr := switch (promiseExprs) {
                    match [] { nounExpr("null", span) }
                    match [ex] { ex }
                    match _ {
                        callExpr(
                            nounExpr("promiseAllFulfilled", span), "run",
                            [emitList(promiseExprs, span)], [], span)
                    }
                }
                def resolution := tempNounExpr("resolution", span)
                # NB: Not using `emitIf` when we know that the test is neither
                # `true` nor `false`. ~ C.
                def whenblock := builder.IfExpr(
                    callExpr(nounExpr("Ref", span), "isBroken",
                         [resolution], [], span),
                    resolution, block, span)
                def prob2 := tempNounExpr("problem", span)
                var handler := prob2
                if (catchers.isEmpty()):
                    # No when-broken clauses to emit.
                    handler := seqExpr([
                        callExpr(nounExpr("traceln", span), "run", [litExpr("Unhandled broken promise at " + M.toString(span), span)], [], span),
                        callExpr(nounExpr("traceln", span), "exception", [prob2], [], span),
                        callExpr(nounExpr("Ref", span), "broken", [prob2], [], span),
                    ], span)
                for cat in (catchers):
                    def fail := tempNounExpr("fail", cat.getSpan())
                    handler := makeEscapeExpr(
                        plainPatt(fail, cat.getSpan()),
                        seqExpr([
                            defExpr(cat.getPattern(),
                                            fail,
                                            prob2, cat.getSpan()),
                            cat.getBody()], cat.getSpan()),
                        ignorePatt(null, cat.getSpan()), handler, cat.getSpan())
                def broken := tempNounExpr("broken", span)
                def wb := callExpr(
                        nounExpr("Ref", span), "when", [
                            expr,
                            makeFn("when-near",
                                   [plainPatt(resolution, span)], [],
                                   whenblock,
                                   expr.getSpan()),
                            makeFn(
                                "when-broken",
                                [plainPatt(broken, span)], [],
                                seqExpr([
                                    defExpr(
                                        plainPatt(prob2, span),
                                        null,
                                        callExpr(
                                            nounExpr("Ref", span), "optProblem",
                                            [broken], [], span), span), handler], span), span)],
                        [], span)
                if (finallyblock == null):
                    wb
                else:
                    callExpr(
                        wb, "_whenMoreResolved",
                        [makeFn("when-finally",
                                [ignorePatt(null, span)], [],
                                finallyblock, span)], [], span)
            match nodeName:
                M.call(builder, nodeName, args + [span], [].asMap())

    def reifyTemporaries(tree):
        def nameList := [].diverge()
        def seen := [].asMap().diverge()
        var i := 0

        # AST nodes uncall to a special maker, so we need to capture the maker
        # for nouns. We'll use this to accelerate the recursion.
        def nounMaker := builder.NounExpr("hack", null)._uncall()[0]

        def nameFinder(node):
            # If it's a noun, then save its name. Otherwise, recurse.
            if (node._uncall() =~ [maker, _, args, _]):
                if (maker == nounMaker):
                    nameList.push(args[0])
                else:
                    for arg in (args):
                        nameFinder(arg)

        nameFinder(tree)
        def names := nameList.asSet()

        def renameTransformer(node, _maker, args, span):
            def nodeName := node.getNodeName()
            if (nodeName == "TempNounExpr"):
                return seen.fetch(node, fn {
                    var noun := null
                    while (true) {
                        i += 1
                        def name := `${args[0]}_$i`
                        if (!names.contains(name)) {
                            noun := nounExpr(name, span)
                            break
                        }
                    }
                    seen[node] := noun
                    noun
                })
            else:
                return M.call(builder, nodeName, args + [span], [].asMap())
        return tree.transform(renameTransformer)

    def defaultPattDF(patt):
        return if (patt.getNodeName() == "FinalPattern") {
            var g := patt.getGuard()
            if (g == null) { g := nounExpr("DeepFrozen", patt.getSpan()) }
            builder.FinalPattern(patt.getNoun(), g, patt.getSpan())
        } else { patt }

    def turnImportPattsDF(item):
        return switch (item.getNodeName()) {
            match =="MapPatternAssoc" {
                builder.MapPatternAssoc(item.getKey(),
                                        defaultPattDF(item.getValue()),
                                        item.getDefault(), item.getSpan())
            }
            match =="MapPatternImport" {
                builder.MapPatternImport(defaultPattDF(item.getValue()),
                                         item.getDefault(), item.getSpan())
            }
        }

    def moduleImports(ast, maker, args, span):
        "Desugar module import-patterns to standard Full-Monte patterns."

        if (ast.getNodeName() == "Module"):
            def [imps, exps, body] := args
            def newImps := [for imp in (imps) {
                def patt := imp.getPattern()
                if (patt.getNodeName() == "MapPattern" && patt.getTail() == null) {
                    def ignorePatt := builder.IgnorePattern(null, patt.getSpan())
                    def newItems := [for item in (patt.getPatterns()) turnImportPattsDF(item)]
                    def newPatt := builder.MapPattern(newItems, ignorePatt,
                                                      patt.getSpan())
                    builder."Import"(imp.getName(), newPatt, imp.getSpan())
                } else { imp }
            }]
            return maker(newImps, exps, body, span)

        return M.call(maker, "run", args + [span], [].asMap())

    var ast := node

    # Appetizers.

    # Fix up import patterns.
    ast transform= (moduleImports)

    # Pre-expand certain simple if-expressions. The transformation isn't total
    # but covers many easy cases and doesn't require temporaries.
    ast transform= (ifAnd)
    ast transform= (ifOr)

    # Do sends within sequences.
    ast transform= (seqSendOnly)

    # The main course. Expand everything not yet expanded.
    ast transform= (expandTransformer)
    ast := reifyTemporaries(ast)

    # Dessert.

    # "Expand" modular exponentation. There is extant Monte code which only
    # runs to completion in reasonable time when this transformation is
    # applied.
    ast transform= (modPow)

    return ast
