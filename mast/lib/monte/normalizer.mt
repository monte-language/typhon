exports (normalize, anfTransform, normalize0)

def normalize(ast, builder) as DeepFrozen:

    def normalizeTransformer(node, _maker, args, span):
        return switch (node.getNodeName()):
            match =="LiteralExpr":
                switch (args[0]):
                    match ==null:
                        builder.NullExpr(span)
                    match i :Int:
                        builder.IntExpr(i, span)
                    match s :Str:
                        builder.StrExpr(s, span)
                    match c :Char:
                        builder.CharExpr(c, span)
                    match d :Double:
                        builder.DoubleExpr(d, span)
            match =="AssignExpr":
                def [_name, rvalue] := args
                builder.AssignExpr(node.getLvalue().getName(), rvalue, span)
            match =="BindingExpr":
                builder.BindingExpr(node.getNoun().getName(), span)
            match =="CatchExpr":
                def [body, patt, catchbody] := args
                builder.TryExpr(body, patt, catchbody, span)
            match =="MethodCallExpr":
                def [obj, verb, margs, namedArgs] := args
                builder.CallExpr(obj, verb, margs, namedArgs, span)
            match =="EscapeExpr":
                if (args =~ [patt, body, ==null, ==null]):
                    builder.EscapeOnlyExpr(patt, body, span)
                else:
                    def [ejPatt, ejBody, catchPatt, catchBody] := args
                    builder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody, span)
            match =="ObjectExpr":
                def [doc, name, asExpr, auditors, [methods, matchers]] := args
                builder.ObjectExpr(if (doc == null) {""} else {doc}, name,
                                   [asExpr] + auditors, methods, matchers,
                                   span)
            match =="Script":
                def [_, methods, matchers] := args
                [methods, matchers]
            match =="IgnorePattern":
                def [guard] := args
                builder.IgnorePatt(guard, span)
            match =="BindingPattern":
                builder.BindingPatt(node.getNoun().getName(), span)
            match =="FinalPattern":
                def [_, guard] := args
                builder.FinalPatt(node.getNoun().getName(), guard, span)
            match =="VarPattern":
                def [_, guard] := args
                builder.VarPatt(node.getNoun().getName(), guard, span)
            match =="ListPattern":
                def [patts, _] := args
                builder.ListPatt(patts, span)
            match =="ViaPattern":
                def [expr, patt] := args
                builder.ViaPatt(expr, patt, span)
            match =="NamedArg":
                def [key, value] := args
                builder.NamedArgExpr(key, value, span)
            match =="NamedParam":
                def [k, p, d] := args
                builder.NamedPattern(k, p, d, span)
            match =="Matcher":
                def [patt, body] := args
                builder.MatcherExpr(patt, body, span)
            match =="Method":
                def [doc, verb, patts, namedPatts, guard, body] := args
                builder.MethodExpr(if (doc == null) {""} else {doc}, verb,
                                   patts, namedPatts, guard, body, span)
            match nodeName:
                M.call(builder, nodeName, args + [span], [].asMap())

    return ast.transform(normalizeTransformer)

def makeLetBinder(n, builder, [outerNames, &seq, parent]) as DeepFrozen:
    def letBindings := [].diverge()
    return object letBinder:
        to getI(ast0):
            return n.immediate(ast0, builder, letBinder)
        to getC(ast0):
            return n.complex(ast0, builder, letBinder)
        to getP(patt, exit_, expr):
            n.pattern(patt, exit_, expr, builder, letBinder)
        to addBinding(name :Str, bindingExpr, span):
            if (outerNames.contains(name)):
                throw(`$name cannot be shadowed`)
            for [_, _, lname, lspan] in (letBindings):
                if (lname != "" && lname == name):
                    throw(`Error at $span: "$name" already defined at $lspan`)
            letBindings.push([seq += 1, bindingExpr, name, span])
            return seq
        to addTempBinding(bindingExpr, span):
            return letBinder.addBinding("", builder.TempBinding(bindingExpr, span), span)
        to getDefs():
            return [outerNames, &seq, letBinder]
        to getSeq():
            return seq
        to getBindings():
            return letBindings
        to getIndexFor(name, span):
            for [idx, binding, lname, _] in (letBindings):
                if (lname == name):
                    return idx
            if (parent == null):
                if ((def i := outerNames.indexOf(name)) >= 0):
                    return i
                throw(`Undefined name $name at $span`)

            return parent.getIndexFor(name, span)

        to guardCoerceFor(speci, gi, ei, span):
            return builder.TempExpr(
                letBinder.addTempBinding(builder.GuardCoerce(speci, gi, ei, span), span), span)
        to letExprFor(expr, span):
            return if (letBindings.isEmpty()) {
                expr
            } else if (expr.getNodeName() == "TempExpr" &&
                       (letBindings.last()[0] == expr.getIndex())) {
                if (letBindings.size() == 1) {
                    letBindings[0][1].getValue()
                } else {
                    builder.LetExpr([for args in
                                 (letBindings.slice(0, letBindings.size() - 1))
                                 M.call(builder, "LetDef", args, [].asMap())],
                                letBindings.last()[1].getValue(), span)
                }
            } else {
                builder.LetExpr([for args in (letBindings)
                                 M.call(builder, "LetDef", args, [].asMap())],
                                expr, span)
            }

