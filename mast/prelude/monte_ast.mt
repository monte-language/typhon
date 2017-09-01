import "boot" =~ [=> DeepFrozenStamp, => TransparentStamp, => KernelAstStamp]
import "lib/iterators" =~ [=> zip :DeepFrozen]
import "ast_printer" =~ [=> astPrint :DeepFrozen]
exports (astBuilder)

def makeStaticScope(read, set, defs, vars, metaStateExpr :Bool) as DeepFrozenStamp:
    def namesRead :Set[DeepFrozen] := read.asSet()
    def namesSet :Set[DeepFrozen] := set.asSet()
    def defNames :Set[DeepFrozen] := defs.asSet()
    def varNames :Set[DeepFrozen] := vars.asSet()
    return object staticScope as DeepFrozenStamp:
        to getNamesRead():
            return namesRead

        to getNamesSet():
            return namesSet

        to getDefNames():
            return defNames

        to getVarNames():
            return varNames

        to getMetaStateExprFlag():
            return metaStateExpr

        to hide():
            return makeStaticScope(namesRead, namesSet, [], [], metaStateExpr)

        to add(right):
            if (right == null):
                return staticScope
            def rightNamesRead := (right.getNamesRead() - defNames) - varNames
            def rightNamesSet := right.getNamesSet() - varNames
            def badAssigns := rightNamesSet & defNames
            if (badAssigns.size() > 0):
                throw(["Can't assign to final nouns", badAssigns])
            return makeStaticScope(namesRead | rightNamesRead,
                                   namesSet | rightNamesSet,
                                   defNames | right.getDefNames(),
                                   varNames | right.getVarNames(),
                                   metaStateExpr | right.getMetaStateExprFlag())
        to namesUsed():
            return namesRead | namesSet

        to outNames():
            return defNames | varNames

        to _printOn(out):
            out.print("<[")
            out.print(" ".join(namesSet.asList()))
            out.print("] := [")
            out.print(" ".join(namesRead.asList()))
            out.print("] =~ [")
            out.print(" ".join(defNames.asList()))
            out.print("] + var [")
            out.print(" ".join(varNames.asList()))
            out.print("] ")
            out.print(metaStateExpr)
            out.print(">")

def emptyScope :DeepFrozen := makeStaticScope([], [], [], [], false)

def astStamp.audit(_audition) :Bool as DeepFrozenStamp:
    return true

def astGuardStamp.audit(_audition) :Bool as DeepFrozenStamp:
    return true

object Ast as DeepFrozenStamp implements astGuardStamp:
    to coerce(specimen, ej):
        if (!_auditedBy(astStamp, specimen) && !_auditedBy(KernelAstStamp, specimen)):
            def conformed := specimen._conformTo(Ast)
            if (!_auditedBy(astStamp, conformed) && !_auditedBy(KernelAstStamp, conformed)):
                throw.eject(ej, M.toString(specimen) + " not an ast node")
            else:
                return conformed
        return specimen

    match [=="get", nodeNames :List[Str], _]:
        def nodeGuard.coerce(specimen, ej) as DeepFrozenStamp implements astGuardStamp:
            def sp := Ast.coerce(specimen, ej)
            if (nodeNames.contains(sp.getNodeName())):
                return sp
            throw.eject(ej, "m`" + M.toString(sp) + "`'s type (" + M.toQuote(sp.getNodeName()) + ") is not one of " + M.toString(nodeNames))

def Pattern.coerce(specimen, ej) as DeepFrozenStamp:
    def sp := Ast.coerce(specimen, ej)
    def n := sp.getNodeName()
    if (n.endsWith("Pattern")):
        return sp
    throw.eject(ej, "m`" + M.toString(sp) + "` is not a pattern")


def Expr.coerce(specimen, ej) as DeepFrozenStamp:
    def sp := Ast.coerce(specimen, ej)
    def n := sp.getNodeName()
    if (n.endsWith("Expr")):
        return sp
    throw.eject(ej, "m`" + M.toString(specimen) + "` is not an an expression")

def NamePattern :DeepFrozen := Ast["FinalPattern", "VarPattern",
                                   "BindPattern", "SlotPattern",
                                   "BindingPattern", "IgnorePattern",
                                   "ValueHolePattern", "PatternHolePattern"]


def baseFieldName(name) as DeepFrozenStamp:
    if (['*', '?'].contains(name[name.size() - 1])):
        return name.slice(0, name.size() - 1)
    return name

def paramGuard(name, g) as DeepFrozenStamp:
    def last := name[name.size() - 1]
    if (last == '?'):
        return NullOk[g]
    if (last == '*'):
        return List[g]
    return g

def transformArg(f, fname, guard, arg) as DeepFrozenStamp:
        if (fname.endsWith("?") && arg == null):
            return null
        else if (fname.endsWith("*")):
            return [for n in (arg)
                    n.transform(f)]
        else if (_auditedBy(astGuardStamp, guard)):
            return arg.transform(f)
        else:
            return arg

