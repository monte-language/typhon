exports (main)

def isPure(expr :DeepFrozen) :Bool as DeepFrozen:
    return ["BindingExpr", "LiteralExpr"].contains(expr.getNodeName())

# Borrowed from the expander.
def reifyTemporaries(tree :DeepFrozen) as DeepFrozen:
    def nameList := [].diverge()
    def seen := [].asMap().diverge()
    var i := 0

    # AST nodes uncall to a special maker, so we need to capture the maker
    # for nouns. We'll use this to accelerate the recursion.
    def nounMaker := astBuilder.NounExpr("hack", null)._uncall()[0]

    def nameFinder(node):
        # If it's a noun, then save its name. Otherwise, recurse.
        if (node._uncall() =~ [maker, _, args, _]):
            if (maker == nounMaker):
                nameList.push(args[0])
            else:
                for arg in (args):
                    nameFinder(arg)

    nameFinder(tree)
    def names := nameList.asSet()

    def renameTransformer(node, _maker, args, span):
        def nodeName := node.getNodeName()
        if (nodeName == "TempNounExpr"):
            return seen.fetch(node, fn {
                var noun := null
                while (true) {
                    i += 1
                    def name := `${args[0]}_$i`
                    if (!names.contains(name)) {
                        noun := astBuilder.NounExpr(name, span)
                        break
                    }
                }
                seen[node] := noun
                noun
            })
        else:
            return M.call(astBuilder, nodeName, args + [span], [].asMap())
    return tree.transform(renameTransformer)

def freeze(var expr :DeepFrozen) as DeepFrozen:
    var tempFixup :Bool := false
    var tempCounter :Int := 0

    def freezeTransformer(ast, maker, args, span):
        return switch (ast):
            match mpatt`var @name :(@guard)`:
                def p := astBuilder.BindingPattern(name, null)
                mpatt`via (_makeVarSlot.makeBinding($guard)) $p`
            match mpatt`var @name`:
                def p := astBuilder.BindingPattern(name, null)
                mpatt`via (_makeVarSlot.makeBinding(Any)) $p`
            # AssignExprs can be tough to pull apart. We use case analysis to
            # try to find easy ways of rephrasing what they do without too
            # much work. In general, we want to only use the RHS once.
            match m`@lhs := @rhs`:
                # Sometimes the RHS can be safely used twice.
                if (isPure(rhs)):
                    m`&$lhs.put($rhs); $rhs`
                # Use a TempNounExpr and we'll fix up later.
                else:
                    def temp := astBuilder.TempNounExpr(`assign$tempCounter`, null)
                    def tempPatt := astBuilder.FinalPattern(temp, null, null)
                    tempFixup := true
                    tempCounter += 1
                    m`def $tempPatt := $rhs; &$lhs.put($temp); $temp`
            match _:
                M.call(maker, "run", args + [span], [].asMap())
    expr transform= (freezeTransformer)
    if (tempFixup):
        expr := reifyTemporaries(expr)
    return expr

def main(_argv) as DeepFrozen:
    def expr := m`{
        var x := var y := { traceln("once"); 1 }
        x += 2
        y += 3
        x + y
    }`.expand()
    traceln("original", eval(expr, safeScope))
    def frozen := m`${freeze(expr)}`.expand()
    traceln("frozen", frozen)
    traceln("after", eval(frozen, safeScope))
    return 0
