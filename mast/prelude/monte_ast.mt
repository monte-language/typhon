def MONTE_KEYWORDS :List[Str] := [
"as", "bind", "break", "catch", "continue", "def", "else", "escape",
"exit", "extends", "exports", "finally", "fn", "for", "guards", "if",
"implements", "in", "interface", "match", "meta", "method", "module",
"object", "pass", "pragma", "return", "switch", "to", "try", "var",
"via", "when", "while", "_"]

def idStart :List[Char] := _makeList.fromIterable("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
def idPart :List[Char] := idStart + _makeList.fromIterable("0123456789")
def INDENT :Str := "    "

# note to future drunk self: lower precedence number means add parens when
# inside a higher-precedence-number expression
def priorities :Map[Str, Int] := [
     "indentExpr" => 0,
     "braceExpr" => 1,
     "assign" => 2,
     "logicalOr" => 3,
     "logicalAnd" => 4,
     "comp" => 5,
     "order" => 6,
     "interval" => 7,
     "shift" => 8,
     "addsub" => 9,
     "divmul" => 10,
     "pow" => 11,
     "prefix" => 12,
     "send" => 13,
     "coerce" => 14,
     "call" => 15,
     "prim" => 16,

     "pattern" => 0]

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
            out.print("<")
            out.print(namesSet)
            out.print(" := ")
            out.print(namesRead)
            out.print(" =~ ")
            out.print(defNames)
            out.print(" + var ")
            out.print(varNames)
            out.print(" ")
            out.print(metaStateExpr)
            out.print(">")

def emptyScope :DeepFrozen := makeStaticScope([], [], [], [], false)

def sumScopes(nodes) as DeepFrozenStamp:
    var result := emptyScope
    for node in nodes:
        if (node != null):
            result += node.getStaticScope()
    return result

def scopeMaybe(optNode) as DeepFrozenStamp:
    if (optNode == null):
        return emptyScope
    return optNode.getStaticScope()

def all(iterable, pred) as DeepFrozenStamp:
    for item in iterable:
        if (!pred(item)):
            return false
    return true

def maybeTransform(node, f) as DeepFrozenStamp:
    if (node == null):
        return null
    return node.transform(f)

def transformAll(nodes, f) as DeepFrozenStamp:
    def results := [].diverge()
    for n in nodes:
        results.push(n.transform(f))
    return results.snapshot()

def isIdentifier(name :Str) :Bool as DeepFrozenStamp:
    if (MONTE_KEYWORDS.contains(name.toLowerCase())):
        return false
    return idStart.contains(name[0]) && all(name.slice(1), idPart.contains)

def printListOn(left, nodes, sep, right, out, priority) as DeepFrozenStamp:
    out.print(left)
    if (nodes.size() >= 1):
        for n in nodes.slice(0, nodes.size() - 1):
            n.subPrintOn(out, priority)
            out.print(sep)
        nodes.last().subPrintOn(out, priority)
    out.print(right)

def printDocstringOn(docstring, out, indentLastLine) as DeepFrozenStamp:
    if (docstring == null):
        if (indentLastLine):
            out.println("")
        return
    out.lnPrint("\"")
    def lines := docstring.split("\n")
    for line in lines.slice(0, 0.max(lines.size() - 2)):
        out.println(line)
    if (lines.size() > 0):
        out.print(lines.last())
    if (indentLastLine):
        out.println("\"")
    else:
        out.print("\"")

def printSuiteOn(leaderFn, printContents, cuddle, noLeaderNewline, out,
                 priority) as DeepFrozenStamp:
    def indentOut := out.indent(INDENT)
    if (priorities["braceExpr"] <= priority):
        if (cuddle):
            out.print(" ")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(" {")
        else:
            indentOut.println(" {")
        printContents(indentOut, priorities["braceExpr"])
        out.println("")
        out.print("}")
    else:
        if (cuddle):
            out.println("")
        leaderFn()
        if (noLeaderNewline):
            indentOut.print(":")
        else:
            indentOut.println(":")
        printContents(indentOut, priorities["indentExpr"])

def printExprSuiteOn(leaderFn, suite, cuddle, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, suite.subPrintOn, cuddle, false, out, priority)

def printDocExprSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, true)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

def printObjectSuiteOn(leaderFn, docstring, suite, out, priority) as DeepFrozenStamp:
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, false)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

object astStamp as DeepFrozenStamp:
    to audit(audition):
        return true

object Ast as DeepFrozenStamp:
    to coerce(specimen, ej):
        if (!_auditedBy(astStamp, specimen) && !_auditedBy(KernelAstStamp, specimen)):
            def conformed := specimen._conformTo(Ast)
            if (!_auditedBy(astStamp, conformed) && !_auditedBy(KernelAstStamp, conformed)):
                throw.eject(ej, "not an ast node")
            else:
                return conformed
        return specimen

    match [=="get", nodeNames :List[Str], _]:
        object nodeGuard as DeepFrozenStamp:
            to coerce(specimen, ej):
                def sp := Ast.coerce(specimen, ej)
                if (nodeNames.contains(sp.getNodeName())):
                    return sp
                throw.eject(ej, "m`" + M.toString(sp) + "`'s type is not one of " + M.toString(nodeNames))

object Pattern as DeepFrozenStamp:
    to coerce(specimen, ej):
        def sp := Ast.coerce(specimen, ej)
        def n := sp.getNodeName()
        if (n.endsWith("Pattern")):
            return sp
        throw.eject(ej, "m`" + M.toString(sp) + "` is not a pattern")


object Expr as DeepFrozenStamp:
    to coerce(specimen, ej):
        def sp := Ast.coerce(specimen, ej)
        def n := sp.getNodeName()
        if (n.endsWith("Expr")):
            return sp
        throw.eject(ej, "m`" + M.toString(specimen) + "` is not an an expression")

def NamePattern :DeepFrozen := Ast["FinalPattern", "VarPattern",
                                   "BindPattern", "SlotPattern",
                                   "BindingPattern", "IgnorePattern"]

# LiteralExpr included here because the optimizer uses it.
def Noun :DeepFrozen := Ast["NounExpr", "TempNounExpr", "LiteralExpr"]

# The story of &scope:
# Scopes are not used very often. They are expensive to calculate:
# * Visits every node (O(n))
#   * Calls Set methods: or/1 (O(n)), subtract/1 (O(n))
# So scope calculation is O(n**2). Not cheap.
# We amortize scope calculation by only computing used scopes, using lazy
# slots to defer the calculations. Since those slots have to be preserved to
# keep the laziness effect, we pass around &scope instead of scope. ~ C.
def astWrapper(node, maker, args, span, &scope, nodeName, transformArgs) as DeepFrozenStamp:
    return object astNode extends node implements Selfless, TransparentStamp, astStamp:
        to getStaticScope():
            return scope
        to getSpan():
            return span
        to withoutSpan():
            if (span == null):
                return astNode
            return M.call(maker, "run", args + [null], [].asMap())

        to canonical():
            def noSpan(nod, mkr, canonicalArgs, span):
                return M.call(mkr, "run", canonicalArgs + [null], [].asMap())
            return astNode.transform(noSpan)

        to getNodeName():
            return nodeName
        to transform(f):
            return f(astNode, maker, transformArgs(f), span)
        to _uncall():
            return [maker, "run", args + [span], [].asMap()]
        to _printOn(out):
            node.subPrintOn(out, 0)

# 'value' is unguarded because the optimized uses LiteralExprs for non-literal
# constants.
def makeLiteralExpr(value, span) as DeepFrozenStamp:
    object literalExpr:
        to getValue():
            return value
        to subPrintOn(out, priority):
            out.quote(value)
    return astWrapper(literalExpr, makeLiteralExpr, [value], span,
        &emptyScope, "LiteralExpr", fn f {[value]})

def makeNounExpr(name :Str, span) as DeepFrozenStamp:
    object nounExpr:
        to getName():
            return name
        to subPrintOn(out, priority):
            if (isIdentifier(name)):
                out.print(name)
            else:
                out.print("::")
                out.quote(name)
    def scope
    def node := astWrapper(nounExpr, makeNounExpr, [name], span,
         &scope, "NounExpr", fn f {[name]})
    bind scope := makeStaticScope([node.getName()], [], [], [], false)
    return node

# Doesn't use astWrapper because it is compared by identity, not Transparent.
def makeTempNounExpr(namePrefix :Str, span) as DeepFrozenStamp:
    def scope
    object tempNounExpr implements DeepFrozenStamp, astStamp:
        to getStaticScope():
            return scope
        to getSpan():
            return span
        to getNodeName():
            return "TempNounExpr"
        to withoutSpan():
            # Purpose of withoutSpan is to make nodes comparable, and this one's
            # comparable by identity. Oh well.
            return tempNounExpr
        to transform(f):
            return f(tempNounExpr, makeTempNounExpr, [namePrefix], span)
        to getName():
            # this object IS a name, at least for comparison/expansion purposes
            return tempNounExpr
        to getNamePrefix():
            return namePrefix
        to _printOn(out):
            tempNounExpr.subPrintOn(out, 0)
        to subPrintOn(out, priority):
            out.print("$<temp ")
            out.print(namePrefix)
            out.print(">")
    bind scope := makeStaticScope([tempNounExpr.withoutSpan()], [], [], [], false)
    return tempNounExpr

def makeSlotExpr(noun :Noun, span) as DeepFrozenStamp:
    def scope := noun.getStaticScope()
    object slotExpr:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&")
            out.print(noun)
    return astWrapper(slotExpr, makeSlotExpr, [noun], span,
        &scope, "SlotExpr", fn f {[noun.transform(f)]})

def makeMetaContextExpr(span) as DeepFrozenStamp:
    def scope := emptyScope
    object metaContextExpr:
        to subPrintOn(out, priority):
            out.print("meta.context()")
    return astWrapper(metaContextExpr, makeMetaContextExpr, [], span,
        &scope, "MetaContextExpr", fn f {[]})

