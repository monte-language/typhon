import "lib/egg" =~ [=> leaf, => makeEGraph]
exports (intoEGraph, rewrite)

def intoEGraph(egraph) as DeepFrozen:
    "
    Build a transformation which will insert ASTs into an e-graph.
    "

    def maybe(expr):
        return if (expr == null) { egraph.add([leaf, null]) } else { expr }

    return object eGraphInsertion:
        to LiteralExpr(x, span):
            return egraph.add([leaf, x])

        to NounExpr(n, span):
            return egraph.add(["NounExpr", egraph.add([leaf, n])])

        to MethodCallExpr(target, verb :Str, args, namedArgs, span):
            def v := egraph.add([leaf, verb])
            def a := egraph.add(["list"] + args)
            def na := egraph.add(["list"] + namedArgs)
            return egraph.add(["MethodCallExpr", target, v, a, na])

        to FinalPattern(noun :Str, guard, span):
            def n := egraph.add([leaf, noun])
            def g := maybe(guard)
            return egraph.add(["FinalPattern", n, g])

        match [verb, args, _]:
            # The args are already inserted, so they should be e-classes now.
            # But the final arg is a span.
            def span := args.last()
            egraph.add([verb] + args.slice(0, args.size() - 1))

# Our preference for certain node constructors.
def nodeOrder :List[Str] := [
    "NounExpr",
    "MethodCallExpr",
]

def patts :DeepFrozen := [
    ["MethodCallExpr",
        ["NounExpr", [leaf, "true"]],
        [leaf, "pick"],
        ["list", 1, 2],
        3,
    ] => 1,
    ["MethodCallExpr",
        ["NounExpr", [leaf, "false"]],
        [leaf, "pick"],
        ["list", 1, 2],
        3,
    ] => 2,
]

def applyMatchOnto(egraph, rhs, m) as DeepFrozen:
    return switch (rhs):
        match i :Int:
            return m[i]

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
    to make(n, egraph):
        return switch (n):
            match [==leaf, x]:
                [constant, x]
            match [=="Atom", a]:
                egraph.analyze(a)
            match [=="list"] + via (allConstant(egraph)) elts:
                [constant, elts]
            match [=="MethodCallExpr",
                   via (isConstant(egraph)) target,
                   via (isConstant(egraph)) verb :Str,
                   via (isConstant(egraph)) args :List,
                   via (isConstant(egraph)) _]:
                # XXX nargs
                [constant, M.call(target, verb, args, [].asMap())]
            match _:
                traceln("um", n)
                unknownValue

    to join(d1, d2):
        return switch ([d1, d2]):
            match [==unknownValue, d]:
                d
            match [d, ==unknownValue]:
                d
            match [[==constant, x], d]:
                traceln(`Constraint $x : $d`)
                [constant, x]
            match [d, [==constant, x]]:
                traceln(`Constraint $x : $d`)
                [constant, x]

    to modify(class, d):
        return if (d =~ [==constant, x]) {
            class.with([leaf, x])
        } else { class }

def rewrite(expr) as DeepFrozen:
    def egraph := makeEGraph(monteAnalysis)
    def topclass := expr(intoEGraph(egraph))
    traceln("before rewriting", egraph)
    def pairs := [].diverge()
    for lhs => rhs in (patts):
        def matches := egraph.ematch(lhs)
        for m in (matches):
            traceln("applying match", lhs, rhs, m)
            pairs.push([m[0], applyMatchOnto(egraph, rhs, m)])
    egraph.mergePairs(pairs.snapshot())
    traceln("after rewriting", egraph)
    def analysis := egraph.analyze(topclass)
    traceln("analysis", analysis)
    def topnode := egraph.extract(topclass, nodeOrder)
    return topnode
