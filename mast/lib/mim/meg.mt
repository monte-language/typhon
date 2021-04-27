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

# Our e-graph analysis is built from a row of join-semilattices:
# * A source span, if any exist
# * A constant value, if one is known
# * A set of names which might occur free

object spanAnalysis as DeepFrozen:
    to make(_n, span, _egraph):
        return span

    to join(l, r):
        return if (l == null) { r } else if (r == null) { l } else {
            l.combine(r)
        }

    to modify(eclass, _span):
        return eclass


object unknownValue as DeepFrozen {}
object constant as DeepFrozen {}

def isConstant(egraph) as DeepFrozen:
    return def isConstantOn(specimen, ej):
        def [=> constant] | _ := egraph.analyze(specimen)
        if (constant == unknownValue):
            throw.eject(ej, "non-constant")
        return constant

def allConstant(egraph) as DeepFrozen:
    def pred := isConstant(egraph)
    return def allConstantOn(specimen, ej):
        def l :List exit ej := specimen
        return [for s in (l) {
            def via (pred) x exit ej := s
            x
        }]

object constantValueAnalysis as DeepFrozen:
    to make(n, _span, egraph):
        def isConstantOn := isConstant(egraph)
        def allConstantOn := allConstant(egraph)
        return switch (n) {
            match [==leaf, x] { x }
            match [=="list"] + via (allConstantOn) elts { elts }
            match [=="MethodCallExpr",
                   via (isConstantOn) target,
                   via (isConstantOn) verb :Str,
                   via (isConstantOn) args :List,
                   via (isConstantOn) _] {
                # XXX nargs
                M.call(target, verb, args, [].asMap())
            }
            match _ {
                traceln("um", n)
                unknownValue
            }
        }

    to join(l, r):
        return if (l == unknownValue) { r } else if (r == unknownValue) { l } else {
            if (l != r) { throw(`constantValueAnalysis.join/2: $l != $r`) }
            l
        }

    to modify(eclass, constant):
        return if (constant == unknownValue) { eclass } else {
            eclass.with([leaf, constant])
        }


object freeNamesAnalysis as DeepFrozen:
    to make(n, _span, egraph):
        def asNoun(eclass, ej):
            def [==leaf, n :Str] exit ej := egraph.extractFiltered(eclass, fn f {
                f == leaf
            })
            return n
        def names(eclass, _ej) { return egraph.analyze(eclass)["names"] }

        return switch (n) {
            match [==leaf, _] { [].asSet() }
            match [=="list"] + tail {
                var rv := [].asSet()
                for eclass in (tail) { rv |= names(eclass, null) }
                rv
            }
            match [=="NounExpr", via (asNoun) n] { [n].asSet() }
            match [=="MethodCallExpr", via (names) receiver, _verb,
                   via (names) args, via (names) namedArgs] {
                receiver | args | namedArgs
            }
            match [=="EscapeExpr", via (names) ejPatt, via (names) ejBody,
                   _, _] {
                # XXX several things wrong
                ejBody &! ejPatt
            }
            match [=="SeqExpr", via (names) l, via (names) r] {
                # Still wrong
                l | r
            }
            match [=="FinalPattern", via (asNoun) n, _] {
                # XXX also wrong
                [n].asSet()
            }
        }

    to join(l, r):
        return l | r

    to modify(eclass, _names):
        return eclass


object makeRowAnalysis as DeepFrozen:
    "A set of analyses, indexed by name."

    match [=="run", _args, [=> FAIL := null] | na :Map[Str, DeepFrozen]]:
        object rowAnalysis as DeepFrozen:
            to make(n, span, egraph):
                return [for k => analysis in (na) k => analysis.make(n, span, egraph)]

            to join(l, r):
                return [for k => analysis in (na) k => analysis.join(l[k], r[k])]

            to modify(var eclass, data):
                for k => analysis in (na):
                    eclass := analysis.modify(eclass, data[k])
                return eclass


def monteAnalysis :DeepFrozen := makeRowAnalysis(
    "span" => spanAnalysis,
    "constant" => constantValueAnalysis,
    "names" => freeNamesAnalysis,
)

# Our preference for certain node constructors.
def exprOrder :List[Str] := [
    "NounExpr",
    "MethodCallExpr",
    # NB: Old benchmarking shows that ejectors have roughly 4x the overhead of
    # checking Boolean values and branching.
    "IfExpr",
    "EscapeExpr",
]