def makeParamBinder(count, [outerNames, &seq, parent]) as DeepFrozen:
    def paramBindings := [for _ in (0..!count) seq += 1]
    object paramBinder:
        to getIndexFor(name, span):
            return parent.getIndexFor(name, span)
        to getDefs():
            return [outerNames, &seq, parent]
    return [paramBinder, paramBindings]

object anfTransform as DeepFrozen:
    to run(ast, outerNames, builder):
        var gensym_seq :Int := outerNames.size() - 1
        return [anfTransform.normalize(ast, builder, [outerNames, &gensym_seq, null]), gensym_seq]

    to normalize(ast, builder, defs):
        def binder := makeLetBinder(anfTransform, builder, defs)
        def expr := anfTransform.immediate(ast, builder, binder)
        return binder.letExprFor(expr, ast.getSpan())

    to immediate(ast, builder, binder):
        def nn := ast.getNodeName()
        def span := ast.getSpan()
        if (nn == "LiteralExpr"):
            return switch (ast.getValue()) {
                match ==null  {builder.NullExpr(span)}
                match i :Int  {builder.IntExpr(i, span)}
                match s :Str  {builder.StrExpr(s, span)}
                match c :Char {builder.CharExpr(c, span)}
                match d :Double {builder.DoubleExpr(d, span)}
                match v {throw("Unknown literal " + M.toQuote(v))}
            }
        else if (nn == "NounExpr"):
            if (ast.getName() == "null"):
                return builder.NullExpr(span)
            return builder.NounExpr(
                def n := ast.getName(),
                binder.getIndexFor(n, span),
                span)
        else if (nn == "BindingExpr"):
            return builder.BindingExpr(
                def n := ast.getNoun().getName(),
                binder.getIndexFor(n, span),
                span)
        else if (nn == "MetaContextExpr"):
            return builder.MetaContextExpr()
        else if (nn == "MetaStateExpr"):
            return builder.MetaStateExpr()
        else:
            return builder.TempExpr(
                binder.addTempBinding(anfTransform.complex(ast, builder, binder), span),
                span)

    to complex(ast, builder, binder):
        def span := ast.getSpan()
        def nn := ast.getNodeName()
        if (nn == "AssignExpr"):
            def bi := binder.addTempBinding(
                builder.CallExpr(
                    builder.BindingExpr(def n := ast.getLvalue().getName(),
                                        binder.getIndexFor(n, span),
                                        span),
                    "get", [], [], span), span)
            return builder.CallExpr(
                builder.TempExpr(bi, span),
                "put", [binder.getI(ast.getRvalue())], [], span)
        else if (nn == "DefExpr"):
            def expr := binder.getI(ast.getExpr())
            def ei := if ((def ex := ast.getExit()) != null) {
                binder.getI(ex)
            } else { null }
            binder.getP(ast.getPattern(), ei, expr)
            return expr
        else if (nn == "EscapeExpr"):
            def [paramBox, [ei]] := makeParamBinder(1, binder.getDefs())
            def innerBinder := makeLetBinder(anfTransform, builder, paramBox.getDefs())
            innerBinder.getP(ast.getEjectorPattern(), null, builder.TempExpr(ei, span))
            def b := innerBinder.letExprFor(innerBinder.getC(ast.getBody()), span)
            if (ast.getCatchPattern() == null):
                return builder.EscapeOnlyExpr(ei, b, span)
            else:
                def [paramBox, [pi]] := makeParamBinder(1, binder.getDefs())
                def catchBinder := makeLetBinder(anfTransform, builder, paramBox.getDefs())
                catchBinder.getP(ast.getCatchPattern(), null, builder.TempExpr(pi, span))
                def cb := catchBinder.letExprFor(catchBinder.getC(ast.getCatchBody()),
                                                 span)
                return builder.EscapeExpr(ei, b, pi, cb, span)
        else if (nn == "FinallyExpr"):
            return builder.FinallyExpr(
                anfTransform.normalize(ast.getBody(), builder, binder.getDefs()),
                anfTransform.normalize(ast.getUnwinder(), builder, binder.getDefs()),
                span)
        else if (nn == "HideExpr"):
            # XXX figure out a renaming scheme to avoid inner-let
            return anfTransform.normalize(ast.getBody(), builder, binder.getDefs())
        else if (nn == "MethodCallExpr"):
            def r := binder.getI(ast.getReceiver())
            def argList := [for arg in (ast.getArgs()) binder.getI(arg)]
            def namedArgList := [for na in (ast.getNamedArgs())
                                 builder.NamedArgExpr(binder.getI(na.getKey()),
                                                      binder.getI(na.getValue()),
                                                      na.getSpan())]
            return builder.CallExpr(r, ast.getVerb(), argList, namedArgList, span)
        else if (nn == "IfExpr"):
            def test := binder.getI(ast.getTest())
            def alt := anfTransform.normalize(ast.getThen(), builder, binder.getDefs())
            def consq := switch (ast.getElse()) {
                match ==null {builder.NullExpr(span)}
                match e {anfTransform.normalize(e, builder, binder.getDefs())}}
            return builder.IfExpr(test, alt, consq, span)
        else if (nn == "SeqExpr"):
            def exprs := ast.getExprs()
            for item in (exprs.slice(0, exprs.size() - 1)):
                binder.getI(item)
            return binder.getC(exprs.last())
        else if (nn == "CatchExpr"):
            def b := anfTransform.normalize(ast.getBody(), builder, binder.getDefs())
            def [paramBox, [ci]] := makeParamBinder(1, binder.getDefs())
            def catchBinder := makeLetBinder(anfTransform, builder, paramBox.getDefs())
            catchBinder.getP(ast.getPattern(), null, builder.TempExpr(ci, span))
            def cb := catchBinder.letExprFor(
                catchBinder.getC(ast.getCatcher()), span)
            return builder.TryExpr(b, ci, cb, span)
        else if (nn == "ObjectExpr"):
            def ai := if ((def asExpr := ast.getAsExpr()) != null) {
                [binder.getI(asExpr)]
            } else {
                [builder.NullExpr(span)]
            } + [for aud in (ast.getAuditors()) binder.getI(aud)]
            def objectBinding
            def oi := builder.TempExpr(binder.addBinding("", objectBinding, span), span)
            def op := ast.getName()
            # FinalPattern/VarPattern must be handled specially to implement 'as'.
            if (ast.getAsExpr() != null):
                if (op.getNodeName() == "FinalPattern"):
                    binder.addBinding(op.getNoun().getName(),
                                      builder.FinalBinding(oi, ai[0], span), span)
                else if (op.getNodeName() == "VarPattern"):
                    binder.addBinding(op.getNoun().getName(),
                                      builder.VarBinding(oi, ai[0], span), span)
                else:
                    throw("\"as\" in ObjectExpr not allowed with complex pattern")
            else:
                anfTransform.pattern(op, null, oi, builder, binder)

            def methods := [].diverge()
            def matchers := [].diverge()
            for meth in (ast.getScript().getMethods()):
                def [paramBox, allParami] := makeParamBinder(meth.getParams().size() + 1,
                                                             binder.getDefs())
                def methBinder := makeLetBinder(anfTransform, builder,
                                                paramBox.getDefs())
                def parami := allParami.slice(0, allParami.size() - 1)
                def namedParami := allParami.last()
                for i => p in (meth.getParams()):
                    methBinder.getP(p, null, builder.TempExpr(parami[i], span))
                for np in (meth.getNamedParams()):
                    def npi := methBinder.addTempBinding(builder.NamedParamExtract(
                        namedParami,
                        methBinder.getI(np.getKey()),
                        methBinder.getI(np.getDefault()), span), span)
                    methBinder.getP(np.getValue(), null,
                                    builder.TempExpr(npi, span))
                def g := meth.getResultGuard()
                def gb := if (g == null) {
                    methBinder.getC(meth.getBody())
                } else {
                    methBinder.guardCoerceFor(methBinder.getI(meth.getBody()),
                                              methBinder.getI(g),
                                              builder.NullExpr(span),
                                              span)
                }
                methods.push(
                    builder."Method"(meth.getDocstring(), meth.getVerb(),
                                     parami, namedParami,
                                     methBinder.letExprFor(gb, span), span))
            for matcher in (ast.getScript().getMatchers()):
                def [paramBox, [mi]] := makeParamBinder(1, binder.getDefs())
                def matcherBinder := makeLetBinder(anfTransform, builder,
                                                   paramBox.getDefs())
                matcherBinder.getP(matcher.getPattern(), null,
                                   builder.TempExpr(mi, span))
                matchers.push(builder.Matcher(
                    mi, matcherBinder.letExprFor(
                        matcherBinder.getC(matcher.getBody()), span), span))
            bind objectBinding := builder.TempBinding(builder.ObjectExpr(
                ast.getDocstring(),
                ast, ai,
                methods.snapshot(),
                matchers.snapshot(),
                span), span)
            return oi
        else if (["LiteralExpr", "NounExpr", "BindingExpr", "MetaStateExpr", "MetaContextExpr"].contains(nn)):
            return anfTransform.immediate(ast, builder, binder)
        else:
            throw(`Unrecognized node $ast (type ${try {ast.getNodeName()} catch _ {"unknown"}})`)

    to pattern(p, exitNode, si, builder, binder):
        def span := p.getSpan()
        def ei := if (exitNode == null) {
            builder.NullExpr(span)
        } else {
            exitNode
        }
        def pn := p.getNodeName()

        def matchSlot(slotNode):
            var si2 := si
            var gi := builder.NullExpr(span)
            if ((def g := p.getGuard()) != null):
                gi := binder.getI(g)
                si2 := binder.guardCoerceFor(si, gi, ei, span)
            return binder.addBinding(
                p.getNoun().getName(),
                slotNode(si2, gi, span),
                span)


        if (pn == "FinalPattern"):
            matchSlot(builder.FinalBinding)
        else if (pn == "VarPattern"):
            matchSlot(builder.VarBinding)
        else if (pn == "BindingPattern"):
            binder.addBinding(p.getNoun().getName(), si, span)
        else if (pn == "IgnorePattern"):
            def gi := if ((def g := p.getGuard()) != null) {
                binder.getI(g)
            } else {
                builder.NullExpr(span)
            }
            binder.guardCoerceFor(si, gi, ei, span)
        else if (pn == "ListPattern"):
            def ps := p.getPatterns()
            def li := builder.TempExpr(
                binder.addTempBinding(builder.ListCoerce(
                    si, ps.size(), ei, span), span), span)
            for idx => subp in (ps):
                def subi := binder.addTempBinding(
                    builder.CallExpr(li, "get",
                                     [builder.IntExpr(idx, span)], [],
                                     span), span)
                binder.getP(subp, ei, builder.TempExpr(subi, span))
        else if (pn == "ViaPattern"):
            def vi := binder.getI(p.getExpr())
            def si2 := binder.addTempBinding(builder.CallExpr(
                vi, "run", [si, ei], [], span), span)
            binder.getP(p.getPattern(), exitNode, builder.TempExpr(si2, span))
        return binder.getBindings()

