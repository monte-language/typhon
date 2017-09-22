exports (normalize, normalize0)

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

def makeLetBinder(n, builder, [defs :Set, outerRenames, &seq]) as DeepFrozen:
    def letBindings := [].diverge()
    def renames := outerRenames.diverge()
    def gensym(s):
        var gs := `${s}_$seq`
        seq += 1
        while (defs.contains(gs)):
            gs := `${s}_$seq`
            seq += 1
        return gs
    return object letBinder:
        to getI(ast0):
            return n.immediate(ast0, builder, letBinder)
        to getC(ast0):
            return n.complex(ast0, builder, letBinder)
        to getP(patt, exit_, expr):
            n.pattern(patt, exit_, expr, builder, letBinder)
        to hide(ast0):
            def innerBinder := makeLetBinder(n, builder, letBinder.getDefs())
            def i := n.complex(ast0, builder, innerBinder)
            letBindings.extend(innerBinder.getBindings())
            return i
        to addBinding(var name :Str, bindingExpr, span):
            for [lname, _, lspan] in (letBindings):
                if (lname == name):
                    throw(`Error at $span: "$name" already defined at $lspan`)
            if (defs.contains(name)):
                def newname := gensym(name)
                renames[name] := newname
                name := newname
            letBindings.push([name, bindingExpr, span])
        to addTempBinding(bindingExpr, span):
            def s := gensym("__t")
            letBinder.addBinding(s, builder.TempBinding(bindingExpr, span), span)
            return s
        to getDefs():
            return [defs | [for b in (letBindings) b[0]].asSet(), renames, &seq]
        to getRename(n):
            return renames.fetch(n, fn {n})
        to getBindings():
            return letBindings
        to gensym(n):
            return gensym(n)

        to guardCoerceFor(speci, gi, ei, span):
            return builder.NounExpr(
                letBinder.addTempBinding(builder.CallExpr(
                    builder.NounExpr("_guardCoerce", span),
                    "run",
                    [speci, gi, ei],
                    [], span), span), span)
        to letExprFor(expr, span):
            return if (letBindings.isEmpty()) {
                expr
            } else if (expr.getNodeName() == "NounExpr" &&
                       (letBindings.last()[0] == expr.getName())) {
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

object normalize0 as DeepFrozen:
    to run(ast, builder):
        var gensym_seq :Int := 0
        return normalize0.normalize(ast, builder, [[].asSet(), [].asMap(),
                                                   &gensym_seq])

    to normalize(ast, builder, defs):
        def binder := makeLetBinder(normalize0, builder, defs)
        def expr := normalize0.immediate(ast, builder, binder)
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
            return builder.NounExpr(binder.getRename(ast.getName()), span)
        else if (nn == "BindingExpr"):
            return builder.BindingExpr(
                binder.getRename(ast.getNoun().getName()), span)
        else if (nn == "MetaContextExpr"):
            return builder.MetaContextExpr()
        else if (nn == "MetaStateExpr"):
            return builder.MetaStateExpr()
        else:
            return builder.NounExpr(
                binder.addTempBinding(normalize0.complex(ast, builder, binder), span),
                span)

    to complex(ast, builder, binder):
        def span := ast.getSpan()
        def nn := ast.getNodeName()
        if (nn == "AssignExpr"):
            def bi := binder.addTempBinding(
                builder.CallExpr(
                    builder.BindingExpr(ast.getLvalue().getName(), span),
                    "get", [], [], span), span)
            return builder.CallExpr(
                builder.NounExpr(bi, span),
                "put", [binder.getI(ast.getRvalue())], [], span)
        else if (nn == "DefExpr"):
            def expr := binder.getI(ast.getExpr())
            def ei := if ((def ex := ast.getExit()) != null) {
                binder.getI(ex)
            } else { null }
            binder.getP(ast.getPattern(), ei, expr)
            return expr
        else if (nn == "EscapeExpr"):
            def ei := binder.gensym("_ej")
            def innerBinder := makeLetBinder(normalize0, builder, binder.getDefs())
            innerBinder.getP(ast.getEjectorPattern(), null, builder.NounExpr(ei, span))
            def b := innerBinder.letExprFor(innerBinder.getC(ast.getBody()), span)
            if (ast.getCatchPattern() == null):
                return builder.EscapeOnlyExpr(ei, b, span)
            else:
                def ci := binder.gensym("_p")
                def catchBinder := makeLetBinder(normalize0, builder, binder.getDefs())
                catchBinder.getP(ast.getCatchPattern(), null, builder.NounExpr(ci, span))
                def cb := catchBinder.letExprFor(catchBinder.getC(ast.getCatchBody()),
                                                 span)
                return builder.EscapeExpr(ei, b, ci, cb, span)
        else if (nn == "FinallyExpr"):
            return builder.FinallyExpr(
                normalize0.normalize(ast.getBody(), builder, binder.getDefs()),
                normalize0.normalize(ast.getUnwinder(), builder, binder.getDefs()),
                span)
        else if (nn == "HideExpr"):
            return binder.hide(ast.getBody())
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
            def alt := normalize0.normalize(ast.getThen(), builder, binder.getDefs())
            def consq := switch (ast.getElse()) {
                match ==null {builder.NullExpr(span)}
                match e {normalize0.normalize(e, builder, binder.getDefs())}}
            return builder.IfExpr(test, alt, consq, span)
        else if (nn == "SeqExpr"):
            def exprs := ast.getExprs()
            for item in (exprs.slice(0, exprs.size() - 1)):
                binder.getI(item)
            return binder.getC(exprs.last())
        else if (nn == "CatchExpr"):
            def b := normalize0.normalize(ast.getBody(), builder, binder.getDefs())
            def ci := binder.gensym("_p")
            def catchBinder := makeLetBinder(normalize0, builder, binder.getDefs())
            catchBinder.getP(ast.getPattern(), null, builder.NounExpr(ci, span))
            def cb := catchBinder.letExprFor(
                catchBinder.getC(ast.getCatcher()), span)
            return builder.TryExpr(b, ci, cb, span)
        else if (nn == "ObjectExpr"):
            def ai := if ((def asExpr := ast.getAsExpr()) != null) {
                [binder.getI(asExpr)]
            } else {
                [builder.NullExpr(span)]
            } + [for aud in (ast.getAuditors()) binder.getI(aud)]
            def methods := [].diverge()
            def matchers := [].diverge()
            for meth in (ast.getScript().getMethods()):
                # uh oh, this won't catch redefs of self-binding. hopefully
                # expander does
                def methBinder := makeLetBinder(normalize0, builder, binder.getDefs())
                def parami := [for p in (meth.getParams())
                               methBinder.gensym("_param")]
                def namedParami := methBinder.gensym("_namedParams")
                for i => p in (meth.getParams()):
                    methBinder.getP(p, null, builder.NounExpr(parami[i], span))
                for np in (meth.getNamedParams()):
                    def npi := methBinder.addTempBinding(
                        builder.CallExpr(builder.NounExpr("_namedParamExtract", span),
                                         "run", [methBinder.getI(np.getKey()),
                                                 methBinder.getI(np.getDefault())],
                                         [], span), span)
                    methBinder.getP(np.getValue(), null,
                                    builder.NounExpr(npi, span))
                def g := meth.getResultGuard()
                def gb := if (g == null) {
                    methBinder.getC(meth.getBody())
                } else {
                    methBinder.guardCoerceFor(methBinder.getI(meth.getBody()),
                                              methBinder.getI(g),
                                              builder.NounExpr("throw", span),
                                              span)
                }
                methods.push(
                    builder."Method"(meth.getDocstring(), meth.getVerb(),
                                     parami, namedParami,
                                     methBinder.letExprFor(gb, span), span))
            for matcher in (ast.getScript().getMatchers()):
                def matcherBinder := makeLetBinder(normalize0, builder,
                                                   binder.getDefs())
                def mi := matcherBinder.gensym("_msg")
                matcherBinder.getP(matcher.getPattern(), null,
                                   builder.NounExpr(mi, span))
                matchers.push(builder.Matcher(
                    mi, matcherBinder.letExprFor(
                        matcherBinder.getC(matcher.getBody()), span), span))
            def oi := builder.NounExpr(
                binder.addTempBinding(
                    builder.ObjectExpr(ast.getDocstring(),
                                       ast, ai,
                                       methods.snapshot(),
                                       matchers.snapshot(),
                                       span), span),
                span)
            def selfNames := [].diverge()
            def op := ast.getName()
            if (op.getNodeName() == "FinalPattern"):
                def on := op.getNoun().getName()
                binder.addBinding(on, builder.FinalBinding(oi, ai[0], span), span)
                selfNames.push(on)
            else if (op.getNodeName() == "VarPattern"):
                def on := op.getNoun().getName()
                binder.addBinding(on, builder.VarBinding(oi, ai[0], span), span)
                selfNames.push(on)
            else:
                object binderWrapper extends binder:
                    to addBinding(name, expr, span):
                        selfNames.push(name)
                        return binder.addBinding(name, expr, span)
                normalize0.pattern(op, null, oi,
                                   builder, binderWrapper)
            for name in (selfNames):
                binder.addTempBinding(builder.CallExpr(
                    builder.NounExpr("_selfBind", span),
                    "run",
                    [oi,
                     builder.StrExpr(binder.getRename(name), span),
                     builder.NounExpr(binder.getRename(name), span)],
                    [], span), span)
            return oi
        else if (["LiteralExpr", "NounExpr", "BindingExpr", "MetaStateExpr", "MetaContextExpr"].contains(nn)):
            return normalize0.immediate(ast, builder, binder)
        else:
            throw(`Unrecognized node $ast (type ${try {ast.getNodeName()} catch _ {"unknown"}})`)

    to pattern(p, exitNode, si, builder, binder):
        def span := p.getSpan()
        def ei := if (exitNode == null) {
            builder.NounExpr("throw", span)
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
            def li := builder.NounExpr(
                binder.addTempBinding(builder.CallExpr(
                    builder.NounExpr("_listCoerce", span),
                    "run", [si, builder.IntExpr(ps.size(), span), ei],
                    [], span), span), span)
            for idx => subp in (ps):
                def subi := binder.addTempBinding(
                    builder.CallExpr(li, "get",
                                     [builder.IntExpr(idx, span)], [],
                                     span), span)
                binder.getP(subp, ei, builder.NounExpr(subi, span))
        else if (pn == "ViaPattern"):
            def vi := binder.getI(p.getExpr())
            def si2 := binder.addTempBinding(builder.CallExpr(
                vi, "run", [si, ei], [], span), span)
            binder.getP(p.getPattern(), exitNode, builder.NounExpr(si2, span))
        return binder.getBindings()