def transformArgs(f, fields, args) as DeepFrozenStamp:
    return [for fname => guard in (fields) transformArg(f, fname, guard, args[baseFieldName(fname)])]

def extractFieldName(contents, name):
    if (name.slice(0, 3) != "get"):
        return null
    def subname := name.slice(3)
    if (subname.isEmpty()):
        return null
    else:
        def fname := subname.slice(0, 1).toLowerCase() + subname.slice(1)
        if (contents.contains(fname)):
            return fname

def makeNodeAuthor(constructorName, fields, extraMethodMaker) as DeepFrozenStamp:
    object nodeMaker as DeepFrozenStamp:
        to _printOn(out):
            out.print("make" + constructorName)

        match [=="run", fullArgs, _]:
            if (fullArgs.size() != (fields.size() + 1)):
                throw("make" + M.toString(constructorName) + " expected " + M.toString(fields.size() + 1) + " arguments (got " + M.toString(fullArgs.size()) + ")")
            def args := fullArgs.slice(0, fullArgs.size() - 1)
            def span := fullArgs.last()
            def contents := [
                for [fname, _] => [guard, specimen :(paramGuard(fname, guard))]
                in (zip(fields, args))
                baseFieldName(fname) => specimen]
            def node
            def extraMethods := if (extraMethodMaker != null) { extraMethodMaker(node) }
            bind node implements Selfless, TransparentStamp, astStamp:
                to getSpan():
                    return span
                to withoutSpan():
                    if (span == null):
                        return node
                    return M.call(nodeMaker, "run", args + [null], [].asMap())
                to canonical():
                    def noSpan(nod, mkr, canonicalArgs, span):
                        return M.call(mkr, "run", canonicalArgs + [null], [].asMap())
                    return node.transform(noSpan)

                to getNodeName():
                    return constructorName

                to transform(f):
                    return f(node, nodeMaker, transformArgs(f, fields, contents), span)

                to _uncall():
                    return [nodeMaker, "run", fullArgs, [].asMap()]

                to _printOn(out):
                    astPrint(node, out, 0)
                    # out.print(constructorName)
                    # out.print("(")
                    # if (args.size() > 0):
                    #     if (args.size() > 1):
                    #         for a in (args.slice(0, args.size() - 1)):
                    #             out.quote(a)
                    #             out.print(", ")
                    #     out.quote(args.last())
                    # out.print(")")

                match [name ? ((def fname := extractFieldName(contents, name)) != null), [], _]:
                    if (!contents.contains(fname)):
                        throw("Message refused: " + name + "/0 - not in " + M.toString(contents))
                    contents[fname]

                match msg:
                    if (extraMethods == null):
                        throw("Message refused: " + msg[0] + "/" + M.toString(msg[1].size()))
                    M.callWithMessage(extraMethods, msg)
    return nodeMaker

def makeAstBuilder(description, extraMethodMakers) as DeepFrozenStamp:
    def gs := [for constructors in (description)
               M.call(Ast, "get", constructors.getKeys(), [].asMap())]
    def ms := [].asMap().diverge()
    for constructorGroup in (description):
        for constructorName :Str => fields in (constructorGroup):
            ms[constructorName] := makeNodeAuthor(
                constructorName, fields,
                extraMethodMakers.fetch(constructorName, fn {null}))
    def makers := ms.snapshot()
    object _astBuilder implements DeepFrozenStamp:
        to convertFromKernel(expr):
            def nodeInfo := [].asMap().diverge()
            for constructorGroup in (description):
                for constructorName :Str => fields in (constructorGroup):
                    nodeInfo[constructorName] := fields
            def convert(node):
                def fullContents := node._uncall()[2]
                def contents := fullContents.slice(0, fullContents.size() - 1)
                def convertedContents := [
                    for [_, fieldname] => [arg, guard]
                    in (zip(contents, nodeInfo[node.getNodeName()]))
                    if (fieldname.endsWith("*")) { [for item in (arg) convert(item)]
                    } else if (arg == null) { null
                    } else if (_auditedBy(astGuardStamp, guard)) { convert(arg)
                    } else { arg }]
                return M.call(_astBuilder, node.getNodeName(),
                              convertedContents + [null],
                              [].asMap())
            return convert(expr)

        match [verb ? (makers.contains(verb)), args, namedArgs]:
            M.call(makers[verb], "run", args, namedArgs)

    return gs + [_astBuilder]

