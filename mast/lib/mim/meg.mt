import "lib/mim/syntax/kernel" =~ ["ASTBuilder" => monteBuilder]
import "lib/egg" =~ [=> leaf, => makeEGraph]
exports (intoEGraph, rewrite)

def intoEGraph(egraph) as DeepFrozen:
    "
    Build a transformation which will insert ASTs into an e-graph.
    "

    def maybe(expr):
        return if (expr == null) { egraph.add([leaf, null], null) } else { expr }

    def many(exprs :List, span):
        return egraph.add(["list"] + exprs, span)

    return object eGraphInsertion:
        to LiteralExpr(x, span):
            return egraph.add([leaf, x], span)

        to NounExpr(n, span):
            return egraph.add(["NounExpr", egraph.add([leaf, n], span)], span)

        to DefExpr(patt, ej, expr, span):
            return egraph.add(["DefExpr", patt, maybe(ej), expr], span)

        to AssignExpr(noun, expr, span):
            def n := egraph.add([leaf, noun], span)
            return egraph.add(["AssignExpr", n, expr], span)

        to MethodCallExpr(target, verb :Str, args, namedArgs, span):
            def v := egraph.add([leaf, verb], span)
            def a := many(args, span)
            def na := many(namedArgs, span)
            return egraph.add(["MethodCallExpr", target, v, a, na], span)

        to IfExpr(test, cons, alt, span):
            # NB: We could discriminate between one-armed and two-armed
            # if-expressions here, but this is easier to pattern-match.
            return egraph.add(["IfExpr", test, cons, maybe(alt)], span)

        to EscapeExpr(ejPatt, ejBody, catchPatt, catchBody, span):
            return egraph.add(["EscapeExpr", ejPatt, ejBody, maybe(catchPatt),
                               maybe(catchBody)], span)

        to SeqExpr(exprs :List, span):
            # Right-associate for sanity; [SeqExpr, e1, e2] is like
            # a let-expression in terms of scoping.
            def [last] + init := exprs.reverse()
            var rv := last
            for expr in (init):
                rv := egraph.add(["SeqExpr", expr, rv], span)
            return rv

        to ObjectExpr(docstring, name, asExpr, auditors, script, span):
            return egraph.add(["ObjectExpr", maybe(docstring), name,
                               maybe(asExpr), many(auditors, span), script],
                               span)

        to FinalPattern(noun :Str, guard, span):
            def n := egraph.add([leaf, noun], span)
            def g := maybe(guard)
            return egraph.add(["FinalPattern", n, g], span)

        to VarPattern(noun :Str, guard, span):
            def n := egraph.add([leaf, noun], span)
            def g := maybe(guard)
            return egraph.add(["VarPattern", n, g], span)

        to IgnorePattern(guard, span):
            return egraph.add(["IgnorePattern", maybe(guard)], span)

        to "Method"(docstring, verb :Str, params :List, namedParams :List,
                    resultGuard, body, span):
            def ds := egraph.add([leaf, docstring], span)
            def v := egraph.add([leaf, verb], span)
            def ps := many(params, span)
            def nps := many(namedParams, span)
            return egraph.add(["Method", ds, v, ps, nps, maybe(resultGuard),
                               body], span)

        to "Script"(ext, meths, matchers, span):
            return egraph.add(["Script", maybe(ext), many(meths, span),
                               many(matchers, span)], span)

        match [verb, args, _]:
            # The args are already inserted, so they should be e-classes now.
            # But the final arg is a span.
            def span := args.last()
            egraph.add([verb] + args.slice(0, args.size() - 1), span)

object unknownValue as DeepFrozen {}
object constant as DeepFrozen {}

def isConstant(egraph) as DeepFrozen:
    return def isConstantOn(specimen, ej):
        def [==constant, x] exit ej := egraph.analyze(specimen)
        return x

def allConstant(egraph) as DeepFrozen:
    return def allConstantOn(specimen, ej):
        def rv := [].diverge()
        def l :List exit ej := specimen
        for s in (l):
            def [==constant, x] exit ej := egraph.analyze(s)
            rv.push(x)
        return rv.snapshot()