# Storage class. Binding and usage are used to determine how to store refs in
# the object frame.

def [BINDING :Int, NOUN :Int, UNUSED :Int] := [0, 1, 2]

def layoutScopes(topExpr, builder) as DeepFrozen:
    def allNames := [].asMap().diverge()
    def accessTypes := [].asMap().diverge()
    def _layoutScopes(ast):
        def layoutExprList(exprs):
            var freeNames := [].asSet()
            def newExprs := [].diverge()
            var localSize := 0
            for a in (exprs):
                def [new, newFreeNames, ls] := _layoutScopes(a)
                freeNames |= newFreeNames
                localSize := localSize.max(ls)
                newExprs.push(new)
            return [newExprs.snapshot(), freeNames, localSize]
        def nn := ast.getNodeName()
        if (nn == "TempExpr"):
           return [builder.TempExpr(ast.getIndex(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "LetExpr"):
            def newExprs := [].diverge()
            def newDefs := [].diverge()
            def boundNames := [].asSet().diverge()
            var freeNames := [].asSet()
            var subLocalSize := 0
            # Process all of the exprs in let defs, process the body, then go
            # through defs _again_ to construct final form with storage type
            # (NOUN, BINDING).
            for letdef in (ast.getDefs()):
                def binding := letdef.getExpr()
                if (!binding.getNodeName().endsWith("Binding")):
                    def [newBinding, bFreeNames, bLocalSize] := _layoutScopes(binding)
                    newExprs.push(newBinding)
                    freeNames |= bFreeNames
                    subLocalSize max= (bLocalSize)
                else:
                    def expr := binding.getValue()
                    def [newExpr, eFreeNames, eLocalSize] := _layoutScopes(expr)
                    freeNames |= eFreeNames
                    subLocalSize max= (eLocalSize)
                    def guard := if (["VarBinding", "FinalBinding"].contains(
                        binding.getNodeName())) {
                            def [newGuard, gf, gls] := _layoutScopes(binding.getGuard())
                            freeNames |= gf
                            subLocalSize max= (gls)
                            newGuard
                        } else { null }
                    newExprs.push([newExpr, guard])
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            freeNames |= bFreeNames
            subLocalSize max= (bLocalSize)
            # All references to names bound in this LetExpr have now been seen.
            # We can now decide which bindings can be deslotified. Since
            # deslotification requires rewriting NounExprs, we leave that for a
            # future pass. Maybe.
            for i => letdef in (ast.getDefs()):
                def binding := letdef.getExpr()
                def bn := binding.getNodeName()
                if (bn == "TempBinding"):
                    def [newVal, ==null] := newExprs[i]
                    newDefs.push(builder.LetDef(
                        letdef.getIndex(),
                        builder.TempBinding(newVal, binding.getSpan()),
                        "", letdef.getSpan()))
                else:
                    def newBinding := if (bn == "FinalBinding") {
                        def [newVal, newGuard] := newExprs[i]
                        builder.FinalBinding(newVal, newGuard,
                                             accessTypes.fetch(letdef.getIndex(),
                                                               fn{UNUSED}),
                                             binding.getSpan())
                    } else if (bn == "VarBinding") {
                        def [newVal, newGuard] := newExprs[i]
                        builder.VarBinding(newVal, newGuard,
                                           accessTypes.fetch(letdef.getIndex(),
                                                             fn{UNUSED}),
                                           binding.getSpan())
                    } else {
                        newExprs[i]
                    }
                    allNames[letdef.getIndex()] := newBinding
                    boundNames.include(letdef.getIndex())
                    newDefs.push(builder.LetDef(letdef.getIndex(), newBinding,
                                                letdef.getName(), letdef.getSpan()))
            return [builder.LetExpr(newDefs.snapshot(), newBody, ast.getSpan()),
                    freeNames &! boundNames,
                    boundNames.size() + subLocalSize]
        else if (nn == "ObjectExpr"):
            def [newAuditors, aNames, localSize] := layoutExprList(ast.getAuditors())
            def newMethods := [].diverge()
            var frameNames := [].asSet()
            for m in (ast.getMethods()):
                def [newBody, mFreeNames, mls] := _layoutScopes(m.getBody())
                frameNames |= mFreeNames
                newMethods.push(builder.MethodExpr(
                    m.getDocstring(), m.getVerb(),
                    m.getParams(), m.getNamedParams(),
                    newBody, mls, m.getSpan()))
            def newMatchers := [].diverge()
            for m in (ast.getMatchers()):
                def [newBody, mFreeNames, mls] := _layoutScopes(m.getBody())
                frameNames |= mFreeNames
                newMatchers.push(builder.Matcher(
                    m.getPattern(), newBody, mls, m.getSpan()))
            return [builder.ObjectExpr(ast.getDocstring(), ast.getKernelAST(),
                                       newAuditors.snapshot(),
                                       newMethods.snapshot(),
                                       newMatchers.snapshot(),
                                       frameNames, ast.getSpan()),
                    aNames,
                    localSize]
        else if (nn == "NounExpr"):
            if (!accessTypes.contains(ast.getIndex())):
                accessTypes[ast.getIndex()] := NOUN
            return [builder.NounExpr(ast.getName(), ast.getIndex(), ast.getSpan()),
                    [ast.getIndex()].asSet(), 0]
        else if (nn == "BindingExpr"):
            accessTypes[ast.getIndex()] := BINDING
            return [builder.BindingExpr(ast.getName(), ast.getIndex(),
                                        ast.getSpan()),
                    [ast.getIndex()].asSet(), 0]
        else if (nn == "IntExpr"):
            return [builder.IntExpr(ast.getI(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "DoubleExpr"):
            return [builder.DoubleExpr(ast.getD(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "CharExpr"):
            return [builder.CharExpr(ast.getC(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "StrExpr"):
            return [builder.StrExpr(ast.getS(), ast.getSpan()), [].asSet(), 0]
        else if (nn == "NullExpr"):
            return [builder.NullExpr(ast.getSpan()), [].asSet(), 0]
        else if (nn == "MetaContextExpr"):
            return [builder.MetaContextExpr(ast.getSpan()), [].asSet(), 0]
        else if (nn == "MetaStateExpr"):
            return [builder.MetaContextExpr(ast.getSpan()), [].asSet(), 0]
        else if (nn == "CallExpr"):
            def [newRcvr, rFreeNames, rLocalSize] := _layoutScopes(ast.getReceiver())
            def [newArgs, aFreeNames, aLocalSize] := layoutExprList(ast.getArgs())
            def [newNArgs, nFreeNames, nLocalSize] := layoutExprList(ast.getNamedArgs())
            return [builder.CallExpr(newRcvr, ast.getVerb(), newArgs, newNArgs,
                                     ast.getSpan()),
                    rFreeNames | aFreeNames | nFreeNames,
                    rLocalSize.max(aLocalSize).max(nLocalSize)]
        else if (nn == "NamedArgExpr"):
            def [newK, kFreeNames, kLocalSize] := _layoutScopes(ast.getKey())
            def [newV, vFreeNames, vLocalSize] := _layoutScopes(ast.getValue())
            return [builder.NamedArgExpr(newK, newV, ast.getSpan()),
                    kFreeNames | vFreeNames,
                    kLocalSize.max(vLocalSize)]
        else if (nn == "TryExpr"):
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            def [newCatchBody, cFreeNames, cLocalSize] := _layoutScopes(
                ast.getCatchBody())
            return [builder.TryExpr(newBody, ast.getCatchPattern(),
                                    newCatchBody, ast.getSpan()),
                    bFreeNames | cFreeNames,
                    bLocalSize.max(cLocalSize)]
        else if (nn == "FinallyExpr"):
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            def [newUnwinder, uFreeNames, uLocalSize] := _layoutScopes(
                ast.getUnwinder())
            return [builder.FinallyExpr(newBody, newUnwinder, ast.getSpan()),
                    bFreeNames | uFreeNames,
                    bLocalSize.max(uLocalSize)]
        else if (nn == "EscapeExpr"):
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            def [newCatchBody, cFreeNames, cLocalSize] := _layoutScopes(
                ast.getCatchBody())
            return [builder.EscapeExpr(ast.getEjectorPattern(), newBody,
                                       ast.getCatchPattern(), newCatchBody,
                                       ast.getSpan()),
                    bFreeNames | cFreeNames,
                    bLocalSize.max(cLocalSize)]
        else if (nn == "EscapeOnlyExpr"):
            def [newBody, bFreeNames, bLocalSize] := _layoutScopes(ast.getBody())
            return [builder.EscapeOnlyExpr(ast.getEjectorPattern(), newBody,
                                       ast.getSpan()),
                    bFreeNames,
                    bLocalSize]
        else if (nn == "IfExpr"):
            def [newTest, tFreeNames, tLocalSize] := _layoutScopes(ast.getTest())
            def [newConsq, cFreeNames, cLocalSize] := _layoutScopes(ast.getThen())
            def [newAlt, aFreeNames, aLocalSize] := _layoutScopes(ast.getElse())
            return [builder.IfExpr(newTest, newConsq, newAlt, ast.getSpan()),
                    tFreeNames | cFreeNames | aFreeNames,
                    tLocalSize.max(cLocalSize).max(aLocalSize)]
        else if (nn == "GuardCoerce"):
            def [newSpecimen, sFreeNames, sLocalSize] := _layoutScopes(
                ast.getSpecimen())
            def [newGuard, gFreeNames, gLocalSize] := _layoutScopes(ast.getGuard())
            def [newExit, eFreeNames, eLocalSize] := _layoutScopes(ast.getExit())
            return [builder.GuardCoerce(newSpecimen, newGuard, newExit, ast.getSpan()),
                    sFreeNames | gFreeNames | eFreeNames,
                    sLocalSize.max(gLocalSize).max(eLocalSize)]
        else if (nn == "ListCoerce"):
            def [newSpecimen, sFreeNames, sLocalSize] := _layoutScopes(
                ast.getSpecimen())
            def [newExit, eFreeNames, eLocalSize] := _layoutScopes(ast.getExit())
            return [builder.ListCoerce(newSpecimen, ast.getSize(), newExit,
                                        ast.getSpan()),
                    sFreeNames | eFreeNames,
                    sLocalSize.max(eLocalSize)]
        else if (nn == "NamedParamExtract"):
            def [newParams, pFreeNames, pLocalSize] := _layoutScopes(
                ast.getParams())
            def [newKey, kFreeNames, kLocalSize] := _layoutScopes(ast.getKey())
            def [newDefault, dFreeNames, dLocalSize] := _layoutScopes(ast.getDefault())
            return [builder.NamedParamExtract(newParams, newKey, newDefault,
                                              ast.getSpan()),
                    pFreeNames | kFreeNames | dFreeNames,
                    pLocalSize.max(kLocalSize).max(dLocalSize)]

    def [expr, _freeNames, _localSize] := _layoutScopes(topExpr)
    return [expr, allNames]

def [FINAL :Int, VAR_ :Int] := [1, 2]
# you're aware i'm a bad person, right?

def [OUTER :Int, FRAME :Int, LOCAL :Int] := [0, 1, 2]

def asPrettyIndex(i :Int) :Str as DeepFrozen:
    return _makeStr.fromChars([for c in (M.toString(i)) '\u2050' + c.asInteger()])

def makeAddress(scope :Int, region :Int, mode :Int, index :Int) as DeepFrozen:
    return object address as DeepFrozen:
        to _printOn(out):
            if (scope == FRAME):
                out.print("⒡")
            else if (scope == LOCAL):
                out.print("⒧")
            if (region == BINDING):
                out.print("ʙ")
            else if (region == VAR_):
                out.print("ᴠ")
            else:
                out.print("ꜰ")
            if (mode == BINDING):
                out.print("⅋")
            out.print(asPrettyIndex(index))
        to getScope():
            return scope
        to getRegion():
            return region
        to getMode():
            return mode
        to getIndex():
            return index

def specializeNouns([topExpr, allNames], outerNames, builder, var gensym_seq, inRepl) as DeepFrozen:
    # Maps global noun indices to address objects
    def allAddresses := [].asMap().diverge()
    # Stack of variable names in closures being traversed
    def frameNameStack := [[]].diverge()
    # Frame layouts for closures being traversed
    def frameStack := [].diverge()
    # Local layouts for methods being traversed
    def localStack := [].diverge()
    # stack of letdef-lists (so NounExprs accessing bindings can add temps for
    # their .get() calls)
    def letdefStack := [[].diverge()].diverge()
    def pushLocalStack():
        localStack.push([
            [].asMap().diverge(),
            [].asMap().diverge(),
            [].asMap().diverge()])
    def pushFrameStack():
        frameStack.push([
            [].asMap().diverge(),
            [].asMap().diverge(),
            [].asMap().diverge()])
    pushLocalStack()
    def addNewAddress(idx):
        traceln(`addNewAddress $idx`)
        if (idx < outerNames.size()):
            def a := if (inRepl) {
                # outers may include bindings from previous interactions
                makeAddress(OUTER, BINDING, BINDING, idx)
            } else {
                # XXX determine if we can prove this by this point
                makeAddress(OUTER, NOUN, FINAL, idx)
            }
            allAddresses[idx] := a
            traceln(`allAddresses $allAddresses`)
            return a

        if (frameNameStack.last().contains(idx)):
            # mentioned in frame
            def la := allAddresses[idx]
            if (frameStack.last()[la.getRegion()].contains(idx)):
                return frameStack.last()[la.getRegion()][idx]
            # tow this binding outside the environment
            def a := makeAddress(FRAME, la.getRegion(), la.getMode(),
                               frameStack.last()[la.getRegion()].size())
            frameStack.last()[la.getRegion()][idx] := la
            return a

        # not outer or frame, must be local
        def b := allNames[idx]
        if (allAddresses.contains(idx)):
            return allAddresses[idx]

        def a := if (b.getNodeName() == "FinalBinding") {
            makeAddress(LOCAL, FINAL, b.getStorage(),
                               localStack.last()[FINAL].size())
        } else if (b.getNodeName() == "VarBinding") {
            makeAddress(LOCAL, VAR_, b.getStorage(),
                               localStack.last()[VAR_].size())
        } else {
            makeAddress(LOCAL, BINDING, BINDING,
                               localStack.last()[BINDING].size())
        }
        localStack.last()[a.getRegion()][idx] := a
        allAddresses[idx] := a
        traceln(`allAddresses $allAddresses`)
        return a

    def _specializeNouns(ast):
        def specializeExprList(exprs):
            return [for ex in (exprs) {def ey := _specializeNouns(ex); traceln(`Produced $ey`); ey}]
        def nn := ast.getNodeName()
        traceln(`Entered $ast $nn`)
        if (nn == "TempExpr"):
            allAddresses[ast.getIndex()] := null
            return builder.TempExpr(ast.getIndex(), ast.getSpan())
        else if (nn == "LetExpr"):
            # need a way to let processing a single letdef.getExpr() result in multiple new letdefs
            # newExprs needs to become Pair[List[Expr], guard]
            def newExprs := [].diverge()
            def newDefs := [].diverge()
            for letdef in (ast.getDefs()):
                def extras := [].diverge()
                letdefStack.push(extras)
                def binding := letdef.getExpr()
                if (!binding.getNodeName().endsWith("Binding")):
                    newExprs.push([_specializeNouns(binding), "&&", extras])
                else:
                    def expr := binding.getValue()
                    def newExpr  := _specializeNouns(expr)
                    def guard := if (["VarBinding", "FinalBinding"].contains(
                            binding.getNodeName())) {
                         _specializeNouns(binding.getGuard())
                        } else { null }
                    traceln(`$newExpr yielded $extras, letdefstack is $letdefStack`)
                    newExprs.push([newExpr, guard, extras])
                letdefStack.pop()
            def bodyExtras := [].diverge()
            letdefStack.push(bodyExtras)
            def newBody := _specializeNouns(ast.getBody())
            letdefStack.pop()
            traceln(`newExprs $newExprs`)
            for i => letdef in (ast.getDefs()):
                def binding := letdef.getExpr()
                def bn := binding.getNodeName()
                if (bn == "TempBinding"):
                    def [newVal, ==null, extras] := newExprs[i]
                    newDefs.extend(extras)
                    newDefs.push(builder.LetDef(
                        letdef.getIndex(),
                        builder.TempBinding(newVal, binding.getSpan()),
                        "", null, letdef.getSpan()))
                else:
                    def newBinding := if (bn == "FinalBinding") {
                        def [newVal, newGuard, _] := newExprs[i]
                        builder.FinalBinding(newVal, newGuard, binding.getSpan())
                    } else if (bn == "VarBinding") {
                        def [newVal, newGuard, _] := newExprs[i]
                        builder.VarBinding(newVal, newGuard, binding.getSpan())
                    } else {
                        newExprs[i][0]
                    }
                    newDefs.extend(newExprs[i][2])
                    newDefs.push(builder.LetDef(letdef.getIndex(), newBinding,
                                                letdef.getName(),
                                                allAddresses.fetch(
                                                    letdef.getIndex(),
                                                    fn{null}),
                                                letdef.getSpan()))

            return builder.LetExpr(newDefs.snapshot() + bodyExtras.snapshot(),
                                   newBody, ast.getSpan())
        else if (nn == "ObjectExpr"):
            def newAuditors := _specializeNouns(ast.getAuditors())
            def newMethods := [].diverge()
            def newMatchers := [].diverge()
            frameNameStack.push(ast.getFrame())
            pushFrameStack()
            for m in (ast.getMethods()):
                pushLocalStack()
                def newBody := _specializeNouns(ast.getBody())
                newMethods.push(builder."Method"(
                    m.getDocstring(), m.getVerb(),
                    m.getParams(), m.getNamedParams(),
                    newBody, localStack.pop(), m.getSpan()))
            for m in (ast.getMatchers()):
                pushLocalStack()
                def newBody := _specializeNouns(m.getBody())
                newMatchers.push(builder.Matcher(
                    m.getPattern(), newBody, localStack.pop(), m.getSpan()))
            frameNameStack.pop()
            def frame := frameStack.pop().getValues()
            return builder.ObjectExpr(ast.getDocstring(), ast.getKernelAST(),
                                      newAuditors.snapshot(),
                                      newMethods.snapshot(),
                                      newMatchers.snapshot(),
                                      frame, ast.getSpan())
        else if (nn == "NounExpr"):
            traceln(`NounExpr ${ast.getIndex()}`)
            def addr := addNewAddress(ast.getIndex())
            if (addr.getMode() == BINDING):
                traceln(`NounExpr $ast for binding`)
                def b := builder.BindingExpr(
                    ast.getName(), ast.getIndex(),
                    addNewAddress(ast.getIndex()),
                    ast.getSpan())
                def temp1 := gensym_seq
                gensym_seq += 1
                letdefStack.last().push(builder.LetDef(
                    temp1,
                    builder.TempBinding(
                        builder.CallExpr(b, "get", [], [], ast.getSpan()),
                        ast.getSpan()),
                    "", null, ast.getSpan()))

                def temp2 := gensym_seq
                gensym_seq += 1
                letdefStack.last().push(builder.LetDef(
                    temp2,
                    builder.TempBinding(
                        builder.CallExpr(
                            builder.TempExpr(temp1, ast.getSpan()),
                            "get", [], [], ast.getSpan()),
                            ast.getSpan()),
                        "", null, ast.getSpan()))
                traceln(`Extras ${letdefStack.last()}`)
                return builder.TempExpr(temp2, ast.getSpan())
            else:
                return builder.NounExpr(ast.getName(), ast.getIndex(),
                                      addr, ast.getSpan())
        else if (nn == "BindingExpr"):
            return builder.BindingExpr(ast.getName(), ast.getIndex(),
                                       addNewAddress(ast.getIndex()),
                                       ast.getSpan())
        else if (nn == "IntExpr"):
            return builder.IntExpr(ast.getI(), ast.getSpan())
        else if (nn == "DoubleExpr"):
            return builder.DoubleExpr(ast.getD(), ast.getSpan())
        else if (nn == "CharExpr"):
            return builder.CharExpr(ast.getC(), ast.getSpan())
        else if (nn == "StrExpr"):
            return builder.StrExpr(ast.getS(), ast.getSpan())
        else if (nn == "NullExpr"):
            return builder.NullExpr(ast.getSpan())
        else if (nn == "MetaContextExpr"):
            return builder.MetaContextExpr(ast.getSpan())
        else if (nn == "MetaStateExpr"):
            return builder.MetaContextExpr(ast.getSpan())
        else if (nn == "CallExpr"):
            def newRcvr := _specializeNouns(ast.getReceiver())
            def newArgs := specializeExprList(ast.getArgs())
            def newNArgs := specializeExprList(
                ast.getNamedArgs())
            return builder.CallExpr(newRcvr, ast.getVerb(), newArgs, newNArgs,
                                     ast.getSpan())
        else if (nn == "NamedArgExpr"):
            def newK := _specializeNouns(ast.getKey())
            def newV := _specializeNouns(ast.getValue())
            return builder.NamedArgExpr(newK, newV, ast.getSpan())
        else if (nn == "TryExpr"):
            def newBody := _specializeNouns(ast.getBody())
            def newCatchBody := _specializeNouns(ast.getCatchBody())
            return builder.TryExpr(newBody, ast.getCatchPattern(),
                                    newCatchBody, ast.getSpan())
        else if (nn == "FinallyExpr"):
            def newBody := _specializeNouns(ast.getBody())
            def newUnwinder  := _specializeNouns(ast.getUnwinder())
            return builder.FinallyExpr(newBody, newUnwinder, ast.getSpan())
        else if (nn == "EscapeExpr"):
            def newBody := _specializeNouns(ast.getBody())
            def newCatchBody := _specializeNouns(ast.getCatchBody())
            return builder.EscapeExpr(ast.getEjectorPattern(), newBody,
                                      ast.getCatchPattern(), newCatchBody,
                                      ast.getSpan())
        else if (nn == "EscapeOnlyExpr"):
            def newBody := _specializeNouns(ast.getBody())
            return builder.EscapeOnlyExpr(ast.getEjectorPattern(), newBody,
                                          ast.getSpan())
        else if (nn == "IfExpr"):
            def newTest := _specializeNouns(ast.getTest())
            def newConsq := _specializeNouns(ast.getThen())
            def newAlt := _specializeNouns(ast.getElse())
            return builder.IfExpr(newTest, newConsq, newAlt, ast.getSpan())
        else if (nn == "GuardCoerce"):
            def newSpecimen  := _specializeNouns(ast.getSpecimen())
            def newGuard  := _specializeNouns(ast.getGuard())
            def newExit  := _specializeNouns(ast.getExit())
            return builder.GuardCoerce(newSpecimen, newGuard, newExit, ast.getSpan())
        else if (nn == "ListCoerce"):
            def newSpecimen  := _specializeNouns(ast.getSpecimen())
            def newExit  := _specializeNouns(ast.getExit())
            return builder.ListCoerce(newSpecimen, ast.getSize(), newExit,
                                       ast.getSpan())
        else if (nn == "NamedParamExtract"):
            def newParams  := _specializeNouns(ast.getParams())
            def newKey := _specializeNouns(ast.getKey())
            def newDefault  := _specializeNouns(ast.getDefault())
            return builder.NamedParamExtract(newParams, newKey, newDefault,
                                             ast.getSpan())
        else:
            throw(`No handler for $nn`)
    def expr := _specializeNouns(topExpr)
    return expr

def normalize0(ast, outerNames, inRepl) as DeepFrozen:
    def [anfTree, numVariables] := anfTransform(ast, outerNames, nastBuilder)
    return specializeNouns(
        layoutScopes(anfTree, layoutNASTBuilder),
        outerNames, boundNounsBuilder, numVariables, inRepl)

#[x] Ensure non-repl outers are not shadowed
#[x] AssignExpr -> slot.put()
#[x] lay out frames
# - Remove localsSize
#[ ] rewrite nouns
# + LetDef adds [class, region, mode, idx] addressing
# + NounExpr/BindingExpr address bindings by [class, region, mode, idx]
# + NounExpr wrapped in .get.get() if needed


#[ ] expand MetaStateExpr
#elide trivial 'return'
#----------------------
#Expand MetaFQNExpr
#replace CallExpr verbs with atoms
