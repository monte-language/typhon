import "lib/egg" =~ [=> leaf, => makeEGraph]
exports (intoEGraph, rewrite)

def intoEGraph(egraph) as DeepFrozen:
    "
    Build a transformation which will insert ASTs into an e-graph.
    "

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

def rewrite(expr) as DeepFrozen:
    def egraph := makeEGraph()
    def topclass := expr(intoEGraph(egraph))
    traceln("before rewriting", egraph)
    def patt := ["MethodCallExpr",
        ["NounExpr", [leaf, "true"]],
        [leaf, "pick"],
        ["list", 0, 1],
        2,
    ]
    def matches := egraph.ematch(patt)
    for [top, nargs, x, y] in (matches):
        egraph.mergePairs([[top, x]])
    traceln("after rewriting", egraph)
    def topnode := egraph.extract(topclass, nodeOrder)
    return topnode