object monteAnalysis as DeepFrozen:
    to make(n, span, egraph):
        def val := switch (n) {
            match [==leaf, x] { [constant, x] }
            match [=="Atom", a] { egraph.analyze(a) }
            match [=="list"] + via (allConstant(egraph)) elts {
                [constant, elts]
            }
            match [=="MethodCallExpr",
                   via (isConstant(egraph)) target,
                   via (isConstant(egraph)) verb :Str,
                   via (isConstant(egraph)) args :List,
                   via (isConstant(egraph)) _] {
                # XXX nargs
                [constant, M.call(target, verb, args, [].asMap())]
            }
            match _ {
                traceln("um", n)
                unknownValue
            }
        }
        return [val, span]

    to join(d1, d2):
        # Join the spans.
        def [v1, s1] := d1
        def [v2, s2] := d2
        def span := if (s1 == null) { s2 } else if (s2 == null) { s1 } else {
            s1.combine(s2)
        }
        def val := switch ([v1, v2]) {
            match [==unknownValue, d] { d }
            match [d, ==unknownValue] { d }
            match [[==constant, x], d] {
                traceln(`Constraint $x : $d`)
                [constant, x]
            }
            match [d, [==constant, x]] {
                traceln(`Constraint $x : $d`)
                [constant, x]
            }
        }
        return [val, span]

    to modify(class, d):
        def [v, _span] := d
        return if (v =~ [==constant, x]) {
            class.with([leaf, x])
        } else { class }

# Our preference for certain node constructors.
def exprOrder :List[Str] := [
    "NounExpr",
    "MethodCallExpr",
    "IfExpr",
]

def extractTree(egraph) as DeepFrozen:
    return object extract:
        to constant(eclass :Int):
            def [[==constant, rv], _span] := egraph.analyze(eclass)
            return rv

        to listOf(extractor, eclass :Int):
            def [_] + args := egraph.extractFiltered(eclass, fn f { f == "list" })
            return [for arg in (args) extractor(arg)]

        to patt(eclass :Int):
            def [_, span] := egraph.analyze(eclass)
            def [constructor] + args := egraph.extractFiltered(eclass, fn f { f.endsWith("Pattern") })
            return switch (constructor):
                match =="FinalPattern":
                    def n :Str := extract.constant(args[0])
                    def g := extract.expr(args[1])
                    monteBuilder.FinalPattern(n, g, span)

        to expr(eclass :Int):
            def [val, span] := egraph.analyze(eclass)
            # Look for constants first.
            return if (val =~ [==constant, x]) {
                if (x != null) { monteBuilder.LiteralExpr(x, span) }
            } else {
                def [constructor] + args := egraph.extract(eclass, exprOrder)
                switch (constructor) {
                    match =="NounExpr" {
                        def n :Str := extract.constant(args[0])
                        monteBuilder.NounExpr(n, span)
                    }
                    match =="MethodCallExpr" {
                        def target := extract.expr(args[0])
                        def verb :Str := extract.constant(args[1])
                        def newArgs := extract.listOf(extract.expr, args[2])
                        def namedArgs := extract.listOf(extract.expr, args[3])
                        monteBuilder.MethodCallExpr(target, verb, newArgs, namedArgs, span)
                    }
                    match =="DefExpr" {
                        def patt := extract.patt(args[0])
                        def ex := extract.expr(args[1])
                        def rhs := extract.expr(args[2])
                        monteBuilder.DefExpr(patt, ex, rhs, span)
                    }
                    match =="SeqExpr" {
                        def exprs := [].diverge()
                        def go(ec :Int) {
                            def [constructor] + seqArgs := egraph.extract(ec, exprOrder)
                            if (constructor == "SeqExpr") {
                                for seqArg in (seqArgs) { go(seqArg) }
                            } else { exprs.push(extract.expr(ec)) }
                        }
                        for arg in (args) { go(arg) }
                        monteBuilder.SeqExpr(exprs.snapshot(), span)
                    }
                    match _ {
                        def newArgs := [for arg in (args) extract.expr(arg)]
                        M.call(monteBuilder, constructor, newArgs.with(span), [].asMap())
                    }
                }
            }

def rewrite(expr) as DeepFrozen:
    def patts := [
        # Constant-folding for if-expressions and .pick/2.
        ["IfExpr",
            ["NounExpr", [leaf, "true"]],
            1,
            2,
        ] => fn m, _ { m[1] },
        ["IfExpr",
            ["NounExpr", [leaf, "false"]],
            1,
            2,
        ] => fn m, _ { m[2] },
        ["MethodCallExpr",
            ["NounExpr", [leaf, "true"]],
            [leaf, "pick"],
            ["list", 1, 2],
            3,
        ] => fn m, _ { m[1] },
        ["MethodCallExpr",
            ["NounExpr", [leaf, "false"]],
            [leaf, "pick"],
            ["list", 1, 2],
            3,
        ] => fn m, _ { m[2] },
    ]

    def egraph := makeEGraph(monteAnalysis)
    def topclass := expr(intoEGraph(egraph))
    traceln("before rewriting", egraph)
    def pairs := [].diverge()
    for lhs => rhs in (patts):
        def matches := egraph.ematch(lhs)
        for m in (matches):
            traceln("applying match", lhs, rhs, m)
            pairs.push([m[0], rhs(m, egraph)])
    egraph.mergePairs(pairs.snapshot())
    traceln("after rewriting", egraph)
    return extractTree(egraph).expr(topclass)
