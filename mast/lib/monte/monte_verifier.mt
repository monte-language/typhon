imports
exports (findUndefinedNames, walkScopeBoxes)

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
    return results.snapshot()


def walkScopeBoxes(expr, outerScope) as DeepFrozen:
    def flatten(pairs):
        def out := [].diverge()
        for p in pairs:
            for item in pairs:
                out.push(item)
        return out.snapshot()

    def flattenNamedPatts(ps):
        def out := [].diverge()
        for p in ps:
            out.push(p.getKey())
            out.push(p.getPattern())
            out.push(p.getDefault())
        return out.snapshot()

    def findDefinition(name, expr):
        # expr exports the name, so don't descend into subexpressions
        # that hide names.
        def stack := [expr].diverge()
        while (stack.size() > 0):
            def item := stack.pop()
            if (item == null):
                continue
            def nn := item.getNodeName()
            if (nn == "SeqExpr"):
                stack.extend(item.getExprs())
            else if (["MethodCallExpr", "SendExpr", "FunCallExpr", "FunSendExpr"].contains(nn)):
                stack.push(item.getReceiver())
                stack.extend(item.getArgs())
                stack.extend(flatten(item.getNamedArgs()))
            else if (nn == "GetExpr"):
                stack.push(item.getIndices())
            else if (["OrExpr", "AndExpr", "BinaryExpr", "CompareExpr",
                      "RangeExpr", "SameExpr"].contains(nn)):
                stack.push(item.getLeft())
                stack.push(item.getRight())
            else if (["MatchBindExpr", "MismatchExpr"].contains(nn)):
                stack.push(item.getSpecimen())
                stack.push(item.getPattern())
            else if (["PrefixExpr", "CurryExpr"].contains(nn)):
                stack.push(item.getReceiver())
            else if (nn == "CoerceExpr"):
                stack.push(item.getSpecimen())
                stack.push(item.getGuard())
            else if (nn == "ExitExpr"):
                stack.push(item.getValue())
            else if (nn == "DefExpr"):
                stack.push(item.getPattern())
                stack.push(item.getExit())
                stack.push(item.getExpr())
            else if (["AugAssignExpr", "AssignExpr"].contains(nn)):
                stack.push(item.getLvalue())
                stack.push(item.getRvalue())
            else if (nn == "VerbAssignExpr"):
                stack.push(item.getLvalue())
                stack.extend(item.getRvalues())
            else if (nn == "ObjectExpr"):
                stack.push(item.getName())
            else if (nn == "ListExpr"):
                stack.push(item.getItems())
            else if (nn == "MapExpr"):
                def bits := [].diverge()
                for p in item.getPairs():
                    if (p.getNodeName() == "MapExprAssoc"):
                        stack.extend([p.getKey(), p.getValue()])
                stack.push(bits.snapshot())
            else if (nn == "InterfaceExpr"):
                stack.push(item.getName())
                stack.push(item.getStamp())
            else if (nn == "FunctionInterfaceExpr"):
                stack.push(item.getName())
                stack.push(item.getStamp())
            else if (nn == "MapPattern"):
                for p in item.getPatterns():
                    def k := p.getKeyer()
                    if (k.getNodeName() == "MapPatternImport"):
                        stack.push(k.getPattern())
                    else:
                        stack.push(k.getKey())
                        stack.push(k.getValue())
                    stack.push(p.getDefault())
            else if (nn == "ViaPattern"):
                stack.extend([item.getExpr(), item.getPattern()])
            else if (nn == "SuchThatPattern"):
                stack.extend([item.getPattern(), item.getExpr()])
            else if (nn == "SamePattern"):
                stack.push(item.getValue())
            else if (["BindPattern", "IgnorePattern"].contains(nn)):
                if ((def g := item.getGuard()) != null):
                    stack.push(g)
            else if (["SlotPattern", "VarPattern", "BindingPattern", "FinalPattern"].contains(nn)):
                if ((def g := item.getGuard()) != null):
                    stack.push(g)
                if (item.getNoun().getName() == name):
                    return item
    ####
    def ab := m__quasiParser.getAstBuilder()
    def outers := [for `&&@name` in (outerScope.getKeys())
                   ab.NounExpr(name, null)].asSet()
    var results := [].asSet()
    def stack := [[expr]].diverge()
    while (stack.size() > 0):
            def exprs := stack.pop()
            var outNames := outers
            for item in exprs:
                if (item == null):
                    continue
                def s := item.getStaticScope()
                def problems := s.outNames() & outNames
                if (problems.size() > 0):
                    results |= [for p in (problems) findDefinition(p.getName(), item)].asSet()
                outNames |= s.outNames()
                def nn := item.getNodeName()
                if (nn == "SeqExpr"):
                    stack.push(item.getExprs())
                else if (["MethodCallExpr", "SendExpr", "FunCallExpr", "FunSendExpr"].contains(nn)):
                    stack.push([item.getReceiver()])
                    stack.push(item.getArgs() + flatten(item.getNamedArgs()))
                else if (nn == "GetExpr"):
                    stack.push(item.getIndices())
                else if (["AndExpr", "BinaryExpr", "CompareExpr", "RangeExpr", "SameExpr"].contains(nn)):
                    stack.push([item.getLeft(), item.getRight()])
                else if (nn == "OrExpr"):
                    stack.push([item.getLeft()])
                    stack.push([item.getRight()])
                else if (["MatchBindExpr", "MismatchExpr"].contains(nn)):
                    stack.push([item.getSpecimen(), item.getPattern()])
                else if (["PrefixExpr", "CurryExpr"].contains(nn)):
                    stack.push([item.getReceiver()])
                else if (nn == "CoerceExpr"):
                    stack.push([item.getSpecimen(), item.getGuard()])
                else if (nn == "ExitExpr"):
                    stack.push([item.getValue()])
                else if (nn == "DefExpr"):
                    stack.push([item.getPattern(), item.getExit(), item.getExpr()])
                else if (["AugAssignExpr", "AssignExpr"].contains(nn)):
                    stack.push([item.getLvalue()])
                    stack.push([item.getRvalue()])
                else if (nn == "VerbAssignExpr"):
                    stack.push([item.getLvalue()])
                    stack.push(item.getRvalues())
                else if (nn == "ObjectExpr"):
                    stack.push([item.getName(), item.getAsExpr()] + item.getAuditors())
                    def s := item.getScript()
                    if (s.getNodeName() == "Script"):
                        if ((def ex := s.getExtends()) != null):
                            stack.push([ex])
                        for m in s.getMethods():
                            stack.push(m.getPatterns() +
                                       flattenNamedPatts(m.getNamedPatterns()) +
                                       [m.getResultGuard(), m.getBody()])
                        for m in s.getMatchers():
                            stack.push([m.getPattern(), m.getBody()])
                    else:
                        stack.push(s.getPatterns() +
                                   flattenNamedPatts(s.getNamedPatterns()) +
                                   [s.getResultGuard()])
                else if (nn == "Catcher"):
                    stack.push([item.getPattern()])
                    stack.push([item.getBody()])
                else if (nn == "FunctionExpr"):
                    stack.push(item.getPatterns())
                    stack.push(item.getBody())
                else if (nn == "ListExpr"):
                    stack.push(item.getItems())
                else if (nn == "ListComprehensionExpr"):
                    stack.push([item.getIterable(), item.getKey(), item.getValue(),
                                item.getFilter()])
                    stack.push([item.getBody()])
                else if (nn == "MapExpr"):
                    def bits := [].diverge()
                    for p in item.getPairs():
                        if (p.getNodeName() == "MapExprAssoc"):
                            bits.extend([p.getKey(), p.getValue()])
                    stack.push(bits.snapshot())
                else if (nn == "MapComprehensionExpr"):
                    stack.push([item.getIterable(), item.getKey(), item.getValue(),
                                item.getFilter()])
                    stack.push([item.getBodyKey(), item.getBodyValue()])
                else if (nn == "ForExpr"):
                    stack.push([item.getIterable(), item.getKey(), item.getValue()])
                    stack.push([item.getBody()])
                    stack.push([item.getCatchPattern()])
                    stack.push([item.getCatchBody()])
                else if (nn == "InterfaceExpr"):
                    stack.push([item.getName(), item.getStamp(), item.getParents(),
                                item.getAuditors()])
                    for m in item.getMessages():
                        stack.push([for p in (m.getParams()) p.getGuard()] +
                                   [m.getResultGuard()])
                else if (nn == "FunctionInterfaceExpr"):
                    stack.push([item.getName(), item.getStamp(), item.getParents(),
                                item.getAuditors()])
                    stack.push([for p in (item.getMessageDesc().getParams())
                                p.getGuard()] + [item.getResultGuard()])
                else if (nn == "CatchExpr"):
                    stack.push([item.getBody()])
                    stack.push([item.getPattern(), item.getCatcher()])
                else if (nn == "FinallyBlock"):
                    stack.push([item.getBody()])
                    stack.push([item.getUnwinder()])
                else if (nn == "TryExpr"):
                    stack.push([item.getBody()])
                    stack.push(item.getCatchers())
                    stack.push([item.getFinally()])
                else if (nn == "EscapeExpr"):
                    stack.push([item.getEjectorPattern(), item.getBody()])
                    stack.push([item.getCatchPattern(), item.getCatchBody()])
                else if (nn == "SwitchExpr"):
                    stack.push([item.getSpecimen()])
                    for m in item.getMatchers():
                        stack.push([m.getPattern(), m.getBody()])
                else if (nn == "WhenExpr"):
                    stack.push([item.getArgs(), item.getBody()])
                    stack.push([item.getCatchers()])
                    stack.push([item.getFinally()])

                else if (nn == "IfExpr"):
                    # Hmm.
                    stack.push([item.getTest(), item.getThen()])
                    stack.push([item.getTest(), item.getElse()])
                else if (nn == "WhileExpr"):
                    stack.push([item.getTest(), item.getBody()])
                    stack.push([item.getCatcher()])
                else if (nn == "HideExpr"):
                    stack.push([item.getExpr()])
                else if (nn == "MapPattern"):
                    def bits := [].diverge()
                    for p in item.getPatterns():
                        def k := p.getKeyer()
                        if (k.getNodeName() == "MapPatternImport"):
                            bits.push(k.getPattern())
                        else:
                            bits.push(k.getKey())
                            bits.push(k.getValue())
                        bits.push(p.getDefault())
                    stack.push(bits)
                else if (nn == "ViaPattern"):
                    stack.push([item.getExpr(), item.getPattern()])
                else if (nn == "SuchThatPattern"):
                    stack.push([item.getPattern(), item.getExpr()])
                else if (nn == "SamePattern"):
                    stack.push([item.getValue()])
                else if (nn == "Module"):
                    stack.push([item.getBody()])
                else if (["SlotPattern", "IgnorePattern", "VarPattern",
                          "BindPattern", "FinalPattern"].contains(nn)):
                    if ((def g := item.getGuard()) != null):
                        stack.push([g])
    return results.snapshot()
