imports
exports (findUndefinedNames)

def Ast :DeepFrozen := m__quasiParser.getAstBuilder().getAstGuard()

def findUndefinedNames(expr, outers) as DeepFrozen:
    def outerNames := [for `&&@name` in (outers.getKeys()) name].asSet()
    def ss := expr.getStaticScope()
    def namesUsed := [for n in (ss.namesUsed()) n.getName()].asSet()
    def offenders := namesUsed &! outerNames
    if (offenders.size() == 0):
        # all good, only names closed over are outers
        return []
    def results := [].diverge()
    def stack := [for a in (expr._uncall()[2]) if (a =~ _ :Ast) a].diverge()
    while (stack.size() > 0):
        def item := stack.pop()
        def names := [for n in (item.getStaticScope().namesUsed()) n.getName()].asSet()
        if ((offenders & names).size() > 0):
            if (["NounExpr", "SlotExpr", "BindingExpr"].contains(item.getNodeName())):
                results.push(item)
            stack.extend([for a in (item._uncall()[2]) if (a =~ _ :Ast) a])
    return results

