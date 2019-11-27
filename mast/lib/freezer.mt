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
def Ast :DeepFrozen := a.getAstGuard()

def freezingThrough(ej) as DeepFrozen:
    return def freezer(x):
        return switch (x) {
            match broken ? (Ref.isBroken(broken)) {
                def problem := a.LiteralExpr(Ref.optProblem(broken), null)
                m`Ref.broken($problem)`
            }
            match expr :Ast {
                # Double-encoded ASTs. Like a normal uncall, but specialized
                # for ASTs to get around m`` wrapping.
                def args := [for arg in (expr._uncall()[2]) freezer(arg)]
                a.MethodCallExpr(m`astBuilder`, expr.getNodeName(),
                                 args, [], null)
            }
            match ==null { m`null` }
            match b :Bool { b.pick(m`true`, m`false`) }
            match _ :Any[Char, Double, Int, Str] { a.LiteralExpr(x, null) }
            match l :List {
                # Generate the uncall for lists by hand.
                def newArgs := [for v in (l) freezer(v)]
                a.MethodCallExpr(m`_makeList`, "run", newArgs, [], null)
            }
            match k ? (freezeMap.contains(k)) {
                a.NounExpr(freezeMap[k], null)
            }
            match obj {
                if (obj._uncall() =~ [newMaker, newVerb, newArgs, newNamedArgs]) {
                    def wrappedArgs := [for arg in (newArgs) freezer(arg)]
                    def wrappedNamedArgs := [for k => v in (newNamedArgs)
                                             a.NamedArg(freezer(k),
                                                        freezer(v),
                                                        null)]
                    def wrappedMaker := freezer(newMaker)
                    a.MethodCallExpr(wrappedMaker, newVerb, wrappedArgs,
                                     wrappedNamedArgs, null)
                } else {
                    throw.eject(ej, `Couldn't freeze $obj: Bad uncall ${obj._uncall()}`)
                }
            }
        }

def freezing(x :Any, ej) :DeepFrozen as DeepFrozen:
    "An AST which builds `x` when evaluated, or else fire `ej`."

    return freezingThrough(ej)(x)

def freeze(x :Any) :DeepFrozen as DeepFrozen:
    "
    Return an AST which builds `x` when evaluated.

    Technically, this is always possible, but there is no single algorithm in
    proper Monte which performs it for all `x`. If `x` is `DeepFrozen` or
    `Transparent`, then that information can guide `freeze`.
    "

    return freezing(x, null)
