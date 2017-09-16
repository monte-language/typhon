exports (normalize, normalize0)

"
AExpr
  NullExpr
  CharExpr
  DoubleExpr
  IntExpr
  StrExpr
  BindingExpr Noun
  NounExpr Noun
  MetaContextExpr
  MetaStateExpr
CExpr
  AssignExpr Noun Expr
  CallExpr AExpr Verb AExpr* NamedArg*
  EscapeExpr Patt Expr Patt Expr
  EscapeOnlyExpr Patt Expr
  FinallyExpr Expr Expr
  IfExpr AExpr Expr Expr
  ObjectExpr Patt AExpr* Method* Matcher* # insufficient for via-patt objectexprs
  TryExpr Expr Patt Expr
  # no SeqExpr
Expr
  LetExpr Let* Expr
  AExpr
  CExpr
Let
  FinalLet Noun CExpr
  BindingLet Noun CExpr

NamedArg
  NamedArgExpr AExpr AExpr
Method
  MethodExpr Verb MethodSignature Expr
Matcher
  MatcherExpr Patt Expr
Patt
  BindingPatt Noun
MethodSignature
  Signature Noun* Noun*
NamedPatt
  NamedPattern AExpr Patt AExpr

(non-BindingPatt rewritten away using pattern helpers: _makeFinalSlot, _makeVarSlot, _guardCoerce, _listCoerce)
"

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

def makeLetBinder(n, builder, [defs :Set, outerRenames :Map]):
    def letBindings := [].diverge()
    def renames := outerRenames.diverge()
    var seq := 0
    def gensym(s):
        var gs := `${s}_seq`
        while (!defs.contains(gs)):
            seq += 1
            gs := `${s}_$seq`
        return gs
    return object letBinder:
        to getI(ast0):
            return n.immediate(ast0, letBinder)
        to getC(ast0):
            return n.complex(ast0, letBinder)
        to getP(patt, exit_, expr):
            n.pattern(patt, exit_, expr, letBinder)
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
            letBinder.addBinding(s, bindingExpr, span)
            return builder.NounExpr(s, span)
        to getDefs():
            return [defs | [for b in (letBindings) b[0]].asSet(), renames]
        to getRename(n):
            return renames.fetch(n, fn {n})
        to getBindings():
            return letBindings
        to gensym(n):
            return gensym(n)


