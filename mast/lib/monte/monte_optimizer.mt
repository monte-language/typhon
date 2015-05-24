# Note that the identity "no-op" operation on ASTs is not `return ast` but
# rather `return M.call(maker, "run", args + [span])`; the transformation has
# to rebuild the AST.


def removeUnusedBareNouns(ast, maker, args, span):
    "Remove unused bare nouns from sequences."

    if (ast.getNodeName() == "SeqExpr"):
        traceln(`Sequence args: $args`)
        def exprs := args[0]
        def last := exprs.last()
        def newExprs := [].diverge()
        for expr in exprs.slice(0, exprs.size() - 1):
            if (expr.getNodeName() != "NounExpr"):
                newExprs.push(expr)
        newExprs.push(last)
        traceln(`Reassembled sequence: $newExprs`)
        return maker(newExprs.snapshot(), span)
    else:
        # No-op.
        return M.call(maker, "run", args + [span])


def optimizations := [
    removeUnusedBareNouns,
]


def optimize(var ast):
    traceln(`AST: $ast`)
    for optimization in optimizations:
        ast := ast.transform(optimization)
    return ast


[=> optimize]