def extractTree(egraph) as DeepFrozen:
    return object extract:
        to constant(eclass :Int):
            def [=> constant] | _ := egraph.analyze(eclass)
            if (constant == unknownValue) { throw("eclass lacked constant") }
            return constant

        to listOf(extractor, eclass :Int):
            def [_] + args := egraph.extractFiltered(eclass, fn f { f == "list" })
            return [for arg in (args) extractor(arg)]

        to patt(eclass :Int):
            def [=> span] | _ := egraph.analyze(eclass)
            def [constructor] + args := egraph.extractFiltered(eclass, fn f { f.endsWith("Pattern") })
            return switch (constructor):
                match =="FinalPattern":
                    def n :Str := extract.constant(args[0])
                    def g := extract.expr(args[1])
                    monteBuilder.FinalPattern(n, g, span)

        to expr(eclass :Int):
            def [=> constant, => span] | _ := egraph.analyze(eclass)
            # Look for constants first.
            return if (constant != unknownValue) {
                if (constant != null) { monteBuilder.LiteralExpr(constant, span) }
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
                    match =="EscapeExpr" {
                        def ejPatt := extract.patt(args[0])
                        def ejBody := extract.expr(args[1])
                        def catchBody := extract.expr(args[3])
                        def catchPatt := if (catchBody != null) {
                            extract.patt(args[2])
                        }
                        monteBuilder.EscapeExpr(ejPatt, ejBody, catchPatt,
                                                catchBody, span)
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

def always(_, _) :Bool as DeepFrozen { return true }

def isNotFreeIn(nounSlot :Int, exprSlot :Int) as DeepFrozen:
    return def notFreeCheck(m, egraph) :Bool as DeepFrozen:
        def [==leaf, n :Str] := egraph.extractFiltered(m[nounSlot], fn f {
            f == leaf
        })
        def [=> names :Set[Str]] | _ := egraph.analyze(m[exprSlot])
        return !names.contains(n)

def rewrite(expr) as DeepFrozen:
    def patts := [
        # Reassociate SeqExprs from the left to the right.
        ["SeqExpr",
            ["SeqExpr", 1, 2],
            3,
        ] => [always, fn m, egraph {
            egraph.add(["SeqExpr", m[1],
                egraph.add(["SeqExpr", m[2], m[3]], null)], null)
        }],
        # Constant-folding for if-expressions and .pick/2.
        ["IfExpr",
            ["NounExpr", [leaf, "true"]],
            1,
            2,
        ] => [always, fn m, _ { m[1] }],
        ["IfExpr",
            ["NounExpr", [leaf, "false"]],
            1,
            2,
        ] => [always, fn m, _ { m[2] }],
        ["MethodCallExpr",
            ["NounExpr", [leaf, "true"]],
            [leaf, "pick"],
            ["list", 1, 2],
            3,
        ] => [always, fn m, _ { m[1] }],
        ["MethodCallExpr",
            ["NounExpr", [leaf, "false"]],
            [leaf, "pick"],
            ["list", 1, 2],
            3,
        ] => [always, fn m, _ { m[2] }],
        # Truncate escape-expression bodies if the ejector is definitely
        # invoked partway through a sequence of instructions.
        # Occurs in canonical expansion of methods.
        ["EscapeExpr",
            ["FinalPattern", 1, 2],
            ["SeqExpr",
                ["MethodCallExpr",
                    ["NounExpr", 1],
                    [leaf, "run"],
                    ["list", 3],
                    ["list"],
                ],
                4,
            ],
            5, 6,
        ] => [always, fn m, egraph {
            egraph.add(["EscapeExpr",
                egraph.add(["FinalPattern", m[1], m[2]], null),
                m[3], m[5], m[6],
            ], null)
        }],
        # Elide escape-expressions when ejectors are not used.
        ["EscapeExpr", ["FinalPattern", 1, 2], 3, 4, 5] => [
            isNotFreeIn(1, 3),
            fn m, _ { m[3] }
        ]
    ]

    def egraph := makeEGraph(monteAnalysis)
    def topclass := expr(intoEGraph(egraph))
    traceln("before rewriting", egraph)
    def pairs := [].diverge()
    for _ in (0..!2):
        for lhs => [cond, rhs] in (patts):
            def matches := egraph.ematch(lhs)
            for m in (matches):
                if (cond(m, egraph)):
                    traceln("applying match", lhs, rhs, m)
                    pairs.push([m[0], rhs(m, egraph)])
                else:
                    traceln("conditional failed", cond, m)
    egraph.mergePairs(pairs.snapshot())
    traceln("after rewriting", egraph)
    return extractTree(egraph).expr(topclass)