def makeMetaStateExpr(span) as DeepFrozenStamp:
    def scope := makeStaticScope([], [], [], [], true)
    object metaStateExpr:
        to subPrintOn(out, priority):
            out.print("meta.getState()")
    return astWrapper(metaStateExpr, makeMetaStateExpr, [], span,
        &scope, "MetaStateExpr", fn f {[]})

def makeBindingExpr(noun :Noun, span) as DeepFrozenStamp:
    def scope := noun.getStaticScope()
    object bindingExpr:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&&")
            out.print(noun)
    return astWrapper(bindingExpr, makeBindingExpr, [noun], span,
        &scope, "BindingExpr", fn f {[noun.transform(f)]})

def makeSeqExpr(exprs :List[Expr], span) as DeepFrozenStamp:
    # Let's not allocate unnecessarily.
    if (exprs.size() == 1):
        return exprs[0]
    # It's common to accidentally nest SeqExprs, mostly because it's legal and
    # semantically unsurprising (distributive, etc.) So we un-nest them here
    # as a courtesy. ~ C.
    def _exprs := [].diverge()
    for ex in exprs:
        if (ex.getNodeName() == "SeqExpr"):
            _exprs.extend(ex.getExprs())
        else:
            _exprs.push(ex)
    def fixedExprs := _exprs.snapshot()
    def &scope := makeLazySlot(fn {sumScopes(fixedExprs)})
    object seqExpr:
        to getExprs():
            return fixedExprs
        to subPrintOn(out, priority):
            if (priority > priorities["braceExpr"]):
                out.print("(")
            var first := true
            if (priorities["braceExpr"] >= priority && fixedExprs == []):
                out.print("pass")
            for e in fixedExprs:
                if (!first):
                    out.println("")
                first := false
                e.subPrintOn(out, priority.min(priorities["braceExpr"]))
            if (priority > priorities["braceExpr"]):
                out.print(")")
    return astWrapper(seqExpr, makeSeqExpr, [fixedExprs], span, &scope,
                      "SeqExpr", fn f {[transformAll(fixedExprs, f)]})

def makeModule(importsList, exportsList, body, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([for [n, p] in (importsList) p] + exportsList)})
    object ::"module":
        to getImports():
            return importsList
        to getExports():
            return exportsList
        to getBody():
            return body
        to subPrintOn(out, priority):
            for [petname, patt] in importsList:
                out.print("import ")
                out.quote(petname)
                out.print(" =~ ")
                out.println(patt)
            if (exportsList.size() > 0):
                out.print("exports ")
                printListOn("(", exportsList, ", ", ")", out, priorities["braceExpr"])
                out.println("")
            body.subPrintOn(out, priorities["indentExpr"])
    return astWrapper(::"module", makeModule, [importsList, exportsList, body], span,
                      &scope, "Module", fn f {[
                          [for [n, v] in (importsList) [n, v.transform(f)]],
                          transformAll(exportsList, f),
                          body.transform(f)]})


def makeNamedArg(k :Expr, v :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {k.getStaticScope() + v.getStaticScope()})
    object namedArg:
        to getKey():
            return k
        to getValue():
            return v
        to subPrintOn(out, priority):
            k.subPrintOn(out, priorities["prim"])
            out.print(" => ")
            v.subPrintOn(out, priorities["braceExpr"])
    return astWrapper(namedArg, makeNamedArg, [k, v], span, &scope, "NamedArg",
                      fn f {[k.transform(f), v.transform(f)]})

def makeNamedArgExport(v :Expr, span) as DeepFrozenStamp:
    def scope := v.getStaticScope()
    object namedArgExport:
        to getValue():
            return v
        to subPrintOn(out, priority):
            out.print(" => ")
            v.subPrintOn(out, "braceExpr")
    return astWrapper(namedArgExport, makeNamedArgExport, [v], span, &scope, "NamedArgExport",
                      fn f {[v.transform(f)]})