object normalize0 as DeepFrozen:
    to run(ast, builder):
        return normalize0.normalize(ast, builder, [[].asSet(), [].asMap()])

    to normalize(ast, builder, defs):
        def binder := makeLetBinder(normalize0, builder, defs)
        def [expr, letBindings] := normalize0.complex(ast, builder, binder)
        return if (letBindings.isEmpty()):
            expr
        else:
            builder.LetExpr([for args in (letBindings)
                             M.call(builder.LetDef, args, [].asMap())],
                            expr, ast.getSpan())

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
                }
        else if (nn == "NounExpr"):
            return builder.NounExpr(binder.getRename(ast.getName()), span)
        else if (nn == "BindingExpr"):
            return builder.BindingExpr(
                binder.getRename(ast.getNoun().getName()), span)
        else if (nn == "MetaContextExpr"):
            return builder.MetaContextExpr()
        else if (nn == "MetaStateExpr"):
            return builder.MetaContextExpr()
        else:
            return binder.addTempBinding(normalize0.complex(ast, builder, binder))

    to complex(ast, builder, binder):
        def span := ast.getSpan()
        def nn := ast.getNodeName()
        if (nn == "AssignExpr"):
            return builder.AssignExpr(ast.getLvalue().getName(),
                                      normalize0.normalize(ast.getRvalue(),
                                                           builder, binder.getDefs()),
                                      span)
        else if (nn == "DefExpr"):
            def expr := binder.getI(ast.getExpr())
            binder.getP(ast.getPattern(), binder.getI(ast.getExit()), expr)
            return expr
        else if (nn == "EscapeExpr"):
            def ei := binder.gensym("_ej")
            def innerBinder := makeLetBinder(normalize0, builder, binder.getDefs())
            innerBinder.getP(ast.getEjectorPattern(), null, ei)
            def b := innerBinder.getC(ast.getBody())
            if (ast.getCatchPattern() == null):
                return builder.EscapeOnlyExpr(ei, b, span)
            else:
                def ci := binder.gensym("_p")
                def catchBinder := makeLetBinder(normalize0, builder, binder.getDefs())
                catchBinder.getP(ast.getCatchPattern(), null, ci)
                def cb := catchBinder.getC(ast.getCatchBody())
                return builder.EscapExpr(ei, b, ci, cb, span)
        else if (nn == "FinallyExpr"):
            return builder.FinallyExpr(
                normalize0.normalize(ast.getBody(), builder, binder.getDefs()),
                normalize0.normalize(ast.getAtLast(), builder, binder.getDefs()),
                span)
        else if (nn == "HideExpr"):
            # XXX figure out a renaming scheme to avoid inner-let
            return normalize0.normalize(ast.getBody(), builder, binder.getDefs())
        else if (nn == "MethodCallExpr"):
            def r := binder.getI(ast.getReceiver())
            def argList := [for arg in (ast.getArgs()) binder.getI(arg)]
            def namedArgList := [for na in (ast.getNamedArgs())
                                 builder.NamedArgExpr(binder.getI(na.getKey()),
                                                      binder.getI(na.getValue()),
                                                      na.getSpan())]
            return builder.CallExpr(r, argList, namedArgList, span)
        else if (nn == "IfExpr"):
            def test := binder.getI(ast.getTest())
            def alt := normalize0.normalize(ast.getThen(), builder, binder.getDefs())
            def consq := switch (ast.getElse()) {
                match ==null {builder.NullExpr()}
                match e {normalize0.normalize(e, builder, binder.getDefs())}}
            return builder.IfExpr(test, alt, consq, span)
        else if (nn == "SeqExpr"):
            def exprs := ast.getExprs()
            for item in (exprs.slice(0, exprs.size - 1)):
                binder.getI(item)
            return binder.getC(exprs.last())
        else if (nn == "TryExpr"):
            def b := normalize0.normalize(ast.getBody(), builder, binder.getDefs())
            def ci := binder.gensym("_p")
            def catchBinder := makeLetBinder(normalize0, builder, binder.getDefs())
            catchBinder.getP(ast.getCatchPattern(), null, ci)
            def cb := catchBinder.getC(ast.getCatchBody())
            return builder.TryExpr(b, ci, cb, span)
        else if (nn == "ObjectExpr"):
            # XXX uh oh
            null
        else:
            throw(`Unrecognized node $ast`)

    to pattern(p, exitNode, specimen, builder, binder):
        def span := p.getSpan()
        def ei := if (exitNode == null) {
            builder.NounExpr("throw", span)
        } else {
            binder.getI(exitNode)
        }
        def si := binder.getI(specimen)
        def pn := p.getNodeName()

        def matchSlot(slotName):
            def g := p.getGuard()
            def gi := if (g == null) {
                builder.NullExpr(span)
            } else {
                binder.addTempBinding(builder.CallExpr(
                    builder.NounExpr("_guardCoerce", span),
                    [si, binder.getI(g), ei],
                    [], span))
            }
            binder.addBinding(
                p.getNoun().getName(),
                builder.CallExpr(builder.NounExpr(slotName, span),
                                     "run",
                                     [si, gi], [], span), span)

        if (pn == "FinalPattern"):
            matchSlot("_makeFinalSlot")
        else if (pn == "VarPattern"):
            matchSlot("_makeVarSlot")
        else if (pn == "BindingPattern"):
            binder.addBinding(p.getNoun().getName(), si, span)
        else if (pn == "IgnorePattern"):
            def g := p.getGuard()
            if (g != null):
                binder.addTempBinding(builder.CallExpr(
                    builder.NounExpr("_guardCoerce", span),
                    "run", [si, binder.getI(g), ei],
                    [], span), span)
        else if (pn == "ListPattern"):
            def ps := p.getPatterns()
            def li := binder.addTempBinding(builder.CallExpr(
                builder.NounExpr("_listCoerce", span),
                "run", [si, builder.IntExpr(ps, span), ei],
                [], span), span)
            for idx => subp in (ps):
                def subi := binder.addTempBinding(
                    builder.CallExpr(li, "get",
                                     [builder.IntExpr(idx)], [],
                                     span), span)
                binder.getP(subp, ei, subi)
        else if (pn == "ViaPattern"):
            def vi := binder.getI(p.getExpr())
            def si2 := binder.addTempBinding(builder.CallExpr(
                vi, "run", [si, ei], [], span))
            binder.getP(p.getPattern())
        return binder.getBindings()