def makeScopeWalker() as DeepFrozenStamp:
    def scopesSeen := [].asMap().diverge()
    def getStaticScope
    def sumScopes(nodes):
        var result := emptyScope
        for node in (nodes):
            if (node != null):
                result += getStaticScope(node)
        return result

    def scopeMaybe(optNode):
        if (optNode == null):
            return emptyScope
        return getStaticScope(optNode)
    bind getStaticScope(node):
        if (scopesSeen.contains(node)):
            return scopesSeen[node]
        def bail := __return
        def s(scope):
            bail(scopesSeen[node] := scope)
        def nodeName := node.getNodeName()
        if (nodeName == "NounExpr"):
            s(makeStaticScope([node.getName()], [], [], [], false))
        if (nodeName == "TempNounExpr"):
            s(makeStaticScope([node], [], [], [], false))
        if (["SlotExpr", "BindingExpr"].contains(nodeName)):
            s(getStaticScope(node.getNoun()))
        if (nodeName == "MetaStateExpr"):
            s(makeStaticScope([], [], [], [], true))
        if (nodeName == "SeqExpr"):
            s(sumScopes(node.getExprs()))
        if (nodeName == "Import"):
            s(getStaticScope(node.getPattern()))
        if (nodeName == "Module"):
            def interiorScope := (sumScopes([for im in (node.getImports())
                                             im.getPattern()]) +
                                  getStaticScope(node.getBody()))
            def exportListScope := sumScopes(node.getExports())
            def exportScope := makeStaticScope(
                exportListScope.getNamesRead() - interiorScope.outNames(),
                [], [for e in (node.getExports())
                     ? (interiorScope.outNames().contains(e.getName()))
                     e.getName()], [], false)
            s(interiorScope.hide() + exportScope)
        if (nodeName == "NamedArg"):
            s(getStaticScope(node.getKey()) + getStaticScope(node.getValue()))
        if (nodeName == "NamedArgExport"):
            s(getStaticScope(node.getValue()))
        if (["MethodCallExpr", "FunCallExpr", "SendExpr", "FunSendExpr"].contains(nodeName)):
            s(sumScopes([node.getReceiver()] + node.getArgs() + node.getNamedArgs()))
        if (nodeName == "ControlExpr"):
            s(getStaticScope(node.getTarget()) +
              (sumScopes(node.getArgs() + node.getParams()) +
               getStaticScope(node.getBody())).hide())
        if (nodeName == "GetExpr"):
            s(sumScopes([node.getReceiver()] + node.getIndices()))
        if (["AndExpr", "OrExpr", "BinaryExpr",
             "RangeExpr", "SameExpr", "CompareExpr"].contains(nodeName)):
            s(getStaticScope(node.getLeft()) + getStaticScope(node.getRight()))
        if (["MatchBindExpr", "MismatchExpr"].contains(nodeName)):
            s(getStaticScope(node.getSpecimen()) + getStaticScope(node.getPattern()))
        if (["PrefixExpr", "CurryExpr"].contains(nodeName)):
            s(getStaticScope(node.getReceiver()))
        if (nodeName == "CoerceExpr"):
            s(getStaticScope(node.getSpecimen()) + getStaticScope(node.getGuard()))
        if (nodeName == "ExitExpr"):
            s(scopeMaybe(node.getValue()))
        if (nodeName == "ForwardExpr"):
            s(makeStaticScope(
                [], [], [node.getNoun().getName(), node.getNoun().getName() +
                         "_Resolver"], [], false))
        if (nodeName == "DefExpr"):
            s(if (node.getExit() == null) {
                getStaticScope(node.getPattern()) + getStaticScope(node.getExpr())
            } else {
                sumScopes([node.getPattern(), node.getExit(), node.getExpr()])
            })
        if (["AssignExpr", "AugAssignExpr"].contains(nodeName)):
            def lname := node.getLvalue().getNodeName()
            def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
                makeStaticScope([], [node.getLvalue().getName()], [], [], false)
            } else {
                getStaticScope(node.getLvalue())
            }
            s(lscope + getStaticScope(node.getRvalue()))
        if (nodeName == "VerbAssignExpr"):
            def lname := node.getLvalue().getNodeName()
            def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
                makeStaticScope([], [node.getLvalue().getName()], [], [], false)
            } else {
                getStaticScope(node.getLvalue())
            }
            s(lscope + sumScopes(node.getRvalues()))

        if (["Method", "To", "MethodExpr"].contains(nodeName)):
            s(sumScopes(node.getParams() + node.getNamedParams() +
                        [node.getResultGuard(), node.getBody()]).hide())
        if (["Matcher", "Catcher"].contains(nodeName)):
            s((getStaticScope(node.getPattern()) +
              getStaticScope(node.getBody())).hide())
        if (nodeName == "Script" || nodeName == "ScriptExpr"):
            def baseScope := sumScopes(node.getMethods() + node.getMatchers())
            def extend := node.getExtends()
            if (extend == null):
                s(baseScope)
            else:
                s(getStaticScope(extend) +
                  makeStaticScope([], [], ["super"], [], false) + baseScope)
        if (nodeName == "FunctionScript"):
            def ps := sumScopes(node.getParams() + node.getNamedParams())
            def returnScope := makeStaticScope([], [], ["__return"], [], false)
            def b := sumScopes([node.getResultGuard(), node.getBody()])
            s((ps + returnScope + b).hide())
        if (nodeName == "FunctionExpr"):
            s(sumScopes(node.getParams() + node.getNamedParams() +
                        [node.getBody()]).hide())
        if (nodeName == "ListExpr"):
            s(sumScopes(node.getItems()))
        if (["MapExprAssoc", "NamedArg"].contains(nodeName)):
            s(getStaticScope(node.getKey()) + getStaticScope(node.getValue()))
        if (["MapExprExport", "NamedArgExport"].contains(nodeName)):
            s(getStaticScope(node.getValue()))
        if (nodeName == "MapExpr"):
            s(sumScopes(node.getPairs()))
        if (nodeName == "MapComprehensionExpr"):
              s(sumScopes([node.getIterable(), node.getKey(),
                           node.getValue(), node.getFilter(),
                           node.getBodyKey(), node.getBodyValue()]).hide())
        if (nodeName == "ListComprehensionExpr"):
              s(sumScopes([node.getIterable(), node.getKey(),
                           node.getValue(), node.getFilter(),
                           node.getBody()]).hide())
        if (nodeName == "ForExpr"):
              s(((makeStaticScope([], [], ["__break"], [], false) +
                  sumScopes([node.getIterable(), node.getKey(),
                             node.getValue()]) +
                  makeStaticScope([], [], ["__continue"], [], false) +
                  getStaticScope(node.getBody())).hide() +
                 scopeMaybe(node.getCatchPattern()) +
                 scopeMaybe(node.getCatchBody())).hide())
        if (nodeName == "ObjectExpr"):
              s(getStaticScope(node.getName()) +
                sumScopes([node.getAsExpr()] + node.getAuditors()).hide() +
                getStaticScope(node.getScript()))
        if (nodeName == "ParamDesc"):
              s(scopeMaybe(node.getGuard()))
        if (nodeName == "MessageDesc"):
              s(sumScopes(node.getParams() + [node.getResultGuard()]))
        if (nodeName == "InterfaceExpr"):
                s(sumScopes([node.getName()] + node.getParents() +
                            [node.getStamp()] + node.getAuditors() +
                            node.getMessages()))
        if (nodeName == "FunctionInterfaceExpr"):
                s(sumScopes([node.getName()] + node.getParents() +
                            [node.getStamp()] + node.getAuditors() +
                            [node.getMessageDesc()]))
        if (nodeName == "CatchExpr"):
            s(getStaticScope(node.getBody()).hide() +
              (getStaticScope(node.getPattern()) +
               getStaticScope(node.getCatcher())).hide())
        if (nodeName == "FinallyExpr"):
            s(getStaticScope(node.getBody()).hide() +
              getStaticScope(node.getUnwinder()).hide())
        if (nodeName == "EscapeExpr"):
            if (node.getCatchPattern() == null):
                s((getStaticScope(node.getEjectorPattern()) +
                          getStaticScope(node.getBody())).hide())
            else:
                s((getStaticScope(node.getEjectorPattern()) +
                          getStaticScope(node.getBody())).hide() +
                         (getStaticScope(node.getCatchPattern()) +
                          getStaticScope(node.getCatchBody())).hide())
        if (nodeName == "SwitchExpr"):
            s((getStaticScope(node.getSpecimen()) +
               sumScopes(node.getMatchers())).hide())
        if (nodeName == "WhenExpr"):
            s(sumScopes(node.getArgs() + [node.getBody()]).hide() +
              sumScopes(node.getCatchers()) +
              scopeMaybe(node.getFinally()).hide())
        if (nodeName == "IfExpr"):
            if (node.getElse() == null):
                s((getStaticScope(node.getTest()) +
                  getStaticScope(node.getThen())).hide())
            else:
                s((getStaticScope(node.getTest()) +
                   getStaticScope(node.getThen())).hide() +
                  getStaticScope(node.getElse()).hide())
        if (nodeName == "WhileExpr"):
            s((makeStaticScope([], [], ["__break"], [], false) +
               getStaticScope(node.getTest()) +
               makeStaticScope([], [], ["__continue"], [], false) +
               getStaticScope(node.getBody())).hide() +
              scopeMaybe(node.getCatcher()).hide())
        if (nodeName == "HideExpr"):
            s(getStaticScope(node.getBody()).hide())
        if (["ValueHoleExpr", "ValueHolePattern",
             "PatternHoleExpr", "PatternHolePattern",
             "QuasiText", "LiteralExpr", "MetaContextExpr"].contains(nodeName)):
            s(emptyScope)
        if (nodeName == "FinalPattern"):
            def gs := scopeMaybe(node.getGuard())
            def noun := node.getNoun()
            if (noun.getNodeName() == "NounExpr" &&
                  gs.namesUsed().contains(noun.getName())):
                throw("Kernel guard cycle not allowed")
            s(makeStaticScope([], [], [noun.getName()], [], false) +
              gs)
        if (["VarPattern", "SlotPattern"].contains(nodeName)):
            def gs := scopeMaybe(node.getGuard())
            def noun := node.getNoun()
            if (noun.getNodeName() == "NounExpr" &&
                  gs.namesUsed().contains(noun.getName())):
                throw("Kernel guard cycle not allowed")
            s(makeStaticScope([], [], [], [noun.getName()], false) +
              gs)
        if (nodeName == "BindingPattern"):
            s(makeStaticScope([], [], [], [node.getNoun().getName()], false))
        if (nodeName == "BindPattern"):
            s(makeStaticScope([node.getNoun().getName() + "_Resolver"],
                              [], [], [], false) +
              scopeMaybe(node.getGuard()))
        if (nodeName == "IgnorePattern"):
            s(scopeMaybe(node.getGuard()))
        if (nodeName == "ListPattern"):
            s(sumScopes(node.getPatterns() + [node.getTail()]))
        if (["MapPatternAssoc", "NamedParam"].contains(nodeName)):
            s(getStaticScope(node.getKey()) + getStaticScope(node.getValue()) +
              scopeMaybe(node.getDefault()))
        if (["MapPatternImport", "NamedParamImport"].contains(nodeName)):
            s(getStaticScope(node.getValue()) + scopeMaybe(node.getDefault()))
        if (nodeName == "MapPattern"):
            s(sumScopes(node.getPatterns() + [node.getTail()]))
        if (nodeName == "ViaPattern"):
            s(getStaticScope(node.getExpr()) + getStaticScope(node.getPattern()))
        if (nodeName == "SuchThatPattern"):
            s(getStaticScope(node.getPattern()) + getStaticScope(node.getExpr()))
        if (nodeName == "SamePattern"):
            s(getStaticScope(node.getValue()))
        if (["QuasiParserExpr", "QuasiParserPattern"].contains(nodeName)):
            def base := if(node.getName() == null) {
                emptyScope
            } else {
                makeStaticScope([node.getName() + "``"], [], [], [], false)
            }
            s(base + sumScopes(node.getQuasis()))
        if (nodeName == "QuasiPatternHole"):
            s(getStaticScope(node.getPattern()))
        if (nodeName == "QuasiExprHole"):
            s(getStaticScope(node.getExpr()))
        throw("Unrecognized node name " + M.toQuote(nodeName))

    return object scopeWalker:
        to getEmptyScope():
            return emptyScope
        to getStaticScope(node):
            return getStaticScope(node)
        to nodeUsesName(node, name :Str):
            return getStaticScope(node).namesUsed().contains(name)
        to nodeSetsName(node, name :Str):
            return getStaticScope(node).getNamesSet().contains(name)
        to nodeReadsName(node, name :Str):
            return getStaticScope(node).getNamesRead().contains(name)
        to nodeBindsName(node, name :Str):
            return getStaticScope(node).outNames().contains(name)