def makeMethodCallExpr(rcvr :Expr, verb :Str, arglist :List[Expr],
                       namedArgs :List[Ast["NamedArg", "NamedArgExport"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([rcvr] + arglist + namedArgs)})

    object methodCallExpr:
        to getReceiver():
            return rcvr
        to getVerb():
            return verb
        to getArgs():
            return arglist
        to getNamedArgs():
            return namedArgs
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            rcvr.subPrintOn(out, priorities["call"])
            out.print(".")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            printListOn("(", arglist + namedArgs, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(methodCallExpr, makeMethodCallExpr,
        [rcvr, verb, arglist, namedArgs], span, &scope, "MethodCallExpr",
        fn f {[rcvr.transform(f), verb, transformAll(arglist, f),
               transformAll(namedArgs, f)]})

def makeFunCallExpr(receiver :Expr, args :List[Expr],
                    namedArgs :List[Ast["NamedArg", "NamedArgExport"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([receiver] + args + namedArgs)})
    object funCallExpr:
        to getReceiver():
            return receiver
        to getArgs():
            return args
        to getNamedArgs():
            return namedArgs
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            receiver.subPrintOn(out, priorities["call"])
            printListOn("(", args + namedArgs, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(funCallExpr, makeFunCallExpr, [receiver, args, namedArgs], span,
        &scope, "FunCallExpr", fn f {[receiver.transform(f), transformAll(args, f),
                                      transformAll(namedArgs, f)]})

def makeSendExpr(rcvr :Ast, verb :Str, arglist :List[Ast],
                 namedArgs :List[Ast["NamedArg", "NamedArgExport"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([rcvr] + arglist + namedArgs)})
    object sendExpr:
        to getReceiver():
            return rcvr
        to getVerb():
            return verb
        to getArgs():
            return arglist
        to getNamedArgs():
            return namedArgs
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            rcvr.subPrintOn(out, priorities["call"])
            out.print(" <- ")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            printListOn("(", arglist + namedArgs, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(sendExpr, makeSendExpr,
        [rcvr, verb, arglist, namedArgs], span, &scope, "SendExpr",
        fn f {[rcvr.transform(f), verb, transformAll(arglist, f),
               transformAll(namedArgs, f)]})

def makeFunSendExpr(receiver :Expr, args :List[Expr],
                    namedArgs :List[Ast["NamedArg", "NamedArgExport"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([receiver] + args + namedArgs)})
    object funSendExpr:
        to getReceiver():
            return receiver
        to getArgs():
            return args
        to getNamedArgs():
            return namedArgs
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            receiver.subPrintOn(out, priorities["call"])
            printListOn(" <- (", args + namedArgs, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(funSendExpr, makeFunSendExpr, [receiver, args, namedArgs], span,
        &scope, "FunSendExpr", fn f {[receiver.transform(f), transformAll(args, f), transformAll(namedArgs, f)]})

def makeGetExpr(receiver :Expr, indices :List[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(indices + [receiver])})
    object getExpr:
        to getReceiver():
            return receiver
        to getIndices():
            return indices
        to subPrintOn(out, priority):
            receiver.subPrintOn(out, priorities["call"])
            printListOn("[", indices, ", ", "]", out, priorities["braceExpr"])

    return astWrapper(getExpr, makeGetExpr, [receiver, indices], span,
        &scope, "GetExpr", fn f {[receiver.transform(f), transformAll(indices, f)]})

def makeAndExpr(left :Expr, right :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object andExpr:
        to getLeft():
            return left
        to getRight():
            return right
        to subPrintOn(out, priority):
            if (priorities["logicalAnd"] < priority):
                out.print("(")
            left.subPrintOn(out, priorities["logicalAnd"])
            out.print(" && ")
            right.subPrintOn(out, priorities["logicalAnd"])
            if (priorities["logicalAnd"] < priority):
                out.print(")")
    return astWrapper(andExpr, makeAndExpr, [left, right], span,
        &scope, "AndExpr", fn f {[left.transform(f), right.transform(f)]})

def makeOrExpr(left :Expr, right :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object orExpr:
        to getLeft():
            return left
        to getRight():
            return right
        to subPrintOn(out, priority):
            if (priorities["logicalOr"] < priority):
                out.print("(")
            left.subPrintOn(out, priorities["logicalOr"])
            out.print(" || ")
            right.subPrintOn(out, priorities["logicalOr"])
            if (priorities["logicalOr"] < priority):
                out.print(")")
    return astWrapper(orExpr, makeOrExpr, [left, right], span,
        &scope, "OrExpr", fn f {[left.transform(f), right.transform(f)]})

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

def makeBinaryExpr(left :Expr, op :Str, right :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object binaryExpr:
        to getLeft():
            return left
        to getOp():
            return op
        to getOpName():
            return operatorsToNamePrio[op][0]
        to getRight():
            return right
        to subPrintOn(out, priority):
            def opPrio := priorities[operatorsToNamePrio[op][1]]
            if (opPrio < priority):
                out.print("(")
            left.subPrintOn(out, opPrio)
            out.print(" ")
            out.print(op)
            out.print(" ")
            right.subPrintOn(out, opPrio)
            if (opPrio < priority):
                out.print(")")
    return astWrapper(binaryExpr, makeBinaryExpr, [left, op, right], span,
        &scope, "BinaryExpr", fn f {[left.transform(f), op, right.transform(f)]})

def comparatorsToName :Map[Str, Str] := [
    ">" => "greaterThan", "<" => "lessThan",
    ">=" => "geq", "<=" => "leq",
    "<=>" => "asBigAs"]

def makeCompareExpr(left :Expr, op :Str, right :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object compareExpr:
        to getLeft():
            return left
        to getOp():
            return op
        to getOpName():
            return comparatorsToName[op]
        to getRight():
            return right
        to subPrintOn(out, priority):
            if (priorities["comp"] < priority):
                out.print("(")
            left.subPrintOn(out, priorities["comp"])
            out.print(" ")
            out.print(op)
            out.print(" ")
            right.subPrintOn(out, priorities["comp"])
            if (priorities["comp"] < priority):
                out.print(")")
    return astWrapper(compareExpr, makeCompareExpr, [left, op, right], span,
        &scope, "CompareExpr", fn f {[left.transform(f), op, right.transform(f)]})

def makeRangeExpr(left :Expr, op :Str, right :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object rangeExpr:
        to getLeft():
            return left
        to getOp():
            return op
        to getOpName():
            if (op == ".."):
                return "thru"
            else if (op == "..!"):
                return "till"
        to getRight():
            return right
        to subPrintOn(out, priority):
            if (priorities["interval"] < priority):
                out.print("(")
            left.subPrintOn(out, priorities["interval"])
            out.print(op)
            right.subPrintOn(out, priorities["interval"])
            if (priorities["interval"] < priority):
                out.print(")")
    return astWrapper(rangeExpr, makeRangeExpr, [left, op, right], span,
        &scope, "RangeExpr", fn f {[left.transform(f), op, right.transform(f)]})

def makeSameExpr(left :Expr, right :Expr, direction :Bool, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {left.getStaticScope() +
                                   right.getStaticScope()})
    object sameExpr:
        to getLeft():
            return left
        to getDirection():
            return direction
        to getRight():
            return right
        to subPrintOn(out, priority):
            if (priorities["comp"] < priority):
                out.print("(")
            left.subPrintOn(out, priorities["comp"])
            if (direction):
                out.print(" == ")
            else:
                out.print(" != ")
            right.subPrintOn(out, priorities["comp"])
            if (priorities["comp"] < priority):
                out.print(")")
    return astWrapper(sameExpr, makeSameExpr, [left, right, direction], span,
        &scope, "SameExpr", fn f {[left.transform(f), right.transform(f), direction]})

def makeMatchBindExpr(specimen :Expr, pattern :Pattern, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {specimen.getStaticScope() +
                                   pattern.getStaticScope()})
    object matchBindExpr:
        to getSpecimen():
            return specimen
        to getPattern():
            return pattern
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            specimen.subPrintOn(out, priorities["call"])
            out.print(" =~ ")
            pattern.subPrintOn(out, priorities["pattern"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(matchBindExpr, makeMatchBindExpr, [specimen, pattern], span,
        &scope, "MatchBindExpr", fn f {[specimen.transform(f), pattern.transform(f)]})

def makeMismatchExpr(specimen :Expr, pattern :Pattern, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {specimen.getStaticScope() +
                                   pattern.getStaticScope()})
    object mismatchExpr:
        to getSpecimen():
            return specimen
        to getPattern():
            return pattern
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            specimen.subPrintOn(out, priorities["call"])
            out.print(" !~ ")
            pattern.subPrintOn(out, priorities["pattern"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(mismatchExpr, makeMismatchExpr, [specimen, pattern], span,
        &scope, "MismatchExpr", fn f {[specimen.transform(f), pattern.transform(f)]})

def unaryOperatorsToName :Map[Str, Str] := [
    "~" => "complement", "!" => "not", "-" => "negate"]

def makePrefixExpr(op :Str, receiver :Expr, span) as DeepFrozenStamp:
    def scope := receiver.getStaticScope()
    object prefixExpr:
        to getOp():
            return op
        to getOpName():
            return unaryOperatorsToName[op]
        to getReceiver():
            return receiver
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            out.print(op)
            receiver.subPrintOn(out, priorities["call"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(prefixExpr, makePrefixExpr, [op, receiver], span,
        &scope, "PrefixExpr", fn f {[op, receiver.transform(f)]})

def makeCoerceExpr(specimen :Expr, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {specimen.getStaticScope() +
                                   guard.getStaticScope()})
    object coerceExpr:
        to getSpecimen():
            return specimen
        to getGuard():
            return guard
        to subPrintOn(out, priority):
            if (priorities["coerce"] < priority):
                out.print("(")
            specimen.subPrintOn(out, priorities["coerce"])
            out.print(" :")
            guard.subPrintOn(out, priorities["prim"])
            if (priorities["coerce"] < priority):
                out.print(")")
    return astWrapper(coerceExpr, makeCoerceExpr, [specimen, guard], span,
        &scope, "CoerceExpr", fn f {[specimen.transform(f), guard.transform(f)]})

def makeCurryExpr(receiver :Expr, verb :Str, isSend :Bool, span) as DeepFrozenStamp:
    def scope := receiver.getStaticScope()
    object curryExpr:
        to getReceiver():
            return receiver
        to getVerb():
            return verb
        to getIsSend():
            return isSend
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            receiver.subPrintOn(out, priorities["call"])
            if (isSend):
                out.print(" <- ")
            else:
                out.print(".")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(curryExpr, makeCurryExpr, [receiver, verb, isSend], span,
        &scope, "CurryExpr", fn f {[receiver.transform(f), verb, isSend]})

def makeExitExpr(name :Str, value :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {scopeMaybe(value)})
    object exitExpr:
        to getName():
            return name
        to getValue():
            return value
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            out.print(name)
            if (value != null):
                out.print(" ")
                value.subPrintOn(out, priority)
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(exitExpr, makeExitExpr, [name, value], span,
        &scope, "ExitExpr", fn f {[name, maybeTransform(value, f)]})

def makeForwardExpr(patt :Ast["FinalPattern"], span) as DeepFrozenStamp:
    def scope := patt.getStaticScope()
    object forwardExpr:
        to getNoun():
            return patt.getNoun()
        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            out.print("def ")
            patt.subPrintOn(out, priorities["prim"])
            if (priorities["assign"] < priority):
                out.print(")")
    return astWrapper(forwardExpr, makeForwardExpr, [patt], span,
        &scope, "ForwardExpr", fn f {[patt.transform(f)]})

def makeVarPattern(noun :Noun, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {makeStaticScope([], [], [],
                                                   [noun.getName()],
                                                   false) +
                                   scopeMaybe(guard)})
    object varPattern:
        to getNoun():
            return noun
        to getGuard():
            return guard

        to withGuard(newGuard):
            return makeVarPattern(noun, newGuard, span)

        to refutable() :Bool:
            return guard != null

        to subPrintOn(out, priority):
            out.print("var ")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(varPattern, makeVarPattern, [noun, guard], span,
        &scope, "VarPattern",
        fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeBindPattern(noun :Noun, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {makeStaticScope([], [],
                                                   [noun.getName()], [],
                                                   false) +
                                   scopeMaybe(guard)})
    object bindPattern:
        to getNoun():
            return noun

        to refutable() :Bool:
            return guard != null

        to subPrintOn(out, priority):
            out.print("bind ")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(bindPattern, makeBindPattern, [noun, guard], span,
        &scope, "BindPattern", fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeDefExpr(pattern :Pattern, exit_ :NullOk[Expr], expr :Expr, span) as DeepFrozenStamp:
    def &scope := if (exit_ == null) {
        makeLazySlot(fn {pattern.getStaticScope() + expr.getStaticScope()})
    } else {
        makeLazySlot(fn {pattern.getStaticScope() + exit_.getStaticScope() +
                         expr.getStaticScope()})
    }
    object defExpr:
        to getPattern():
            return pattern
        to getExit():
            return exit_
        to getExpr():
            return expr

        to withExpr(newExpr :Expr):
            return makeDefExpr(pattern, exit_, newExpr, span)

        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            if (!["VarPattern", "BindPattern"].contains(pattern.getNodeName())):
                out.print("def ")
            pattern.subPrintOn(out, priorities["pattern"])
            if (exit_ != null):
                out.print(" exit ")
                exit_.subPrintOn(out, priorities["call"])
            out.print(" := ")
            expr.subPrintOn(out, priorities["assign"])
            if (priorities["assign"] < priority):
                out.print(")")
    return astWrapper(defExpr, makeDefExpr, [pattern, exit_, expr], span,
        &scope, "DefExpr", fn f {[pattern.transform(f), if (exit_ == null) {null} else {exit_.transform(f)}, expr.transform(f)]})

def makeAssignExpr(lvalue :Expr, rvalue :Expr, span) as DeepFrozenStamp:
    def lname := lvalue.getNodeName()
    def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def &scope := makeLazySlot(fn {lscope + rvalue.getStaticScope()})
    object assignExpr:
        to getLvalue():
            return lvalue
        to getRvalue():
            return rvalue
        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            lvalue.subPrintOn(out, priorities["call"])
            out.print(" := ")
            rvalue.subPrintOn(out, priorities["assign"])
            if (priorities["assign"] < priority):
                out.print(")")
    return astWrapper(assignExpr, makeAssignExpr, [lvalue, rvalue], span,
        &scope, "AssignExpr", fn f {[lvalue.transform(f), rvalue.transform(f)]})

def makeVerbAssignExpr(verb :Str, lvalue :Expr, rvalues :List[Expr], span) as DeepFrozenStamp:
    def lname := lvalue.getNodeName()
    def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def &scope := makeLazySlot(fn {lscope + sumScopes(rvalues)})
    object verbAssignExpr:
        to getLvalue():
            return lvalue
        to getRvalues():
            return rvalues
        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            lvalue.subPrintOn(out, priorities["call"])
            out.print(" ")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            out.print("= ")
            printListOn("(", rvalues, ", ", ")", out, priorities["assign"])
            if (priorities["assign"] < priority):
                out.print(")")
    return astWrapper(verbAssignExpr, makeVerbAssignExpr, [verb, lvalue, rvalues], span,
        &scope, "VerbAssignExpr", fn f {[verb, lvalue.transform(f), transformAll(rvalues, f)]})


def makeAugAssignExpr(op :Str, lvalue :Expr, rvalue :Expr, span) as DeepFrozenStamp:
    def lname := lvalue.getNodeName()
    def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def &scope := makeLazySlot(fn {lscope + rvalue.getStaticScope()})
    object augAssignExpr:
        to getOp():
            return op
        to getOpName():
            return operatorsToNamePrio[op][0]
        to getLvalue():
            return lvalue
        to getRvalue():
            return rvalue
        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            lvalue.subPrintOn(out, priorities["call"])
            out.print(" ")
            out.print(op)
            out.print("= ")
            rvalue.subPrintOn(out, priorities["assign"])
            if (priorities["assign"] < priority):
                out.print(")")
    return astWrapper(augAssignExpr, makeAugAssignExpr, [op, lvalue, rvalue], span,
        &scope, "AugAssignExpr", fn f {[op, lvalue.transform(f), rvalue.transform(f)]})

def makeMethod(docstring :NullOk[Str], verb :Str, patterns :List[Pattern],
               namedPatts :List[Ast["NamedParam", "NamedParamImport"]], resultGuard :NullOk[Expr],
               body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(patterns + namedPatts +
                                             [resultGuard, body]).hide()})
    object ::"method":
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getPatterns():
            return patterns
        to getNamedPatterns():
            return namedPatts
        to getResultGuard():
            return resultGuard
        to getBody():
            return body

        to withBody(newBody):
            return makeMethod(docstring, verb, patterns, namedPatts,
                              resultGuard, newBody, span)

        to subPrintOn(out, priority):
            printDocExprSuiteOn(fn {
                out.lnPrint("method ")
                if (isIdentifier(verb)) {
                    out.print(verb)
                } else {
                    out.quote(verb)
                }
                printListOn("(", patterns, ", ", "", out, priorities["pattern"])
                if (patterns.size() > 0 && namedPatts.size() > 0) {
                    out.print(", ")
                }
                printListOn("", namedPatts, ", ", ")", out, priorities["pattern"])
                if (resultGuard != null) {
                    out.print(" :")
                    resultGuard.subPrintOn(out, priorities["call"])
                }
            }, docstring, body, out, priority)
    return astWrapper(::"method", makeMethod, [docstring, verb, patterns, namedPatts, resultGuard, body], span,
        &scope, "Method", fn f {[docstring, verb, transformAll(patterns, f), transformAll(namedPatts, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeTo(docstring :NullOk[Str], verb :Str, patterns :List[Pattern],
           namedPatts :List[Ast["NamedParam", "NamedParamImport"]], resultGuard :NullOk[Expr],
           body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(patterns + namedPatts +
                                             [resultGuard, body]).hide()})
    object ::"to":
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getPatterns():
            return patterns
        to getNamedPatterns():
            return namedPatts
        to getResultGuard():
            return resultGuard
        to getBody():
            return body
        to subPrintOn(out, priority):

            printDocExprSuiteOn(fn {
                out.lnPrint("to ")
                if (isIdentifier(verb)) {
                    out.print(verb)
                } else {
                    out.quote(verb)
                }
                printListOn("(", patterns, ", ", "", out, priorities["pattern"])
                if (patterns.size() > 0 && namedPatts.size() > 0) {
                    out.print(", ")
                }
                printListOn("", namedPatts, ", ", ")", out, priorities["pattern"])
                if (resultGuard != null) {
                    out.print(" :")
                    resultGuard.subPrintOn(out, priorities["call"])
                }
            }, docstring, body, out, priority)
    return astWrapper(::"to", makeTo, [docstring, verb, patterns, namedPatts, resultGuard, body], span,
        &scope, "To", fn f {[docstring, verb, transformAll(patterns, f), transformAll(namedPatts, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeMatcher(pattern :Pattern, body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {(pattern.getStaticScope() +
                                    body.getStaticScope()).hide()})
    object matcher:
        to getPattern():
            return pattern
        to getBody():
            return body
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.lnPrint("match ");
                pattern.subPrintOn(out, priorities["pattern"]);
            }, body, false, out, priority)
    return astWrapper(matcher, makeMatcher, [pattern, body], span,
        &scope, "Matcher", fn f {[pattern.transform(f), body.transform(f)]})

def makeCatcher(pattern :Pattern, body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {(pattern.getStaticScope() +
                                    body.getStaticScope()).hide()})
    object catcher:
        to getPattern():
            return pattern
        to getBody():
            return body
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.print("catch ");
                pattern.subPrintOn(out, priorities["pattern"]);
            }, body, true, out, priority)
    return astWrapper(catcher, makeCatcher, [pattern, body], span,
        &scope, "Catcher", fn f {[pattern.transform(f), body.transform(f)]})

def makeScript(extend :NullOk[Expr], methods :List[Ast["Method", "To"]],
               matchers :List[Ast["Matcher"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(methods + matchers)})
    object script:
        to getExtends():
            return extend
        to getMethods():
            return methods
        to getMatchers():
            return matchers

        to getMethodNamed(verb, ej):
            "Look up the first method with the given verb, or eject if no such
             method exists."

            for meth in methods:
                if (meth.getVerb() == verb):
                    return meth
            throw.eject(ej, "No method named " + verb)

        to getCompleteMatcher(ej):
            "Obtain the pattern and body of the 'complete' matcher, or eject
             if it is not present.

             A 'complete' matcher is a matcher which is last in the list of
             matchers and which has a pattern that cannot fail. Such matchers
             are common in transparent forwarders and other composed objects."

            if (matchers.size() > 0):
                def last := matchers.last()
                def pattern := last.getPattern()
                if (pattern.refutable()):
                    throw.eject(ej, "getCompleteMatcher/1: Ultimate matcher pattern is refutable")
                else:
                    return [pattern, last.getBody()]
            throw.eject(ej, "getCompleteMatcher/1: No matchers")

        to printObjectHeadOn(name, asExpr, auditors, out, priority):
            out.print("object ")
            name.subPrintOn(out, priorities["pattern"])
            if (asExpr != null):
                out.print(" as ")
                asExpr.subPrintOn(out, priorities["call"])
            if (auditors.size() > 0):
                printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
            if (extend != null):
                out.print(" extends ")
                extend.subPrintOn(out, priorities["order"])
        to subPrintOn(out, priority):
            for m in methods + matchers:
                m.subPrintOn(out, priority)
                out.print("\n")
    return astWrapper(script, makeScript, [extend, methods, matchers], span,
        &scope, "Script", fn f {[maybeTransform(extend, f), transformAll(methods, f), transformAll(matchers, f)]})

def makeFunctionScript(patterns :List[Pattern],
                       namedPatterns :List[Ast["NamedParam", "NamedParamImport"]],
                       resultGuard :NullOk[Expr], body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(patterns + namedPatterns +
                                             [resultGuard, body]).hide()})
    object functionScript:
        to getPatterns():
            return patterns
        to getNamedPatterns():
            return namedPatterns
        to getResultGuard():
            return resultGuard
        to getBody():
            return body
        to printObjectHeadOn(name, asExpr, auditors, out, priority):
            out.print("def ")
            name.subPrintOn(out, priorities["pattern"])
            printListOn("(", patterns, ", ", "", out, priorities["pattern"])
            printListOn("", namedPatterns, ", ", ")", out, priorities["pattern"])
            if (resultGuard != null):
                out.print(" :")
                resultGuard.subPrintOn(out, priorities["call"])
            if (asExpr != null):
                out.print(" as ")
                asExpr.subPrintOn(out, priorities["call"])
            if (auditors.size() > 0):
                printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
        to subPrintOn(out, priority):
            body.subPrintOn(out, priority)
            out.print("\n")
    return astWrapper(functionScript, makeFunctionScript, [patterns, namedPatterns, resultGuard, body], span,
        &scope, "FunctionScript", fn f {[transformAll(patterns, f), transformAll(namedPatterns, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeFunctionExpr(patterns :List[Pattern], body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {(sumScopes(patterns) +
                                    body.getStaticScope()).hide()})
    object functionExpr:
        to getPatterns():
            return patterns
        to getBody():
            return body
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                printListOn("fn ", patterns, ", ", "", out, priorities["pattern"])
            }, body, false, out, priorities["assign"])
    return astWrapper(functionExpr, makeFunctionExpr, [patterns, body], span,
        &scope, "FunctionExpr", fn f {[transformAll(patterns, f), body.transform(f)]})

def makeListExpr(items :List[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(items)})
    object listExpr:
        to getItems():
            return items
        to subPrintOn(out, priority):
            printListOn("[", items, ", ", "]", out, priorities["braceExpr"])
    return astWrapper(listExpr, makeListExpr, [items], span,
        &scope, "ListExpr", fn f {[transformAll(items, f)]})

def makeListComprehensionExpr(iterable :Expr, filter :NullOk[Expr],
                              key :NullOk[Pattern], value :Pattern,
                              body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([iterable, key, value, filter,
                                              body]).hide()})
    object listComprehensionExpr:
        to getKey():
            return key
        to getValue():
            return value
        to getIterable():
            return iterable
        to getFilter():
            return filter
        to getBody():
            return body
        to subPrintOn(out, priority):
            out.print("[for ")
            if (key != null):
                key.subPrintOn(out, priorities["pattern"])
                out.print(" => ")
            value.subPrintOn(out, priorities["pattern"])
            out.print(" in (")
            iterable.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
            if (filter != null):
                out.print("if (")
                filter.subPrintOn(out, priorities["braceExpr"])
                out.print(") ")
            body.subPrintOn(out, priorities["braceExpr"])
            out.print("]")
    return astWrapper(listComprehensionExpr, makeListComprehensionExpr, [iterable, filter, key, value, body], span,
        &scope, "ListComprehensionExpr", fn f {[iterable.transform(f), maybeTransform(filter, f), maybeTransform(key, f), value.transform(f), body.transform(f)]})

def makeMapExprAssoc(key :Expr, value :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {key.getStaticScope() +
                                   value.getStaticScope()})
    object mapExprAssoc:
        to getKey():
            return key
        to getValue():
            return value
        to subPrintOn(out, priority):
            key.subPrintOn(out, priorities["braceExpr"])
            out.print(" => ")
            value.subPrintOn(out, priorities["braceExpr"])
    return astWrapper(mapExprAssoc, makeMapExprAssoc, [key, value], span,
        &scope, "MapExprAssoc", fn f {[key.transform(f), value.transform(f)]})

def makeMapExprExport(value :Ast["NounExpr", "BindingExpr", "SlotExpr", "TempNounExpr"], span) as DeepFrozenStamp:
    def scope := value.getStaticScope()
    object mapExprExport:
        to getValue():
            return value
        to subPrintOn(out, priority):
            out.print("=> ")
            value.subPrintOn(out, priorities["prim"])
    return astWrapper(mapExprExport, makeMapExprExport, [value], span,
        &scope, "MapExprExport", fn f {[value.transform(f)]})

def makeMapExpr(pairs :List[Ast["MapExprAssoc", "MapExprExport"]] ? (pairs.size() > 0), span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(pairs)})
    object mapExpr:
        to getPairs():
            return pairs
        to subPrintOn(out, priority):
            printListOn("[", pairs, ", ", "]", out, priorities["braceExpr"])
    return astWrapper(mapExpr, makeMapExpr, [pairs], span,
        &scope, "MapExpr", fn f {[transformAll(pairs, f)]})

def makeMapComprehensionExpr(iterable :Expr, filter :NullOk[Expr],
                             key :NullOk[Pattern], value :Pattern,
                             bodyk :Expr, bodyv :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([iterable, key, value, filter,
                                              bodyk, bodyv]).hide()})
    object mapComprehensionExpr:
        to getIterable():
            return iterable
        to getFilter():
            return filter
        to getKey():
            return key
        to getValue():
            return value
        to getBodyKey():
            return bodyk
        to getBodyValue():
            return bodyv
        to subPrintOn(out, priority):
            out.print("[for ")
            if (key != null):
                key.subPrintOn(out, priorities["pattern"])
                out.print(" => ")
            value.subPrintOn(out, priorities["pattern"])
            out.print(" in (")
            iterable.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
            if (filter != null):
                out.print("if (")
                filter.subPrintOn(out, priorities["braceExpr"])
                out.print(") ")
            bodyk.subPrintOn(out, priorities["braceExpr"])
            out.print(" => ")
            bodyv.subPrintOn(out, priorities["braceExpr"])
            out.print("]")
    return astWrapper(mapComprehensionExpr, makeMapComprehensionExpr, [iterable, filter, key, value, bodyk, bodyv], span,
        &scope, "MapComprehensionExpr", fn f {[iterable.transform(f), maybeTransform(filter, f), maybeTransform(key, f), value.transform(f), bodyk.transform(f), bodyv.transform(f)]})

def makeForExpr(iterable :Expr, key :NullOk[Pattern], value :Pattern,
                body :Expr, catchPattern :NullOk[Pattern],
                catchBody :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([iterable, key, value,
                                              body]).hide()})
    object forExpr:
        to getKey():
            return key
        to getValue():
            return value
        to getIterable():
            return iterable
        to getBody():
            return body
        to getCatchPattern():
            return catchPattern
        to getCatchBody():
            return catchBody
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.print("for ")
                if (key != null) {
                    key.subPrintOn(out, priorities["pattern"])
                    out.print(" => ")
                }
                value.subPrintOn(out, priorities["pattern"])
                out.print(" in ")
                iterable.subPrintOn(out, priorities["braceExpr"])
            }, body, false, out, priority)
            if (catchPattern != null):
                printExprSuiteOn(fn {
                    out.print("catch ")
                    catchPattern.subPrintOn(out, priorities["pattern"])
                }, catchBody, true, out, priority)
    return astWrapper(forExpr, makeForExpr, [iterable, key, value, body, catchPattern, catchBody],
        span,
        &scope, "ForExpr", fn f {[iterable.transform(f), maybeTransform(key, f), value.transform(f), body.transform(f), maybeTransform(catchPattern, f), maybeTransform(catchBody, f)]})

def makeObjectExpr(docstring :NullOk[Str], name :NamePattern,
                   asExpr :NullOk[Expr], auditors :List[Expr],
                   script :Ast["Script", "FunctionScript"], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {name.getStaticScope() +
                                   sumScopes([asExpr] + auditors).hide() +
                                   script.getStaticScope()})
    object ObjectExpr:
        to getDocstring():
            return docstring
        to getName():
            return name
        to getAsExpr():
            return asExpr
        to getAuditors():
            return auditors
        to getScript():
            return script

        to withScript(newScript):
            return makeObjectExpr(docstring, name, asExpr, auditors,
                                  newScript, span)

        to subPrintOn(out, priority):
            def printIt := if (script.getNodeName() == "FunctionScript") {
                printDocExprSuiteOn
            } else {
                printObjectSuiteOn
            }
            printIt(fn {
                script.printObjectHeadOn(name, asExpr, auditors, out, priority)
            }, docstring, script, out, priority)
    return astWrapper(ObjectExpr, makeObjectExpr, [docstring, name, asExpr, auditors, script], span,
        &scope, "ObjectExpr", fn f {[docstring, name.transform(f), maybeTransform(asExpr, f), transformAll(auditors, f), script.transform(f)]})

def makeParamDesc(name :Str, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {scopeMaybe(guard)})
    object paramDesc:
        to getName():
            return name
        to getGuard():
            return guard
        to subPrintOn(out, priority):
            if (name == null):
                out.print("_")
            else:
                out.print(name)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["call"])
    return astWrapper(paramDesc, makeParamDesc, [name, guard], span,
        &scope, "ParamDesc", fn f {[name, maybeTransform(guard, f)]})

def makeMessageDesc(docstring :NullOk[Str], verb :Str,
                    params :List[Ast["ParamDesc"]], resultGuard :NullOk[Expr],
                    span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(params + [resultGuard])})
    object messageDesc:
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getParams():
            return params
        to getResultGuard():
            return resultGuard
        to subPrintOn(head, out, priority):
            #XXX hacckkkkkk
            if (head == "to"):
                out.println("")
            out.print(head)
            out.print(" ")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            printListOn("(", params, ", ", ")", out, priorities["pattern"])
            if (resultGuard != null):
                out.print(" :")
                resultGuard.subPrintOn(out, priorities["call"])
            if (docstring != null):
                def bracey := priorities["braceExpr"] <= priority
                def indentOut := out.indent(INDENT)
                if (bracey):
                    indentOut.print(" {")
                else:
                    indentOut.print(":")
                printDocstringOn(docstring, indentOut, bracey)
                if (bracey):
                    out.print("}")

    return astWrapper(messageDesc, makeMessageDesc, [docstring, verb, params, resultGuard], span,
        &scope, "MessageDesc", fn f {[docstring, verb, transformAll(params, f), maybeTransform(resultGuard, f)]})


def makeInterfaceExpr(docstring :NullOk[Str], name :NamePattern,
                      stamp :NullOk[NamePattern], parents :List[Expr],
                      auditors :List[Expr],
                      messages :List[Ast["MessageDesc"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {name.getStaticScope() +
                                   sumScopes(parents + [stamp] + auditors +
                                             messages)})
    object interfaceExpr:
        to getDocstring():
            return docstring
        to getName():
            return name
        to getStamp():
            return stamp
        to getParents():
            return parents
        to getAuditors():
            return auditors
        to getMessages():
            return messages
        to subPrintOn(out, priority):
            out.print("interface ")
            out.print(name)
            if (stamp != null):
                out.print(" guards ")
                stamp.subPrintOn(out, priorities["pattern"])
            if (parents.size() > 0):
                printListOn(" extends ", parents, ", ", "", out, priorities["call"])
            if (auditors.size() > 0):
                printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
            def indentOut := out.indent(INDENT)
            if (priorities["braceExpr"] <= priority):
                indentOut.print(" {")
            else:
                indentOut.print(":")
            printDocstringOn(docstring, indentOut, false)
            for m in messages:
                m.subPrintOn("to", indentOut, priority)
                indentOut.print("\n")
            if (priorities["braceExpr"] <= priority):
                out.print("}")
    return astWrapper(interfaceExpr, makeInterfaceExpr, [docstring, name, stamp, parents, auditors, messages], span,
        &scope, "InterfaceExpr", fn f {[docstring, name.transform(f), maybeTransform(stamp, f), transformAll(parents, f), transformAll(auditors, f), transformAll(messages, f)]})

def makeFunctionInterfaceExpr(docstring :NullOk[Str], name :NamePattern,
                              stamp :NullOk[NamePattern], parents :List[Expr],
                              auditors :List[Expr],
                              messageDesc :Ast["MessageDesc"], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {name.getStaticScope() +
                                   sumScopes(parents + [stamp] + auditors +
                                             [messageDesc])})
    object functionInterfaceExpr:
        to getDocstring():
            return docstring
        to getName():
            return name
        to getMessageDesc():
            return messageDesc
        to getStamp():
            return stamp
        to getParents():
            return parents
        to getAuditors():
            return auditors
        to subPrintOn(out, priority):
            out.print("interface ")
            out.print(name)
            var cuddle := true
            if (stamp != null):
                out.print(" guards ")
                stamp.subPrintOn(out, priorities["pattern"])
                cuddle := false
            if (parents.size() > 0):
                printListOn(" extends ", parents, ", ", "", out, priorities["call"])
                cuddle := false
            if (auditors.size() > 0):
                printListOn(" implements ", auditors, ", ", "", out, priorities["call"])
                cuddle := false
            if (!cuddle):
                out.print(" ")
            printListOn("(", messageDesc.getParams(), ", ", ")", out, priorities["pattern"])
            if (messageDesc.getResultGuard() != null):
                out.print(" :")
                messageDesc.getResultGuard().subPrintOn(out, priorities["call"])
            if (docstring != null):
                def bracey := priorities["braceExpr"] <= priority
                def indentOut := out.indent(INDENT)
                if (bracey):
                    indentOut.print(" {")
                else:
                    indentOut.print(":")
                printDocstringOn(docstring, indentOut, bracey)
                if (bracey):
                    out.print("}")
            out.print("\n")
    return astWrapper(functionInterfaceExpr, makeFunctionInterfaceExpr, [docstring, name, stamp, parents, auditors, messageDesc], span,
        &scope, "FunctionInterfaceExpr", fn f {[docstring, name.transform(f), maybeTransform(stamp, f), transformAll(parents, f), transformAll(auditors, f), messageDesc.transform(f)]})

def makeCatchExpr(body :Expr, pattern :Pattern, catcher :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {body.getStaticScope().hide() +
                                   (pattern.getStaticScope() +
                                    catcher.getStaticScope()).hide()})
    object catchExpr:
        to getBody():
            return body
        to getPattern():
            return pattern
        to getCatcher():
            return catcher
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {out.print("try")}, body, false, out, priority)
            printExprSuiteOn(fn {
                out.print("catch ")
                pattern.subPrintOn(out, priorities["pattern"])
            }, catcher, true, out, priority)
    return astWrapper(catchExpr, makeCatchExpr, [body, pattern, catcher], span,
        &scope, "CatchExpr", fn f {[body.transform(f), pattern.transform(f),
                                       catcher.transform(f)]})

def makeFinallyExpr(body :Expr, unwinder :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {body.getStaticScope().hide() +
                                   unwinder.getStaticScope().hide()})
    object finallyExpr:
        to getBody():
            return body
        to getUnwinder():
            return unwinder
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {out.print("try")}, body, false, out, priority)
            printExprSuiteOn(fn {out.print("finally")}, unwinder, true, out,
                         priority)
    return astWrapper(finallyExpr, makeFinallyExpr, [body, unwinder], span,
        &scope, "FinallyExpr", fn f {[body.transform(f), unwinder.transform(f)]})

def makeTryExpr(body :Expr, catchers :List[Ast["Catcher"]],
                finallyBlock :NullOk[Expr], span) as DeepFrozenStamp:
    # Definition of baseScope is duplicated in order to avoid chaining lazy
    # slots. ~ C.
    def &scope := if (finallyBlock == null) {
        makeLazySlot(fn {(body.getStaticScope() +
                          sumScopes(catchers)).hide()})
    } else {
        makeLazySlot(fn {(body.getStaticScope() +
                          sumScopes(catchers)).hide() +
                          finallyBlock.getStaticScope().hide()})
    }
    object tryExpr:
        to getBody():
            return body
        to getCatchers():
            return catchers
        to getFinally():
            return finallyBlock
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {out.print("try")}, body, false, out, priority)
            for m in catchers:
                m.subPrintOn(out, priority)
            if (finallyBlock != null):
                printExprSuiteOn(fn {out.print("finally")},
                    finallyBlock, true, out, priority)
    return astWrapper(tryExpr, makeTryExpr, [body, catchers, finallyBlock], span,
        &scope, "TryExpr", fn f {[body.transform(f), transformAll(catchers, f),maybeTransform(finallyBlock, f)]})

def makeEscapeExpr(ejectorPattern :Pattern, body :Expr,
                   catchPattern :NullOk[Pattern], catchBody :NullOk[Expr],
                   span) as DeepFrozenStamp:
    # Definition of baseScope is duplicated in order to avoid chaining lazy
    # slots. ~ C.
    def &scope := if (catchPattern == null) {
        makeLazySlot(fn {(ejectorPattern.getStaticScope() +
                          body.getStaticScope()).hide()})
    } else {
        makeLazySlot(fn {(ejectorPattern.getStaticScope() +
                          body.getStaticScope()).hide() +
                         (catchPattern.getStaticScope() +
                          catchBody.getStaticScope()).hide()})
    }
    object escapeExpr:
        to getEjectorPattern():
            return ejectorPattern
        to getBody():
            return body
        to getCatchPattern():
            return catchPattern
        to getCatchBody():
            return catchBody

        to withBody(newBody :Expr):
            return makeEscapeExpr(ejectorPattern, newBody, catchPattern,
                                  catchBody, span)

        to withCatchBody(newBody :NullOk[Expr]):
            return makeEscapeExpr(ejectorPattern, body, catchPattern,
                                  newBody, span)

        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.print("escape ")
                ejectorPattern.subPrintOn(out, priorities["pattern"])
            }, body, false, out, priority)
            if (catchPattern != null):
                printExprSuiteOn(fn {
                    out.print("catch ")
                    catchPattern.subPrintOn(out, priorities["pattern"])
                }, catchBody, true, out, priority)
    return astWrapper(escapeExpr, makeEscapeExpr,
         [ejectorPattern, body, catchPattern, catchBody], span,
        &scope, "EscapeExpr",
         fn f {[ejectorPattern.transform(f), body.transform(f),
                maybeTransform(catchPattern, f), maybeTransform(catchBody, f)]})

def makeSwitchExpr(specimen :Expr, matchers :List[Ast["Matcher"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {specimen.getStaticScope() +
                                   sumScopes(matchers)})
    object switchExpr:
        to getSpecimen():
            return specimen
        to getMatchers():
            return matchers
        to subPrintOn(out, priority):
            out.print("switch (")
            specimen.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
            def indentOut := out.indent(INDENT)
            if (priorities["braceExpr"] <= priority):
                indentOut.print(" {")
            else:
                indentOut.print(":")
            for m in matchers:
                m.subPrintOn(indentOut, priority)
                indentOut.print("\n")
            if (priorities["braceExpr"] <= priority):
                out.print("}")
    return astWrapper(switchExpr, makeSwitchExpr, [specimen, matchers], span,
        &scope, "SwitchExpr", fn f {[specimen.transform(f), transformAll(matchers, f)]})

def makeWhenExpr(args :List[Expr], body :Expr, catchers :List[Ast["Catcher"]],
                 finallyBlock :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(args + [body]).hide() +
                                   sumScopes(catchers) +
                                   scopeMaybe(finallyBlock).hide()})
    object whenExpr:
        to getArgs():
            return args
        to getBody():
            return body
        to getCatchers():
            return catchers
        to getFinally():
            return finallyBlock
        to subPrintOn(out, priority):
            printListOn("when (", args, ", ", ") ->", out, priorities["braceExpr"])
            def indentOut := out.indent(INDENT)
            if (priorities["braceExpr"] <= priority):
                indentOut.println(" {")
            else:
                indentOut.println("")
            body.subPrintOn(indentOut, priority)
            if (priorities["braceExpr"] <= priority):
                out.println("")
                out.print("}")
            for c in catchers:
                c.subPrintOn(out, priority)
            if (finallyBlock != null):
                printExprSuiteOn(fn {
                    out.print("finally")
                }, finallyBlock, true, out, priority)
    return astWrapper(whenExpr, makeWhenExpr, [args, body, catchers, finallyBlock], span,
        &scope, "WhenExpr", fn f {[transformAll(args, f), body.transform(f), transformAll(catchers, f), maybeTransform(finallyBlock, f)]})

def makeIfExpr(test :Expr, consq :Expr, alt :NullOk[Expr], span) as DeepFrozenStamp:
    # Definition of baseScope is duplicated in order to avoid chaining lazy
    # slots. ~ C.
    def &scope := if (alt == null) {
        makeLazySlot(fn {test.getStaticScope() +
                         consq.getStaticScope().hide()})
    } else {
        makeLazySlot(fn {test.getStaticScope() +
                         consq.getStaticScope().hide() +
                         alt.getStaticScope().hide()})
    }
    object ifExpr:
        to getTest():
            return test
        to getThen():
            return consq
        to getElse():
            return alt
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.print("if (")
                test.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
                }, consq, false, out, priority)
            if (alt != null):
                if (alt.getNodeName() == "IfExpr"):
                    if (priorities["braceExpr"] <= priority):
                        out.print(" ")
                    else:
                        out.println("")
                    out.print("else ")
                    alt.subPrintOn(out, priority)
                else:
                    printExprSuiteOn(fn {out.print("else")}, alt, true, out, priority)

    return astWrapper(ifExpr, makeIfExpr, [test, consq, alt], span,
        &scope, "IfExpr", fn f {[test.transform(f), consq.transform(f), maybeTransform(alt, f)]})

def makeWhileExpr(test :Expr, body :Expr, catcher :NullOk[Ast["Catcher"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes([test, body, catcher])})
    object whileExpr:
        to getTest():
            return test
        to getBody():
            return body
        to getCatcher():
            return catcher
        to subPrintOn(out, priority):
            printExprSuiteOn(fn {
                out.print("while (")
                test.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
                }, body, false, out, priority)
            if (catcher != null):
                catcher.subPrintOn(out, priority)
    return astWrapper(whileExpr, makeWhileExpr, [test, body, catcher], span,
        &scope, "WhileExpr", fn f {[test.transform(f), body.transform(f), maybeTransform(catcher, f)]})

def makeHideExpr(body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {body.getStaticScope().hide()})
    object hideExpr:
        to getBody():
            return body
        to subPrintOn(out, priority):
            def indentOut := out.indent(INDENT)
            indentOut.println("{")
            body.subPrintOn(indentOut, priorities["braceExpr"])
            out.println("")
            out.print("}")

    return astWrapper(hideExpr, makeHideExpr, [body], span,
        &scope, "HideExpr", fn f {[body.transform(f)]})

def makeValueHoleExpr(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object valueHoleExpr implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return valueHoleExpr
        to subPrintOn(out, priority):
            out.print("${expr-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(valueHoleExpr, makeValueHoleExpr, [index], span,
        &scope, "ValueHoleExpr", fn f {[index]})

def makePatternHoleExpr(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object patternHoleExpr implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return patternHoleExpr
        to subPrintOn(out, priority):
            out.print("@{expr-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(patternHoleExpr, makePatternHoleExpr, [index], span,
        &scope, "PatternHoleExpr", fn f {[index]})

def makeValueHolePattern(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object valueHolePattern implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return valueHolePattern
        to subPrintOn(out, priority):
            out.print("${pattern-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(valueHolePattern, makeValueHolePattern, [index], span,
        &scope, "ValueHolePattern", fn f {[index]})

def makePatternHolePattern(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object patternHolePattern implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return patternHolePattern
        to subPrintOn(out, priority):
            out.print("@{pattern-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(patternHolePattern, makePatternHolePattern, [index], span,
        &scope, "PatternHolePattern", fn f {[index]})

# Guard  would be 'noun :Noun' but optimizer will fold some constants here.
def makeFinalPattern(noun :Any, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def gs := scopeMaybe(guard)
    if (noun.getNodeName() == "NounExpr" &&
        gs.namesUsed().contains(noun.getName())):
        throw("Kernel guard cycle not allowed")
    def scope := makeStaticScope([], [], [noun.getName()], [], false) + gs
    object finalPattern:
        to getNoun():
            return noun
        to getGuard():
            return guard

        to withGuard(newGuard):
            return makeFinalPattern(noun, newGuard, span)

        to refutable() :Bool:
            return guard != null

        to subPrintOn(out, priority):
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(finalPattern, makeFinalPattern, [noun, guard], span,
        &scope, "FinalPattern",
        fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeSlotPattern(noun :Noun, guard :NullOk[Expr] , span) as DeepFrozenStamp:
    def gs := scopeMaybe(guard)
    if (noun.getNodeName() == "NounExpr" &&
        gs.namesUsed().contains(noun.getName())):
        throw("Kernel guard cycle not allowed")
    def scope := makeStaticScope([], [], [], [noun.getName()], false) + gs
    object slotPattern:
        to getNoun():
            return noun

        to refutable() :Bool:
            return guard != null

        to subPrintOn(out, priority):
            out.print("&")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(slotPattern, makeSlotPattern, [noun, guard], span,
        &scope, "SlotPattern", fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeBindingPattern(noun :Noun, span) as DeepFrozenStamp:
    def scope := makeStaticScope([], [], [], [noun.getName()], false)
    object bindingPattern:
        to getNoun():
            return noun

        to refutable() :Bool:
            return false

        to subPrintOn(out, priority):
            out.print("&&")
            noun.subPrintOn(out, priority)
    return astWrapper(bindingPattern, makeBindingPattern, [noun], span,
        &scope, "BindingPattern", fn f {[noun.transform(f)]})

def makeIgnorePattern(guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {scopeMaybe(guard)})
    object ignorePattern:
        to getGuard():
            return guard

        to withGuard(newGuard):
            return makeIgnorePattern(newGuard, span)

        to refutable() :Bool:
            return guard != null

        to subPrintOn(out, priority):
            out.print("_")
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(ignorePattern, makeIgnorePattern, [guard], span,
        &scope, "IgnorePattern", fn f {[maybeTransform(guard, f)]})

def makeListPattern(patterns :List[Pattern], tail :NullOk[Pattern], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(patterns + [tail])})
    object listPattern:
        to getPatterns():
            return patterns
        to getTail():
            return tail

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            printListOn("[", patterns, ", ", "]", out, priorities["pattern"])
            if (tail != null):
                out.print(" + ")
                tail.subPrintOn(out, priorities["pattern"])
    return astWrapper(listPattern, makeListPattern, [patterns, tail], span,
        &scope, "ListPattern", fn f {[transformAll(patterns, f), maybeTransform(tail, f)]})

def makeMapPatternAssoc(key :Expr, value :Pattern, default :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {key.getStaticScope() +
                                   value.getStaticScope() + scopeMaybe(default)})
    object mapPatternAssoc:
        to getKey():
            return key
        to getValue():
            return value
        to getDefault():
            return default
        to subPrintOn(out, priority):
            if (key.getNodeName() == "LiteralExpr"):
                key.subPrintOn(out, priority)
            else:
                out.print("(")
                key.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
            out.print(" => ")
            value.subPrintOn(out, priority)
            if (default != null):
                out.print(" := (")
                default.subPrintOn(out, "braceExpr")
                out.print(")")
    return astWrapper(mapPatternAssoc, makeMapPatternAssoc, [key, value, default], span,
        &scope, "MapPatternAssoc", fn f {[key.transform(f), value.transform(f), maybeTransform(default, f)]})

def makeMapPatternImport(pattern :NamePattern, default :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {pattern.getStaticScope() + scopeMaybe(default)})
    object mapPatternImport:
        to getPattern():
            return pattern
        to getDefault():
            return default
        to subPrintOn(out, priority):
            out.print("=> ")
            pattern.subPrintOn(out, priority)
            if (default != null):
                out.print(" := (")
                default.subPrintOn(out, "braceExpr")
                out.print(")")
    return astWrapper(mapPatternImport, makeMapPatternImport, [pattern, default], span,
        &scope, "MapPatternImport", fn f {[pattern.transform(f), maybeTransform(default, f)]})

def makeMapPattern(patterns :List[Ast["MapPatternAssoc", "MapPatternImport"]], tail :NullOk[Pattern], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(patterns + [tail])})
    object mapPattern:
        to getPatterns():
            return patterns
        to getTail():
            return tail

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            printListOn("[", patterns, ", ", "]", out, priorities["pattern"])
            if (tail != null):
                out.print(" | ")
                tail.subPrintOn(out, priorities["pattern"])
    return astWrapper(mapPattern, makeMapPattern, [patterns, tail], span,
        &scope, "MapPattern", fn f {[transformAll(patterns, f), maybeTransform(tail, f)]})

def makeNamedParam(key :Expr, patt :Pattern, default :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {key.getStaticScope() +
                                   patt.getStaticScope() +
                                   scopeMaybe(default)})
    object namedParam:
        to getKey():
            return key
        to getPattern():
            return patt
        to getDefault():
            return default
        to subPrintOn(out, priority):
            if (key.getNodeName() == "LiteralExpr"):
                key.subPrintOn(out, priority)
            else:
                out.print("(")
                key.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
            out.print(" => ")
            patt.subPrintOn(out, priority)
            if (default != null):
                out.print(" := (")
                default.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
    return astWrapper(namedParam, makeNamedParam, [key, patt, default], span,
        &scope, "NamedParam", fn f {[key.transform(f), patt.transform(f), maybeTransform(default, f)]})

def makeNamedParamImport(patt :NamePattern, default :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {patt.getStaticScope() +
                                   scopeMaybe(default)})
    object namedParamImport:
        to getPattern():
            return patt
        to getDefault():
            return default
        to subPrintOn(out, priority):
            out.print("=> ")
            patt.subPrintOn(out, priority)
            if (default != null):
                out.print(" := (")
                default.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
    return astWrapper(namedParamImport, makeNamedParamImport, [patt, default], span,
        &scope, "NamedParamImport", fn f {[patt.transform(f), maybeTransform(default, f)]})

def makeViaPattern(expr :Expr, subpattern :Pattern, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {expr.getStaticScope() +
                                   subpattern.getStaticScope()})
    object viaPattern:
        to getExpr():
            return expr
        to getPattern():
            return subpattern

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            out.print("via (")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
            subpattern.subPrintOn(out, priority)
    return astWrapper(viaPattern, makeViaPattern, [expr, subpattern], span,
        &scope, "ViaPattern", fn f {[expr.transform(f), subpattern.transform(f)]})

def makeSuchThatPattern(subpattern :Pattern, expr :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {expr.getStaticScope() +
                                   subpattern.getStaticScope()})
    object suchThatPattern:
        to getExpr():
            return expr
        to getPattern():
            return subpattern

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            subpattern.subPrintOn(out, priority)
            out.print(" ? (")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
    return astWrapper(suchThatPattern, makeSuchThatPattern, [subpattern, expr], span,
        &scope, "SuchThatPattern", fn f {[subpattern.transform(f), expr.transform(f)]})

def makeSamePattern(value :Expr, direction :Bool, span) as DeepFrozenStamp:
    def scope := value.getStaticScope()
    object samePattern:
        to getValue():
            return value
        to getDirection():
            return direction

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            if (direction):
                out.print("==")
            else:
                out.print("!=")
            value.subPrintOn(out, priorities["call"])
    return astWrapper(samePattern, makeSamePattern, [value, direction], span,
        &scope, "SamePattern", fn f {[value.transform(f), direction]})

def makeQuasiText(text :Str, span) as DeepFrozenStamp:
    def scope := emptyScope
    object quasiText:
        to getText():
            return text
        to subPrintOn(out, priority):
            out.print(text)
    return astWrapper(quasiText, makeQuasiText, [text], span,
        &scope, "QuasiText", fn f {[text]})

def makeQuasiExprHole(expr :Expr, span) as DeepFrozenStamp:
    def scope := expr.getStaticScope()
    object quasiExprHole:
        to getExpr():
            return expr
        to subPrintOn(out, priority):
            out.print("$")
            if (priorities["braceExpr"] < priority):
                if (expr.getNodeName() == "NounExpr" && isIdentifier(expr.getName())):
                    expr.subPrintOn(out, priority)
                    return
            out.print("{")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print("}")
    return astWrapper(quasiExprHole, makeQuasiExprHole, [expr], span,
        &scope, "QuasiExprHole", fn f {[expr.transform(f)]})


def makeQuasiPatternHole(pattern :Pattern, span) as DeepFrozenStamp:
    def scope := pattern.getStaticScope()
    object quasiPatternHole:
        to getPattern():
            return pattern
        to subPrintOn(out, priority):
            out.print("@")
            if (priorities["braceExpr"] < priority):
                if (pattern.getNodeName() == "FinalPattern"):
                    if (pattern.getGuard() == null && isIdentifier(pattern.getNoun().getName())):
                        pattern.subPrintOn(out, priority)
                        return
            out.print("{")
            pattern.subPrintOn(out, priority)
            out.print("}")
    return astWrapper(quasiPatternHole, makeQuasiPatternHole, [pattern], span,
        &scope, "QuasiPatternHole", fn f {[pattern.transform(f)]})

def quasiPrint(name, quasis, out, priority) as DeepFrozenStamp:
    if (name != null):
        out.print(name)
    out.print("`")
    for i => q in quasis:
        var p := priorities["prim"]
        if (i + 1 < quasis.size()):
            def next := quasis[i + 1]
            if (next.getNodeName() == "QuasiText"):
                if (next.getText().size() > 0 && idPart.contains(next.getText()[0])):
                    p := priorities["braceExpr"]
        q.subPrintOn(out, p)
    out.print("`")

def QuasiPiece :DeepFrozen := Ast["QuasiText", "QuasiExprHole",
                                  "QuasiPatternHole"]

def makeQuasiParserExpr(name :NullOk[Str], quasis :List[QuasiPiece], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        if (name == null) {emptyScope} else {
            makeStaticScope([name + "__quasiParser"], [],
                            [], [], false)
        } + sumScopes(quasis)
    })
    object quasiParserExpr:
        to getName():
            return name
        to getQuasis():
            return quasis
        to subPrintOn(out, priority):
            quasiPrint(name, quasis, out, priority)
    return astWrapper(quasiParserExpr, makeQuasiParserExpr, [name, quasis], span,
        &scope, "QuasiParserExpr", fn f {[name, transformAll(quasis, f)]})

def makeQuasiParserPattern(name :NullOk[Str], quasis :List[QuasiPiece], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        if (name == null) {emptyScope} else {
            makeStaticScope([name + "__quasiParser"], [],
                            [], [], false)
        } + sumScopes(quasis)
    })
    object quasiParserPattern:
        to getName():
            return name
        to getQuasis():
            return quasis

        to refutable() :Bool:
            return true

        to subPrintOn(out, priority):
            quasiPrint(name, quasis, out, priority)
    return astWrapper(quasiParserPattern, makeQuasiParserPattern, [name, quasis], span,
        &scope, "QuasiParserPattern", fn f {[name, transformAll(quasis, f)]})

object astBuilder as DeepFrozenStamp:
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
    to LiteralExpr(value, span):
        return makeLiteralExpr(value, span)
    to NounExpr(name, span):
        return makeNounExpr(name, span)
    to TempNounExpr(namePrefix, span):
        return makeTempNounExpr(namePrefix, span)
    to SlotExpr(name, span):
        return makeSlotExpr(name, span)
    to MetaContextExpr(span):
        return makeMetaContextExpr(span)
    to MetaStateExpr(span):
        return makeMetaStateExpr(span)
    to BindingExpr(name, span):
        return makeBindingExpr(name, span)
    to SeqExpr(exprs, span):
        return makeSeqExpr(exprs, span)
    to "Module"(importsList, exportsList, body, span):
        return makeModule(importsList, exportsList, body, span)
    to NamedArg(k, v, span):
        return makeNamedArg(k, v, span)
    to NamedArgExport(v, span):
        return makeNamedArgExport(v, span)
    to MethodCallExpr(rcvr, verb, arglist, namedArgs, span):
        return makeMethodCallExpr(rcvr, verb, arglist, namedArgs, span)
    to FunCallExpr(receiver, args, namedArgs, span):
        return makeFunCallExpr(receiver, args, namedArgs, span)
    to SendExpr(rcvr, verb, arglist, namedArgs, span):
        return makeSendExpr(rcvr, verb, arglist, namedArgs, span)
    to FunSendExpr(receiver, args, namedArgs, span):
        return makeFunSendExpr(receiver, args, namedArgs, span)
    to GetExpr(receiver, indices, span):
        return makeGetExpr(receiver, indices, span)
    to AndExpr(left, right, span):
        return makeAndExpr(left, right, span)
    to OrExpr(left, right, span):
        return makeOrExpr(left, right, span)
    to BinaryExpr(left, op, right, span):
        return makeBinaryExpr(left, op, right, span)
    to CompareExpr(left, op, right, span):
        return makeCompareExpr(left, op, right, span)
    to RangeExpr(left, op, right, span):
        return makeRangeExpr(left, op, right, span)
    to SameExpr(left, right, direction, span):
        return makeSameExpr(left, right, direction, span)
    to MatchBindExpr(specimen, pattern, span):
        return makeMatchBindExpr(specimen, pattern, span)
    to MismatchExpr(specimen, pattern, span):
        return makeMismatchExpr(specimen, pattern, span)
    to PrefixExpr(op, receiver, span):
        return makePrefixExpr(op, receiver, span)
    to CoerceExpr(specimen, guard, span):
        return makeCoerceExpr(specimen, guard, span)
    to CurryExpr(receiver, verb, isSend, span):
        return makeCurryExpr(receiver, verb, isSend, span)
    to ExitExpr(name, value, span):
        return makeExitExpr(name, value, span)
    to ForwardExpr(name, span):
        return makeForwardExpr(name, span)
    to VarPattern(noun, guard, span):
        return makeVarPattern(noun, guard, span)
    to DefExpr(pattern, exit_, expr, span):
        return makeDefExpr(pattern, exit_, expr, span)
    to AssignExpr(lvalue, rvalue, span):
        return makeAssignExpr(lvalue, rvalue, span)
    to VerbAssignExpr(verb, lvalue, rvalues, span):
        return makeVerbAssignExpr(verb, lvalue, rvalues, span)
    to AugAssignExpr(op, lvalue, rvalue, span):
        return makeAugAssignExpr(op, lvalue, rvalue, span)
    to "Method"(docstring, verb, patterns, namedPatts, resultGuard, body, span):
        return makeMethod(docstring, verb, patterns, namedPatts, resultGuard, body, span)
    to "To"(docstring, verb, patterns, namedPatts, resultGuard, body, span):
        return makeTo(docstring, verb, patterns, namedPatts, resultGuard, body, span)
    to Matcher(pattern, body, span):
        return makeMatcher(pattern, body, span)
    to Catcher(pattern, body, span):
        return makeCatcher(pattern, body, span)
    to Script(extend, methods, matchers, span):
        return makeScript(extend, methods, matchers, span)
    to FunctionScript(patterns, namedPatterns, resultGuard, body, span):
        return makeFunctionScript(patterns, namedPatterns, resultGuard, body, span)
    to FunctionExpr(patterns, body, span):
        return makeFunctionExpr(patterns, body, span)
    to ListExpr(items, span):
        return makeListExpr(items, span)
    to ListComprehensionExpr(iterable, filter, key, value, body, span):
        return makeListComprehensionExpr(iterable, filter, key, value, body, span)
    to MapExprAssoc(key, value, span):
        return makeMapExprAssoc(key, value, span)
    to MapExprExport(value, span):
        return makeMapExprExport(value, span)
    to MapExpr(pairs, span):
        return makeMapExpr(pairs, span)
    to MapComprehensionExpr(iterable, filter, key, value, bodyk, bodyv, span):
        return makeMapComprehensionExpr(iterable, filter, key, value, bodyk, bodyv, span)
    to ForExpr(iterable, key, value, body, catchPattern, catchBlock, span):
        return makeForExpr(iterable, key, value, body, catchPattern, catchBlock, span)
    to ObjectExpr(docstring, name, asExpr, auditors, script, span):
        return makeObjectExpr(docstring, name, asExpr, auditors, script, span)
    to ParamDesc(name, guard, span):
        return makeParamDesc(name, guard, span)
    to MessageDesc(docstring, verb, params, resultGuard, span):
        return makeMessageDesc(docstring, verb, params, resultGuard, span)
    to InterfaceExpr(docstring, name, stamp, parents, auditors, messages, span):
        return makeInterfaceExpr(docstring, name, stamp, parents, auditors, messages, span)
    to FunctionInterfaceExpr(docstring, name, stamp, parents, auditors, messageDesc, span):
        return makeFunctionInterfaceExpr(docstring, name, stamp, parents, auditors, messageDesc, span)
    to CatchExpr(body, pattern, catcher, span):
        return makeCatchExpr(body, pattern, catcher, span)
    to FinallyExpr(body, unwinder, span):
        return makeFinallyExpr(body, unwinder, span)
    to TryExpr(body, catchers, finallyBlock, span):
        return makeTryExpr(body, catchers, finallyBlock, span)
    to EscapeExpr(ejectorPattern, body, catchPattern, catchBody, span):
        return makeEscapeExpr(ejectorPattern, body, catchPattern, catchBody, span)
    to SwitchExpr(specimen, matchers, span):
        return makeSwitchExpr(specimen, matchers, span)
    to WhenExpr(args, body, catchers, finallyBlock, span):
        return makeWhenExpr(args, body, catchers, finallyBlock, span)
    to IfExpr(test, consq, alt, span):
        return makeIfExpr(test, consq, alt, span)
    to WhileExpr(test, body, catcher, span):
        return makeWhileExpr(test, body, catcher, span)
    to HideExpr(body, span):
        return makeHideExpr(body, span)
    to ValueHoleExpr(index, span):
        return makeValueHoleExpr(index, span)
    to PatternHoleExpr(index, span):
        return makePatternHoleExpr(index, span)
    to ValueHolePattern(index, span):
        return makeValueHolePattern(index, span)
    to PatternHolePattern(index, span):
        return makePatternHolePattern(index, span)
    to FinalPattern(noun, guard, span):
        return makeFinalPattern(noun, guard, span)
    to SlotPattern(noun, guard, span):
        return makeSlotPattern(noun, guard, span)
    to BindingPattern(noun, span):
        return makeBindingPattern(noun, span)
    to BindPattern(noun, guard, span):
        return makeBindPattern(noun, guard, span)
    to IgnorePattern(guard, span):
        return makeIgnorePattern(guard, span)
    to ListPattern(patterns, tail, span):
        return makeListPattern(patterns, tail, span)
    to MapPatternAssoc(key, value, default, span):
        return makeMapPatternAssoc(key, value, default, span)
    to MapPatternImport(value, default, span):
        return makeMapPatternImport(value, default, span)
    to MapPattern(patterns, tail, span):
        return makeMapPattern(patterns, tail, span)
    to NamedParam(k, p, default, span):
        return makeNamedParam(k, p, default, span)
    to NamedParamImport(p, default, span):
        return makeNamedParamImport(p, default, span)
    to ViaPattern(expr, subpattern, span):
        return makeViaPattern(expr, subpattern, span)
    to SuchThatPattern(subpattern, expr, span):
        return makeSuchThatPattern(subpattern, expr, span)
    to SamePattern(value, direction, span):
        return makeSamePattern(value, direction, span)
    to QuasiText(text, span):
        return makeQuasiText(text, span)
    to QuasiExprHole(expr, span):
        return makeQuasiExprHole(expr, span)
    to QuasiPatternHole(pattern, span):
        return makeQuasiPatternHole(pattern, span)
    to QuasiParserExpr(name, quasis, span):
        return makeQuasiParserExpr(name, quasis, span)
    to QuasiParserPattern(name, quasis, span):
        return makeQuasiParserPattern(name, quasis, span)

[=> astBuilder]
