exports (freeze, freezing)

# A quick and dirty freezer, originally isolated from an early Monte
# optimizer. The logic is oriented towards freezing values that are either
# DeepFrozen or recently diverged from a DeepFrozen maker.

# This is the list of objects which can be thawed and will not break things
# when frozen later on. These objects must satisfy a few rules:
# * Must be uncallable and the transitive uncall must be within the types that
#   are serializable as literals. Currently:
#   * Bool, Char, Int, Str;
#   * List;
#   * broken refs;
#   * Anything in this list of objects; e.g. _booleanFlow is acceptable
# * Must have a transitive closure (under calls) obeying the above rule.
def freezeMap :DeepFrozen := [for `&&@k` => &&v in (safeScope) v => k]

def a :DeepFrozen := astBuilder

def freezingThrough(ej) as DeepFrozen:
    return def freezer(ast, maker, args, span):
        if (ast.getNodeName() == "LiteralExpr"):
            switch (args[0]):
                match broken ? (Ref.isBroken(broken)):
                    # Generate the uncall for broken refs by hand.
                    return a.MethodCallExpr(a.NounExpr("Ref", span), "broken",
                                            [a.LiteralExpr(Ref.optProblem(broken),
                                                           span)], [],
                                            span)
                match ==null:
                    return a.NounExpr("null", span)
                match b :Bool:
                    if (b):
                        return a.NounExpr("true", span)
                    else:
                        return a.NounExpr("false", span)
                match _ :Any[Char, Double, Int, Str]:
                    return ast
                match l :List:
                    # Generate the uncall for lists by hand.
                    def newArgs := [for v in (l)
                                    a.LiteralExpr(v, span).transform(freezer)]
                    return a.MethodCallExpr(a.NounExpr("_makeList", span), "run",
                                            newArgs, [], span)
                match k ? (freezeMap.contains(k)):
                    return a.NounExpr(freezeMap[k], span)
                match obj:
                    if (obj._uncall() =~ [newMaker, newVerb, newArgs, newNamedArgs]):
                        def wrappedArgs := [for arg in (newArgs)
                                            a.LiteralExpr(arg, span)]
                        def wrappedNamedArgs := [for k => v in (newNamedArgs)
                                                 a.NamedArg(a.LiteralExpr(k),
                                                            a.LiteralExpr(v),
                                                            span)]
                        def call := a.MethodCallExpr(a.LiteralExpr(newMaker,
                                                                   span),
                                                     newVerb, wrappedArgs,
                                                     wrappedNamedArgs, span)
                        return call.transform(freezer)
                    else:
                        throw.eject(ej, `Couldn't freeze $obj: Bad uncall ${obj._uncall()}`)

        return M.call(maker, "run", args + [span], [].asMap())

def freezing(x :Any, ej) :DeepFrozen as DeepFrozen:
    "An AST which builds `x` when evaluated, or else fire `ej`."

    return a.LiteralExpr(x, null).transform(freezingThrough(ej))

def freeze(x :Any) :DeepFrozen as DeepFrozen:
    "
    Return an AST which builds `x` when evaluated.

    Technically, this is always possible, but there is no single algorithm in
    proper Monte which performs it for all `x`. If `x` is `DeepFrozen` or
    `Transparent`, then that information can guide `freeze`.
    "

    return freezing(x, null)