def operatorsToNamePrio :Map[Str, List[Str]] := [
    "+" => ["add", "addsub"],
    "-" => ["subtract", "addsub"],
    "*" => ["multiply", "divmul"],
    "//" => ["floorDivide", "divmul"],
    "/" => ["approxDivide", "divmul"],
    "%" => ["mod", "divmul"],
    "**" => ["pow", "pow"],
    "&" => ["and", "comp"],
    "|" => ["or", "comp"],
    "^" => ["xor", "comp"],
    "&!" => ["butNot", "comp"],
    "<<" => ["shiftLeft", "comp"],
    ">>" => ["shiftRight", "comp"]]

def comparatorsToName :Map[Str, Str] := [
    ">" => "greaterThan", "<" => "lessThan",
    ">=" => "geq", "<=" => "leq",
    "<=>" => "asBigAs"]


def unaryOperatorsToName :Map[Str, Str] := [
    "~" => "complement", "!" => "not", "-" => "negate"]

def makeCoreAst() as DeepFrozenStamp:
    def Noun := Ast[
        "ValueHoleExpr", "PatternHoleExpr", "NounExpr", "TempNounExpr",
    ]

    def [Expr, Pattern, NamedArg, MapItem, MapPatternItem,
         NamedParam, Method_, Matcher, Catcher, Script,
         ParamDesc, MessageDesc, QuasiPiece, Import_, _Module,
         astBuilder_] := makeAstBuilder([
    "Expr" => [
        "LiteralExpr"           => ["value" => Any],
        "TempNounExpr"          => [],
        "NounExpr"              => ["name" => Str],
        "SlotExpr"              => ["noun" => Noun],
        "BindingExpr"           => ["noun" => Noun],
        "MetaContextExpr"       => [].asMap(),
        "MetaStateExpr"         => [].asMap(),
        "SeqExpr"               => ["exprs*" => Expr],
        "MethodCallExpr"        => ["receiver" => Expr,
                                    "verb" => Str,
                                    "args*" => Expr,
                                    "namedArgs*" => NamedArg],
        "FunCallExpr"           => ["receiver" => Expr,
                                    "args*" => Expr,
                                    "namedArgs*" => NamedArg],
        "SendExpr"              => ["receiver" => Expr,
                                    "verb" => Str,
                                    "args*" => Expr,
                                    "namedArgs*" => NamedArg],
        "FunSendExpr"           => ["receiver" => Expr,
                                    "args*" => Expr,
                                    "namedArgs*" => NamedArg],
        "GetExpr"               => ["receiver" => Expr,
                                    "indices*" => Expr],
        "AndExpr"               => ["left" => Expr, "right" => Expr],
        "OrExpr"                => ["left" => Expr, "right" => Expr],
        "BinaryExpr"            => ["left" => Expr, "op" => Str,
                                    "right" => Expr],
        "CompareExpr"           => ["left" => Expr, "op" => Str,
                                    "right" => Expr],
        "RangeExpr"             => ["left" => Expr, "op" => Str,
                                    "right" => Expr],
        "SameExpr"              => ["left" => Expr, "right" => Expr,
                                    "direction" => Bool],
        "MatchBindExpr"         => ["specimen" => Expr, "pattern" => Pattern],
        "MismatchExpr"          => ["specimen" => Expr, "pattern" => Pattern],
        "ControlExpr"           => ["target" => Expr, "operator" => Str,
                                    "args*" => Expr,
                                    "params*" => Pattern,
                                    "body" => Expr,
                                    "isTop" => Bool],
        "PrefixExpr"            => ["op" => Str, "receiver" => Expr],
        "CoerceExpr"            => ["specimen" => Expr, "guard?" => Expr],
        "CurryExpr"             => ["receiver" => Expr, "verb" => Str, "isSend" => Bool],
        "ExitExpr"              => ["name" => Str, "value?" => Expr],
        "ForwardExpr"           => ["pattern" => Ast["FinalPattern"]],
        "DefExpr"               => ["pattern" => Pattern, "exit?" => Expr,
                                    "expr" => Expr],
        "AssignExpr"            => ["lvalue" => Expr, "rvalue" => Expr],
        "VerbAssignExpr"        => ["verb" => Str, "lvalue" => Expr,
                                    "rvalues*" => Expr],
        "AugAssignExpr"         => ["op" => Str, "lvalue" => Expr, "rvalue" => Expr],
        "FunctionExpr"          => ["params*" => Pattern,
                                    "namedParams*" => NamedParam,
                                    "body" => Expr],
        "ListExpr"              => ["items*" => Expr],
        "ListComprehensionExpr" => ["iterable" => Expr,
                                    "filter?" => Expr,
                                    "key?" => Pattern,
                                    "value" => Pattern,
                                    "body" => Expr],
        "MapExpr"               => ["pairs*" => MapItem],
        "MapComprehensionExpr"  => ["iterable" => Expr, "filter?" => Expr,
                                    "key?" => Pattern, "value" => Pattern,
                                    "bodyKey" => Expr, "bodyValue" => Expr],
        "ForExpr"               => ["iterable" => Expr, "key?" => Pattern,
                                    "value" => Pattern, "body" => Expr,
                                    "catchPattern?" => Pattern,
                                    "catchBody?" => Expr],
        "ObjectExpr"            => ["docstring?" => Str, "name" => NamePattern,
                                    "asExpr?" => Expr, "auditors*" => Expr,
                                    "script" => Script],
        "InterfaceExpr"         => ["docstring?" => Str, "name" => NamePattern,
                                    "stamp?" => NamePattern, "parents*" => Expr,
                                    "auditors*" => Expr, "messages*" => MessageDesc],
        "FunctionInterfaceExpr" => ["docstring?" => Str, "name" => NamePattern,
                                    "stamp?" => NamePattern, "parents*" => Expr,
                                    "auditors*" => Expr, "messageDesc" => MessageDesc],
        "CatchExpr"             => ["body" => Expr, "pattern" => Pattern, "catcher" => Expr],
        "FinallyExpr"           => ["body" => Expr, "unwinder" => Expr],
        "EscapeExpr"            => ["ejectorPattern" => Pattern, "body" => Expr,
                                    "catchPattern?" => Pattern, "catchBody?" => Expr],
        "SwitchExpr"            => ["specimen" => Expr, "matchers*" => Matcher],
        "WhenExpr"              => ["args*" => Expr, "body" => Expr,
                                    "catchers*" => Catcher, "finally?" => Expr],
        "IfExpr"                => ["test" => Expr, "then" => Expr, "else?" => Expr],
        "WhileExpr"             => ["test" => Expr, "body" => Expr, "catcher?" => Catcher],
        "HideExpr"              => ["body" => Expr],
        "QuasiParserExpr"       => ["name?" => Str, "quasis*" => QuasiPiece],
        "ValueHoleExpr"         => ["index" => Int],
        "PatternHoleExpr"       => ["index" => Int],
    ],
    "Pattern" => [
        "IgnorePattern"      => ["guard?" => Expr],
        "FinalPattern"       => ["noun" => Noun, "guard?" => Expr],
        "SlotPattern"        => ["noun" => Noun, "guard?" => Expr],
        "VarPattern"         => ["noun" => Noun, "guard?" => Expr],
        "BindPattern"        => ["noun" => Noun, "guard?" => Expr],
        "BindingPattern"     => ["noun" => Noun],
        "ListPattern"        => ["patterns*" => Pattern, "tail?" => Pattern],
        "MapPattern"         => ["patterns*" => MapPatternItem, "tail?" => Pattern],
        "ViaPattern"         => ["expr" => Expr, "pattern" => Pattern],
        "SuchThatPattern"    => ["pattern" => Pattern, "expr" => Expr],
        "SamePattern"        => ["value" => Expr, "direction" => Bool],
        "QuasiParserPattern" => ["name?" => Str, "quasis*" => QuasiPiece],
        "ValueHolePattern"   => ["index" => Int],
        "PatternHolePattern" => ["index" => Int],
    ],
    "NamedArg" => [
        "NamedArg"       => ["key" => Expr, "value" => Expr],
        "NamedArgExport" => ["value" => Expr]
    ],
    "MapItem" => [
        "MapExprAssoc"  => ["key" => Expr, "value" => Expr],
        "MapExprExport" => ["value" => Expr],
    ],
    "MapPatternItem" => [
        "MapPatternAssoc"  => ["key" => Expr, "value" => Pattern, "default?" => Expr],
        "MapPatternImport" => ["value" => Pattern, "default?" => Expr],
    ],
    "NamedParam" => [
        "NamedParam"       => ["key" => Expr, "value" => Pattern, "default?" => Expr],
        "NamedParamImport" => ["value" => Pattern, "default?" => Expr],
    ],
    "Method" => [
        "Method" => ["docstring?" => Str, "verb" => Str, "params*" => Pattern,
                     "namedParams*" => NamedParam, "resultGuard?" => Expr,
                     "body" => Expr],
        "To"     => ["docstring?" => Str, "verb" => Str, "params*" => Pattern,
                     "namedParams*" => NamedParam, "resultGuard?" => Expr,
                     "body" => Expr]
    ],
    "Matcher" => [
        "Matcher" => ["pattern" => Pattern, "body" => Expr]
    ],
    "Catcher" => [
        "Catcher" => ["pattern" => Pattern, "body" => Expr]
    ],
    "Script" => [
        "Script"         => ["extends?" => Expr, "methods*" => Method_,
                             "matchers*" => Matcher],
        "FunctionScript" => ["verb" => Str, "params*" => Pattern,
                             "namedParams*" => NamedParam,
                             "resultGuard?" => Expr,
                             "body" => Expr]
    ],
    "ParamDesc" => [
        "ParamDesc" => ["name" => Str, "guard?" => Expr]
    ],
    "MessageDesc" => [
        "MessageDesc" => ["docstring?" => Str, "verb" => Str,
                          "params*" => ParamDesc, "namedParams*" => ParamDesc,
                          "resultGuard?" => Expr]
    ],
    "QuasiPiece" => [
        "QuasiText"        => ["text" => Str],
        "QuasiExprHole"    => ["expr" => Expr],
        "QuasiPatternHole" => ["pattern" => Pattern]
    ],
    "Import" => [
        "Import" => ["name" => Str, "pattern" => Pattern],
    ],
    "Module" => [
        "Module" => ["imports*" => Import_, "exports*" => Noun, "body" => Expr]
    ]
    ],
    [
    "BindingExpr" => fn super {
        def bindingExprExtras.getName() {
            return super.getNoun().getName()
        }
    },
    "SlotExpr" => fn super {
        def slotExprExtras.getName() {
            return super.getNoun().getName()
        }
    },
    "Script" => fn super {
        object scriptExtras {
            to getMethodNamed(verb, ej) {
                "Look up the first method with the given verb, or eject if no such
                method exists."

                for meth in (super.getMethods()) {
                        if (meth.getVerb() == verb) {
                            return meth
                        }
                }
                throw.eject(ej, "No method named " + verb)
            }
            to getCompleteMatcher(ej) {
                "Obtain the pattern and body of the 'complete' matcher, or eject
                 if it is not present.

                 A 'complete' matcher is a matcher which is last in the list of
                 matchers and which has a pattern that cannot fail. Such matchers
                 are common in transparent forwarders and other composed objects."

                if (super.getMatchers().size() > 0) {
                    def last := super.getMatchers().last()
                    def pattern := last.getPattern()
                    if (pattern.refutable()) {
                        throw.eject(ej, "getCompleteMatcher/1: Ultimate matcher pattern is refutable")
                    } else {
                        return [pattern, last.getBody()]
                    }
                }
                throw.eject(ej, "getCompleteMatcher/1: No matchers")
            }
        }},
    "VarPattern" => fn super {
        object varPatternExtras {
            to withGuard(newGuard) {
                return astBuilder_.VarPattern(super.getNoun(), newGuard, super.getSpan())
            }
            to refutable() :Bool {
                return super.getGuard() != null
            }
        }},
    "FinalPattern" => fn super {
        object finalPatternExtras {
            to withGuard(newGuard) {
                return astBuilder_.FinalPattern(super.getNoun(), newGuard, super.getSpan())
            }
            to refutable() :Bool {
                return super.getGuard() != null
            }
        }},
    "SlotPattern" => fn super {
        def slotPatternExtras.refutable() :Bool {
            return super.getGuard() != null
        }
    },
    "BindPattern" => fn super {
        def bindPatternExtras.refutable() :Bool {
            return super.getGuard() != null
        }
    },
    "BindingPattern" => fn _super {
        def bindingPatternExtras.refutable() :Bool {
            return true
        }
    },
    "IgnorePattern" => fn super {
        def ignorePatternExtras.refutable() :Bool {
            return super.getGuard() != null
        }
    },
    "ListPattern" => fn _super {
        def listPatternExtras.refutable() :Bool {
            return true
        }
    },
    "MapPattern" => fn _super {
        def mapPatternExtras.refutable() :Bool {
            return true
        }
    },
    "ViaPattern" => fn _super {
        def viaPatternExtras.refutable() :Bool {
            return true
        }
    },
    "SuchThatPattern" => fn _super {
        def suchThatPatternExtras.refutable() :Bool {
            return true
        }
    },
    "SamePattern" => fn _super {
        def samePatternExtras.refutable() :Bool {
            return true
        }
    },
    "QuasiParserPattern" => fn _super {
        def quasiParserPatternExtras.refutable() :Bool {
            return true
        }
    },
    "ForwardExpr" => fn super {
        def forwardExprExtras.getNoun() {
            return super.getPattern().getNoun()
        }
    },
    "BinaryExpr" => fn super {
        object binaryExprExtras {
            to getOpName() {
                return operatorsToNamePrio[super.getOp()][0]
            }
            to getPriorityName() {
                return operatorsToNamePrio[super.getOp()][1]
            }
        }},
    "CompareExpr" => fn super {
        def compareExprExtras.getOpName() {
            return comparatorsToName[super.getOp()]
        }
    },
    "RangeExpr" => fn super {
        def rangeExprExtras.getOpName() {
            if (super.getOp() == "..") {
                return "thru"
            } else if (super.getOp() == "..!") {
                return "till"
            }
        }
    },
    "PrefixExpr" => fn super {
        def prefixExprExtras.getOpName() {
            return unaryOperatorsToName[super.getOp()]
        }
    },
    "AugAssignExpr" => fn super {
        def augAssignExprExtras.getOpName() {
            return operatorsToNamePrio[super.getOp()][0]
        }
    },
    "EscapeExpr" => fn super {
        def escapeExprExtras.withBody(newBody :Expr) {
            return astBuilder_.EscapeExpr(
                super.getEjectorPattern(), newBody, super.getCatchPattern(),
                super.getCatchBody(), super.getSpan())
        }
    },
    "Method" => fn super {
        def methodExtras.withBody(newBody) {
            return astBuilder_."Method"(super.getDocstring(), super.getVerb(),
                                        super.getParams(),
                                        super.getNamedParams(),
                                        super.getResultGuard(), newBody,
                                        super.getSpan())
        }
    }
    ])
    return object astBuilder implements DeepFrozenStamp:
        to makeScopeWalker():
            return makeScopeWalker()
        to getAstGuard():
            return Ast
        to getPatternGuard():
            return Pattern
        to getExprGuard():
            return Expr
        to getNamePatternGuard():
            return NamePattern
        to getNounGuard():
            return Noun
        to TempNounExpr(namePrefix :Str, span):
            return object tempNounExpr implements DeepFrozenStamp, astStamp:
                to getNodeName():
                    return "TempNounExpr"
                to transform(f):
                    return f(tempNounExpr, astBuilder.TempNounExpr, [namePrefix], span)
                to getName():
                    # this object IS a name, at least for comparison/expansion purposes
                    return tempNounExpr
                to getNamePrefix():
                    return namePrefix
                to _printOn(out):
                    out.print("TempNounExpr(")
                    out.quote(namePrefix)
                    out.print(")")
        to FinalPattern(noun, guard :NullOk[Expr], span):
            if (guard != null && noun.getNodeName() == "NounExpr" &&
                makeScopeWalker().nodeUsesName(guard, noun.getName())):
                throw("Kernel guard cycle not allowed")
            return astBuilder_.FinalPattern(noun, guard, span)
        to VarPattern(noun, guard :NullOk[Expr], span):
            if (guard != null && noun.getNodeName() == "NounExpr" &&
                makeScopeWalker().nodeUsesName(guard, noun.getName())):
                throw("Kernel guard cycle not allowed")
            return astBuilder_.VarPattern(noun, guard, span)
        to SeqExpr(exprs, span):
            # Let's not allocate unnecessarily.
            if (exprs.size() == 1):
                return exprs[0]
            # It's common to accidentally nest SeqExprs, mostly because it's legal and
            # semantically unsurprising (distributive, etc.) So we un-nest them here
            # as a courtesy. ~ C.
            def fixedExprs := {
                def l := [].diverge()
                for ex in (exprs) {
                        if (ex.getNodeName() == "SeqExpr") {
                                l.extend(ex.getExprs())
                        } else { l.push(ex) }
                }
                l.snapshot()
            }
            return astBuilder_.SeqExpr(fixedExprs, span)

        match msg:
            M.callWithMessage(astBuilder_, msg)

def astBuilder :DeepFrozen := makeCoreAst()
