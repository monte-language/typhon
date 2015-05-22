def [=> term__quasiParser] := import("lib/monte/termParser")
def [=> UTF8] | _ := import("lib/codec/utf8")

def MONTE_KEYWORDS := [
"as", "bind", "break", "catch", "continue", "def", "else", "escape",
"exit", "extends", "export", "finally", "fn", "for", "guards", "if",
"implements", "in", "interface", "match", "meta", "method", "module",
"object", "pass", "pragma", "return", "switch", "to", "try", "var",
"via", "when", "while", "_"]

def idStart := 'a'..'z' | 'A'..'Z' | '_'..'_'
def idPart := idStart | '0'..'9'
def INDENT := "    "
# note to future drunk self: lower precedence number means add parens when
# inside a higher-precedence-number expression
def priorities := [
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
def makeStaticScope(read, set, defs, vars, metaStateExpr):
    def namesRead := read.asSet()
    def namesSet := set.asSet()
    def defNames := defs.asSet()
    def varNames := vars.asSet()
    return object staticScope:
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
            return makeStaticScope(namesRead, namesSet, [], [],
                                   metaStateExpr)

        to add(right):
            if (right == null):
                return staticScope
            def rightNamesRead := (right.getNamesRead() - defNames) - varNames
            def rightNamesSet := right.getNamesSet() - varNames
            def badAssigns := rightNamesSet & defNames
            if (badAssigns.size() > 0):
                throw(`Can't assign to final nouns ${badAssigns}`)
            return makeStaticScope(namesRead | rightNamesRead,
                                   namesSet | rightNamesSet,
                                   defNames | right.getDefNames(),
                                   varNames | right.getVarNames(),
                                   metaStateExpr | right.getMetaStateExprFlag())
        to namesUsed():
            return namesRead | namesSet

        to outNames():
            return defNames | varNames

        to printOn(out):
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

def emptyScope := makeStaticScope([], [], [], [], false)

def sumScopes(nodes):
    var result := emptyScope
    for node in nodes:
        if (node != null):
            result += node.getStaticScope()
    return result

def scopeMaybe(optNode):
    if (optNode == null):
        return emptyScope
    return optNode.getStaticScope()

def all(iterable, pred):
    for item in iterable:
        if (!pred(item)):
            return false
    return true

def maybeTransform(node, f):
    if (node == null):
        return null
    return node.transform(f)

def transformAll(nodes, f):
    def results := [].diverge()
    for n in nodes:
        results.push(n.transform(f))
    return results.snapshot()

def isIdentifier(name):
    if (MONTE_KEYWORDS.contains(name.toLowerCase())):
        return false
    return idStart(name[0]) && all(name.slice(1), idPart)

def printListOn(left, nodes, sep, right, out, priority):
    out.print(left)
    if (nodes.size() >= 1):
        for n in nodes.slice(0, nodes.size() - 1):
            n.subPrintOn(out, priority)
            out.print(sep)
        nodes.last().subPrintOn(out, priority)
    out.print(right)

def printDocstringOn(docstring, out, indentLastLine):
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

def printSuiteOn(leaderFn, printContents, cuddle, noLeaderNewline, out, priority):
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

def printExprSuiteOn(leaderFn, suite, cuddle, out, priority):
        printSuiteOn(leaderFn, suite.subPrintOn, cuddle, false, out, priority)

def printDocExprSuiteOn(leaderFn, docstring, suite, out, priority):
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, true)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

def printObjectSuiteOn(leaderFn, docstring, suite, out, priority):
        printSuiteOn(leaderFn, fn o, p {
            printDocstringOn(docstring, o, false)
            suite.subPrintOn(o, p)
            }, false, true, out, priority)

def astWrapper(node, maker, args, span, scope, termFunctor, transformArgs):
    return object astNode extends node:
        to getStaticScope():
            return scope
        to getSpan():
            return span
        to getNodeName():
            return termFunctor.getTag().getName()
        to asTerm():
            def termit(subnode, maker, args, span):
                return subnode.asTerm()
            return term`$termFunctor(${transformArgs(termit)}*)`.withSpan(span)
        to transform(f):
            return f(astNode, maker, transformArgs(f), span)
        to _uncall():
            return [maker, "run", args + [span]]
        to _printOn(out):
            astNode.subPrintOn(out, 0)

def makeLiteralExpr(value, span):
    object literalExpr:
        to getValue():
            return value
        to subPrintOn(out, priority):
            out.quote(value)
    return astWrapper(literalExpr, makeLiteralExpr, [value], span,
        emptyScope, term`LiteralExpr`, fn f {[value]})

def makeNounExpr(name, span):
    def scope := makeStaticScope([name], [], [], [], false)
    object nounExpr:
        to getName():
            return name
        to subPrintOn(out, priority):
            if (isIdentifier(name)):
                out.print(name)
            else:
                out.print("::")
                out.quote(name)
    return astWrapper(nounExpr, makeNounExpr, [name], span,
         scope, term`NounExpr`, fn f {[name]})

def makeTempNounExpr(namePrefix, span):
    object name extends namePrefix:
        to _printOn(out):
            out.print("$<temp ")
            out.print(namePrefix)
            out.print(">")
    def scope := makeStaticScope([name], [], [], [], false)
    object tempNounExpr:
        to getName():
            return namePrefix
        to subPrintOn(out, priority):
            out.print(name)
    return astWrapper(tempNounExpr, makeTempNounExpr, [name], span,
         scope, term`TempNounExpr`, fn f {[namePrefix]})

def makeSlotExpr(noun, span):
    def scope := noun.getStaticScope()
    object slotExpr:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&")
            out.print(noun)
    return astWrapper(slotExpr, makeSlotExpr, [noun], span,
        scope, term`SlotExpr`, fn f {[noun.transform(f)]})

def makeMetaContextExpr(span):
    def scope := emptyScope
    object metaContextExpr:
        to subPrintOn(out, priority):
            out.print("meta.context()")
    return astWrapper(metaContextExpr, makeMetaContextExpr, [], span,
        scope, term`MetaContextExpr`, fn f {[]})

def makeMetaStateExpr(span):
    def scope := makeStaticScope([], [], [], [], true)
    object metaStateExpr:
        to subPrintOn(out, priority):
            out.print("meta.getState()")
    return astWrapper(metaStateExpr, makeMetaStateExpr, [], span,
        scope, term`MetaStateExpr`, fn f {[]})

def makeBindingExpr(noun, span):
    def scope := noun.getStaticScope()
    object bindingExpr:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&&")
            out.print(noun)
    return astWrapper(bindingExpr, makeBindingExpr, [noun], span,
        scope, term`BindingExpr`, fn f {[noun.transform(f)]})

def makeSeqExpr(exprs, span):
    def scope := sumScopes(exprs)
    object seqExpr:
        to getExprs():
            return exprs
        to subPrintOn(out, priority):
            if (priority > priorities["braceExpr"]):
                out.print("(")
            var first := true
            if (priorities["braceExpr"] >= priority && exprs == []):
                out.print("pass")
            for e in exprs:
                if (!first):
                    out.println("")
                first := false
                e.subPrintOn(out, priority.min(priorities["braceExpr"]))
    return astWrapper(seqExpr, makeSeqExpr, [exprs], span,
        scope, term`SeqExpr`, fn f {[transformAll(exprs, f)]})

def makeModule(imports, exports, body, span):
    def scope := sumScopes(imports + exports)
    object ::"module":
        to getImports():
            return imports
        to getExports():
            return exports
        to getBody():
            return body
        to subPrintOn(out, priority):
            out.print("module")
            if (imports.size() > 0):
                out.print(" ")
                printListOn("", imports, ", ", "", out, priorities["braceExpr"])
            out.println("")
            if (exports.size() > 0):
                out.print("export ")
                printListOn("(", exports, ", ", ")", out, priorities["braceExpr"])
                out.println("")
            body.subPrintOn(out, priorities["indentExpr"])
    return astWrapper(::"module", makeModule, [imports, exports, body], span,
        scope, term`Module`, fn f {[
            transformAll(imports, f),
            transformAll(exports, f),
            body.transform(f)]})

def makeMethodCallExpr(rcvr, verb, arglist, span):
    def scope := sumScopes(arglist + [rcvr])
    object methodCallExpr:
        to getReceiver():
            return rcvr
        to getVerb():
            return verb
        to getArgs():
            return arglist
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            rcvr.subPrintOn(out, priorities["call"])
            out.print(".")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            printListOn("(", arglist, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(methodCallExpr, makeMethodCallExpr,
        [rcvr, verb, arglist], span, scope, term`MethodCallExpr`,
        fn f {[rcvr.transform(f), verb, transformAll(arglist, f)]})

def makeFunCallExpr(receiver, args, span):
    def scope := sumScopes(args + [receiver])
    object funCallExpr:
        to getReceiver():
            return receiver
        to getArgs():
            return args
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            receiver.subPrintOn(out, priorities["call"])
            printListOn("(", args, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(funCallExpr, makeFunCallExpr, [receiver, args], span,
        scope, term`FunCallExpr`, fn f {[receiver.transform(f), transformAll(args, f)]})

def makeSendExpr(rcvr, verb, arglist, span):
    def scope := sumScopes(arglist + [rcvr])
    object sendExpr:
        to getReceiver():
            return rcvr
        to getVerb():
            return verb
        to getArgs():
            return arglist
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            rcvr.subPrintOn(out, priorities["call"])
            out.print(" <- ")
            if (isIdentifier(verb)):
                out.print(verb)
            else:
                out.quote(verb)
            printListOn("(", arglist, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(sendExpr, makeSendExpr,
        [rcvr, verb, arglist], span, scope, term`SendExpr`,
        fn f {[rcvr.transform(f), verb, transformAll(arglist, f)]})

def makeFunSendExpr(receiver, args, span):
    def scope := sumScopes(args + [receiver])
    object funSendExpr:
        to getReceiver():
            return receiver
        to getArgs():
            return args
        to subPrintOn(out, priority):
            if (priorities["call"] < priority):
                out.print("(")
            receiver.subPrintOn(out, priorities["call"])
            printListOn(" <- (", args, ", ", ")", out, priorities["braceExpr"])
            if (priorities["call"] < priority):
                out.print(")")
    return astWrapper(funSendExpr, makeFunSendExpr, [receiver, args], span,
        scope, term`FunSendExpr`, fn f {[receiver.transform(f), transformAll(args, f)]})

def makeGetExpr(receiver, indices, span):
    def scope := sumScopes(indices + [receiver])
    object getExpr:
        to getReceiver():
            return receiver
        to getIndices():
            return indices
        to subPrintOn(out, priority):
            receiver.subPrintOn(out, priorities["call"])
            printListOn("[", indices, ", ", "]", out, priorities["braceExpr"])

    return astWrapper(getExpr, makeGetExpr, [receiver, indices], span,
        scope, term`GetExpr`, fn f {[receiver.transform(f), transformAll(indices, f)]})

def makeAndExpr(left, right, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`AndExpr`, fn f {[left.transform(f), right.transform(f)]})

def makeOrExpr(left, right, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`OrExpr`, fn f {[left.transform(f), right.transform(f)]})

def operatorsToNamePrio := [
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

def makeBinaryExpr(left, op, right, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`BinaryExpr`, fn f {[left.transform(f), op, right.transform(f)]})

def comparatorsToName := [
    ">" => "greaterThan", "<" => "lessThan",
    ">=" => "geq", "<=" => "leq",
    "<=>" => "asBigAs"]

def makeCompareExpr(left, op, right, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`CompareExpr`, fn f {[left.transform(f), op, right.transform(f)]})

def makeRangeExpr(left, op, right, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`RangeExpr`, fn f {[left.transform(f), op, right.transform(f)]})

def makeSameExpr(left, right, direction, span):
    def scope := left.getStaticScope() + right.getStaticScope()
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
        scope, term`SameExpr`, fn f {[left.transform(f), right.transform(f), direction]})

def makeMatchBindExpr(specimen, pattern, span):
    def scope := specimen.getStaticScope() + pattern.getStaticScope()
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
        scope, term`MatchBindExpr`, fn f {[specimen.transform(f), pattern.transform(f)]})

def makeMismatchExpr(specimen, pattern, span):
    def scope := specimen.getStaticScope() + pattern.getStaticScope()
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
        scope, term`MismatchExpr`, fn f {[specimen.transform(f), pattern.transform(f)]})

def unaryOperatorsToName := ["~" => "complement", "!" => "not", "-" => "negate"]

def makePrefixExpr(op, receiver, span):
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
        scope, term`PrefixExpr`, fn f {[op, receiver.transform(f)]})

def makeCoerceExpr(specimen, guard, span):
    def scope := specimen.getStaticScope() + guard.getStaticScope()
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
        scope, term`CoerceExpr`, fn f {[specimen.transform(f), guard.transform(f)]})

def makeCurryExpr(receiver, verb, isSend, span):
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
        scope, term`CurryExpr`, fn f {[receiver.transform(f), verb, isSend]})

def makeExitExpr(name, value, span):
    def scope := scopeMaybe(value)
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
        scope, term`ExitExpr`, fn f {[name, maybeTransform(value, f)]})

def makeForwardExpr(patt, span):
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
        scope, term`ForwardExpr`, fn f {[patt.transform(f)]})

def makeVarPattern(noun, guard, span):
    def scope := makeStaticScope([], [], [], [noun.getName()], false)
    object varPattern:
        to getNoun():
            return noun
        to getGuard():
            return guard
        to subPrintOn(out, priority):
            out.print("var ")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(varPattern, makeVarPattern, [noun, guard], span,
        scope, term`VarPattern`,
        fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeBindPattern(noun, guard, span):
    def scope := makeStaticScope([], [], [noun.getName()], [], false) + scopeMaybe(guard)
    object bindPattern:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("bind ")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(bindPattern, makeBindPattern, [noun, guard], span,
        scope, term`BindPattern`, fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeDefExpr(pattern, exit_, expr, span):
    def scope := if (exit_ == null) {
        pattern.getStaticScope() + expr.getStaticScope()
    } else {
        pattern.getStaticScope() + exit_.getStaticScope() + expr.getStaticScope()
    }
    object defExpr:
        to getPattern():
            return pattern
        to getExit():
            return exit_
        to getExpr():
            return expr
        to subPrintOn(out, priority):
            if (priorities["assign"] < priority):
                out.print("(")
            if (![makeVarPattern, makeBindPattern].contains(pattern._uncall()[0])):
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
        scope, term`DefExpr`, fn f {[pattern.transform(f), if (exit_ == null) {null} else {exit_.transform(f)}, expr.transform(f)]})

def makeAssignExpr(lvalue, rvalue, span):
    def [lmaker, _, largs] := lvalue._uncall()
    def lscope := if (lmaker == makeNounExpr || lmaker == makeTempNounExpr) {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def scope := lscope + rvalue.getStaticScope()
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
        scope, term`AssignExpr`, fn f {[lvalue.transform(f), rvalue.transform(f)]})

def makeVerbAssignExpr(verb, lvalue, rvalues, span):
    def [lmaker, _, largs] := lvalue._uncall()
    def lscope := if (lmaker == makeNounExpr || lmaker == makeTempNounExpr) {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def scope := lscope + sumScopes(rvalues)
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
        scope, term`VerbAssignExpr`, fn f {[verb, lvalue.transform(f), transformAll(rvalues, f)]})


def makeAugAssignExpr(op, lvalue, rvalue, span):
    def [lmaker, _, largs] := lvalue._uncall()
    def lscope := if (lmaker == makeNounExpr || lmaker == makeTempNounExpr) {
        makeStaticScope([], [lvalue.getName()], [], [], false)
    } else {
        lvalue.getStaticScope()
    }
    def scope := lscope + rvalue.getStaticScope()
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
        scope, term`AugAssignExpr`, fn f {[op, lvalue.transform(f), rvalue.transform(f)]})

def makeMethod(docstring, verb, patterns, resultGuard, body, span):
    def scope := sumScopes(patterns + [resultGuard, body]).hide()
    object ::"method":
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getPatterns():
            return patterns
        to getResultGuard():
            return resultGuard
        to getBody():
            return body
        to subPrintOn(out, priority):
            printDocExprSuiteOn(fn {
                out.lnPrint("method ")
                if (isIdentifier(verb)) {
                    out.print(verb)
                } else {
                    out.quote(verb)
                }
                printListOn("(", patterns, ", ", ")", out, priorities["pattern"])
                if (resultGuard != null) {
                    out.print(" :")
                    resultGuard.subPrintOn(out, priorities["call"])
                }
            }, docstring, body, out, priority)
    return astWrapper(::"method", makeMethod, [docstring, verb, patterns, resultGuard, body], span,
        scope, term`Method`, fn f {[docstring, verb, transformAll(patterns, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeTo(docstring, verb, patterns, resultGuard, body, span):
    def scope := sumScopes(patterns + [resultGuard, body]).hide()
    object ::"to":
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getPatterns():
            return patterns
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
                printListOn("(", patterns, ", ", ")", out, priorities["pattern"])
                if (resultGuard != null) {
                    out.print(" :")
                    resultGuard.subPrintOn(out, priorities["call"])
                }
            }, docstring, body, out, priority)
    return astWrapper(::"to", makeTo, [docstring, verb, patterns, resultGuard, body], span,
        scope, term`To`, fn f {[docstring, verb, transformAll(patterns, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeMatcher(pattern, body, span):
    def scope := (pattern.getStaticScope() + body.getStaticScope()).hide()
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
        scope, term`Matcher`, fn f {[pattern.transform(f), body.transform(f)]})

def makeCatcher(pattern, body, span):
    def scope := (pattern.getStaticScope() + body.getStaticScope()).hide()
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
        scope, term`Catcher`, fn f {[pattern.transform(f), body.transform(f)]})

def makeScript(extend, methods, matchers, span):
    def scope := sumScopes(methods + matchers)
    object script:
        to getExtends():
            return extend
        to getMethods():
            return methods
        to getMatchers():
            return matchers
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
        scope, term`Script`, fn f {[maybeTransform(extend, f), transformAll(methods, f), transformAll(matchers, f)]})

def makeFunctionScript(patterns, resultGuard, body, span):
    def scope := sumScopes(patterns + [resultGuard, body]).hide()
    object functionScript:
        to getPatterns():
            return patterns
        to getResultGuard():
            return resultGuard
        to getBody():
            return body
        to printObjectHeadOn(name, asExpr, auditors, out, priority):
            out.print("def ")
            name.subPrintOn(out, priorities["pattern"])
            printListOn("(", patterns, ", ", ")", out, priorities["pattern"])
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
    return astWrapper(functionScript, makeFunctionScript, [patterns, resultGuard, body], span,
        scope, term`FunctionScript`, fn f {[transformAll(patterns, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeFunctionExpr(patterns, body, span):
    def scope := (sumScopes(patterns) + body.getStaticScope()).hide()
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
        scope, term`FunctionExpr`, fn f {[transformAll(patterns, f), body.transform(f)]})

def makeListExpr(items, span):
    def scope := sumScopes(items)
    object listExpr:
        to getItems():
            return items
        to subPrintOn(out, priority):
            printListOn("[", items, ", ", "]", out, priorities["braceExpr"])
    return astWrapper(listExpr, makeListExpr, [items], span,
        scope, term`ListExpr`, fn f {[transformAll(items, f)]})

def makeListComprehensionExpr(iterable, filter, key, value, body, span):
    def scope := sumScopes([iterable, key, value, filter, body]).hide()
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
        scope, term`ListComprehensionExpr`, fn f {[iterable.transform(f), maybeTransform(filter, f), maybeTransform(key, f), value.transform(f), body.transform(f)]})

def makeMapExprAssoc(key, value, span):
    def scope := key.getStaticScope() + value.getStaticScope()
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
        scope, term`MapExprAssoc`, fn f {[key.transform(f), value.transform(f)]})

def makeMapExprExport(value, span):
    def scope := value.getStaticScope()
    object mapExprExport:
        to getValue():
            return value
        to subPrintOn(out, priority):
            out.print("=> ")
            value.subPrintOn(out, priorities["prim"])
    return astWrapper(mapExprExport, makeMapExprExport, [value], span,
        scope, term`MapExprExport`, fn f {[value.transform(f)]})

def makeMapExpr(pairs ? (pairs.size() > 0), span):
    def scope := sumScopes(pairs)
    object mapExpr:
        to getPairs():
            return pairs
        to subPrintOn(out, priority):
            printListOn("[", pairs, ", ", "]", out, priorities["braceExpr"])
    return astWrapper(mapExpr, makeMapExpr, [pairs], span,
        scope, term`MapExpr`, fn f {[transformAll(pairs, f)]})

def makeMapComprehensionExpr(iterable, filter, key, value, bodyk, bodyv, span):
    def scope := sumScopes([iterable, key, value, filter, bodyk, bodyv]).hide()
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
        scope, term`MapComprehensionExpr`, fn f {[iterable.transform(f), maybeTransform(filter, f), maybeTransform(key, f), value.transform(f), bodyk.transform(f), bodyv.transform(f)]})

def makeForExpr(iterable, key, value, body, catchPattern, catchBody, span):
    def scope := sumScopes([iterable, key, value, body]).hide()
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
        scope, term`ForExpr`, fn f {[iterable.transform(f), maybeTransform(key, f), value.transform(f), body.transform(f), maybeTransform(catchPattern, f), maybeTransform(catchBody, f)]})

def makeObjectExpr(docstring, name, asExpr, auditors, script, span):
    def scope := name.getStaticScope() + sumScopes([asExpr] + auditors).hide() + script.getStaticScope()
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
        to subPrintOn(out, priority):
            def printIt := if (script._uncall()[0] == makeFunctionScript) {
                printDocExprSuiteOn
            } else {
                printObjectSuiteOn
            }
            printIt(fn {
                script.printObjectHeadOn(name, asExpr, auditors, out, priority)
            }, docstring, script, out, priority)
    return astWrapper(ObjectExpr, makeObjectExpr, [docstring, name, asExpr, auditors, script], span,
        scope, term`ObjectExpr`, fn f {[docstring, name.transform(f), maybeTransform(asExpr, f), transformAll(auditors, f), script.transform(f)]})

def makeParamDesc(name, guard, span):
    def scope := scopeMaybe(guard)
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
        scope, term`ParamDesc`, fn f {[name, maybeTransform(guard, f)]})

def makeMessageDesc(docstring, verb, params, resultGuard, span):
    def scope := sumScopes(params + [resultGuard])
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
        scope, term`MessageDesc`, fn f {[docstring, verb, transformAll(params, f), maybeTransform(resultGuard, f)]})


def makeInterfaceExpr(docstring, name, stamp, parents, auditors, messages, span):
    def scope := name.getStaticScope() + sumScopes(parents + [stamp] + auditors + messages)
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
        scope, term`InterfaceExpr`, fn f {[docstring, name.transform(f), maybeTransform(stamp, f), transformAll(parents, f), transformAll(auditors, f), transformAll(messages, f)]})

def makeFunctionInterfaceExpr(docstring, name, stamp, parents, auditors, messageDesc, span):
    def scope := name.getStaticScope() + sumScopes(parents + [stamp] + auditors + [messageDesc])
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
        scope, term`FunctionInterfaceExpr`, fn f {[docstring, name.transform(f), maybeTransform(stamp, f), transformAll(parents, f), transformAll(auditors, f), messageDesc.transform(f)]})

def makeCatchExpr(body, pattern, catcher, span):
    def scope := body.getStaticScope().hide() + (pattern.getStaticScope() + catcher.getStaticScope()).hide()
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
        scope, term`CatchExpr`, fn f {[body.transform(f), pattern.transform(f),
                                       catcher.transform(f)]})

def makeFinallyExpr(body, unwinder, span):
    def scope := body.getStaticScope().hide() + unwinder.getStaticScope().hide()
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
        scope, term`FinallyExpr`, fn f {[body.transform(f), unwinder.transform(f)]})

def makeTryExpr(body, catchers, finallyBlock, span):
    def baseScope := (body.getStaticScope() + sumScopes(catchers)).hide()
    def scope := if (finallyBlock == null) {
        baseScope
    } else {
        baseScope + finallyBlock.getStaticScope().hide()
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
        scope, term`TryExpr`, fn f {[body.transform(f), transformAll(catchers, f),maybeTransform(finallyBlock, f)]})

def makeEscapeExpr(ejectorPattern, body, catchPattern, catchBody, span):
    def baseScope := (ejectorPattern.getStaticScope() + body.getStaticScope()).hide()
    def scope := if (catchPattern == null) {
        baseScope
    } else {
        baseScope + (catchPattern.getStaticScope() + catchBody.getStaticScope()).hide()
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
        scope, term`EscapeExpr`,
         fn f {[ejectorPattern.transform(f), body.transform(f),
                maybeTransform(catchPattern, f), maybeTransform(catchBody, f)]})

def makeSwitchExpr(specimen, matchers, span):
    def scope := specimen.getStaticScope() + sumScopes(matchers)
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
        scope, term`SwitchExpr`, fn f {[specimen.transform(f), transformAll(matchers, f)]})

def makeWhenExpr(args, body, catchers, finallyBlock, span):
    def scope := sumScopes(args + [body]).hide() + sumScopes(catchers) + scopeMaybe(finallyBlock).hide()
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
        scope, term`WhenExpr`, fn f {[transformAll(args, f), body.transform(f), transformAll(catchers, f), maybeTransform(finallyBlock, f)]})

def makeIfExpr(test, consq, alt, span):
    def baseScope := test.getStaticScope() + consq.getStaticScope().hide()
    def scope := if (alt == null) {
        baseScope
    } else {
        baseScope + alt.getStaticScope().hide()
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
        scope, term`IfExpr`, fn f {[test.transform(f), consq.transform(f), maybeTransform(alt, f)]})

def makeWhileExpr(test, body, catcher, span):
    def scope := sumScopes([test, body, catcher])
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
        scope, term`WhileExpr`, fn f {[test.transform(f), body.transform(f), maybeTransform(catcher, f)]})

def makeHideExpr(body, span):
    def scope := body.getStaticScope().hide()
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
        scope, term`HideExpr`, fn f {[body.transform(f)]})

def makeValueHoleExpr(index, span):
    def scope := null
    object valueHoleExpr:
        to getIndex():
            return index
        to subPrintOn(out, priority):
            out.print("${value-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(valueHoleExpr, makeValueHoleExpr, [index], span,
        scope, term`ValueHoleExpr`, fn f {[index]})

def makePatternHoleExpr(index, span):
    def scope := null
    object patternHoleExpr:
        to getIndex():
            return index
        to subPrintOn(out, priority):
            out.print("${pattern-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(patternHoleExpr, makePatternHoleExpr, [index], span,
        scope, term`PatternHoleExpr`, fn f {[index]})

def makeValueHolePattern(index, span):
    def scope := null
    object valueHolePattern:
        to getIndex():
            return index
        to subPrintOn(out, priority):
            out.print("@{value-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(valueHolePattern, makeValueHolePattern, [index], span,
        scope, term`ValueHolePattern`, fn f {[index]})

def makePatternHolePattern(index, span):
    def scope := null
    object patternHolePattern:
        to getIndex():
            return index
        to subPrintOn(out, priority):
            out.print("@{pattern-hole ")
            out.print(index)
            out.print("}")
    return astWrapper(patternHolePattern, makePatternHolePattern, [index], span,
        scope, term`PatternHolePattern`, fn f {[index]})

def makeFinalPattern(noun, guard, span):
    def gs := scopeMaybe(guard)
    if (gs.namesUsed().contains(noun.getName())):
        throw("Kernel guard cycle not allowed")
    def scope := makeStaticScope([], [], [noun.getName()], [], false) + gs
    object finalPattern:
        to getNoun():
            return noun
        to getGuard():
            return guard
        to subPrintOn(out, priority):
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(finalPattern, makeFinalPattern, [noun, guard], span,
        scope, term`FinalPattern`,
        fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeSlotPattern(noun, guard, span):
    def gs := scopeMaybe(guard)
    if (gs.namesUsed().contains(noun.getName())):
        throw("Kernel guard cycle not allowed")
    def scope := makeStaticScope([], [], [noun.getName()], [], false) + gs
    object slotPattern:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&")
            noun.subPrintOn(out, priority)
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(slotPattern, makeSlotPattern, [noun, guard], span,
        scope, term`SlotPattern`, fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeBindingPattern(noun, span):
    def scope := makeStaticScope([], [], [noun.getName()], [], false)
    object bindingPattern:
        to getNoun():
            return noun
        to subPrintOn(out, priority):
            out.print("&&")
            noun.subPrintOn(out, priority)
    return astWrapper(bindingPattern, makeBindingPattern, [noun], span,
        scope, term`BindingPattern`, fn f {[noun.transform(f)]})

def makeIgnorePattern(guard, span):
    def scope := scopeMaybe(guard)
    object ignorePattern:
        to getGuard():
            return guard
        to subPrintOn(out, priority):
            out.print("_")
            if (guard != null):
                out.print(" :")
                guard.subPrintOn(out, priorities["order"])
    return astWrapper(ignorePattern, makeIgnorePattern, [guard], span,
        scope, term`IgnorePattern`, fn f {[maybeTransform(guard, f)]})

def makeListPattern(patterns, tail, span):
    def scope := sumScopes(patterns + [tail])
    object listPattern:
        to getPatterns():
            return patterns
        to getTail():
            return tail
        to subPrintOn(out, priority):
            printListOn("[", patterns, ", ", "]", out, priorities["pattern"])
            if (tail != null):
                out.print(" + ")
                tail.subPrintOn(out, priorities["pattern"])
    return astWrapper(listPattern, makeListPattern, [patterns, tail], span,
        scope, term`ListPattern`, fn f {[transformAll(patterns, f), maybeTransform(tail, f)]})

def makeMapPatternAssoc(key, value, span):
    def scope := key.getStaticScope() + value.getStaticScope()
    object mapPatternAssoc:
        to getKey():
            return key
        to getValue():
            return value
        to subPrintOn(out, priority):
            if (key._uncall()[0] == makeLiteralExpr):
                key.subPrintOn(out, priority)
            else:
                out.print("(")
                key.subPrintOn(out, priorities["braceExpr"])
                out.print(")")
            out.print(" => ")
            value.subPrintOn(out, priority)
    return astWrapper(mapPatternAssoc, makeMapPatternAssoc, [key, value], span,
        scope, term`MapPatternAssoc`, fn f {[key.transform(f), value.transform(f)]})

def makeMapPatternImport(pattern, span):
    def scope := pattern.getStaticScope()
    object mapPatternImport:
        to getPattern():
            return pattern
        to subPrintOn(out, priority):
            out.print("=> ")
            pattern.subPrintOn(out, priority)
    return astWrapper(mapPatternImport, makeMapPatternImport, [pattern], span,
        scope, term`MapPatternImport`, fn f {[pattern.transform(f)]})

def makeMapPatternRequired(keyer, span):
    def scope := keyer.getStaticScope()
    object mapPatternRequired:
        to getKeyer():
            return keyer
        to getDefault():
            return null
        to subPrintOn(out, priority):
            keyer.subPrintOn(out, priority)
    return astWrapper(mapPatternRequired, makeMapPatternRequired, [keyer], span,
        scope, term`MapPatternRequired`, fn f {[keyer.transform(f)]})

def makeMapPatternDefault(keyer, default, span):
    def scope := keyer.getStaticScope() + default.getStaticScope()
    object mapPatternDefault:
        to getKeyer():
            return keyer
        to getDefault():
            return default
        to subPrintOn(out, priority):
            keyer.subPrintOn(out, priority)
            out.print(" := (")
            default.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
    return astWrapper(mapPatternDefault, makeMapPatternDefault, [keyer, default], span,
        scope, term`MapPatternDefault`, fn f {[keyer.transform(f), default.transform(f)]})

def makeMapPattern(patterns, tail, span):
    def scope := sumScopes(patterns + [tail])
    object mapPattern:
        to getPatterns():
            return patterns
        to getTail():
            return tail
        to subPrintOn(out, priority):
            printListOn("[", patterns, ", ", "]", out, priorities["pattern"])
            if (tail != null):
                out.print(" | ")
                tail.subPrintOn(out, priorities["pattern"])
    return astWrapper(mapPattern, makeMapPattern, [patterns, tail], span,
        scope, term`MapPattern`, fn f {[transformAll(patterns, f), maybeTransform(tail, f)]})

def makeViaPattern(expr, subpattern, span):
    def scope := expr.getStaticScope() + subpattern.getStaticScope()
    object viaPattern:
        to getExpr():
            return expr
        to getPattern():
            return subpattern
        to subPrintOn(out, priority):
            out.print("via (")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print(") ")
            subpattern.subPrintOn(out, priority)
    return astWrapper(viaPattern, makeViaPattern, [expr, subpattern], span,
        scope, term`ViaPattern`, fn f {[expr.transform(f), subpattern.transform(f)]})

def makeSuchThatPattern(subpattern, expr, span):
    def scope := expr.getStaticScope() + subpattern.getStaticScope()
    object suchThatPattern:
        to getExpr():
            return expr
        to getPattern():
            return subpattern
        to subPrintOn(out, priority):
            subpattern.subPrintOn(out, priority)
            out.print(" ? (")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print(")")
    return astWrapper(suchThatPattern, makeSuchThatPattern, [subpattern, expr], span,
        scope, term`SuchThatPattern`, fn f {[subpattern.transform(f), expr.transform(f)]})

def makeSamePattern(value, direction, span):
    def scope := value.getStaticScope()
    object samePattern:
        to getValue():
            return value
        to getDirection():
            return direction
        to subPrintOn(out, priority):
            if (direction):
                out.print("==")
            else:
                out.print("!=")
            value.subPrintOn(out, priorities["call"])
    return astWrapper(samePattern, makeSamePattern, [value, direction], span,
        scope, term`SamePattern`, fn f {[value.transform(f), direction]})

def makeQuasiText(text, span):
    def scope := emptyScope
    object quasiText:
        to getText():
            return text
        to subPrintOn(out, priority):
            out.print(text)
    return astWrapper(quasiText, makeQuasiText, [text], span,
        scope, term`QuasiText`, fn f {[text]})

def makeQuasiExprHole(expr, span):
    def scope := expr.getStaticScope()
    object quasiExprHole:
        to getExpr():
            return expr
        to subPrintOn(out, priority):
            out.print("$")
            if (priorities["braceExpr"] < priority):
                if (expr._uncall()[0] == makeNounExpr && isIdentifier(expr.getName())):
                    expr.subPrintOn(out, priority)
                    return
            out.print("{")
            expr.subPrintOn(out, priorities["braceExpr"])
            out.print("}")
    return astWrapper(quasiExprHole, makeQuasiExprHole, [expr], span,
        scope, term`QuasiExprHole`, fn f {[expr.transform(f)]})


def makeQuasiPatternHole(pattern, span):
    def scope := pattern.getStaticScope()
    object quasiPatternHole:
        to getPattern():
            return pattern
        to subPrintOn(out, priority):
            out.print("@")
            if (priorities["braceExpr"] < priority):
                if (pattern._uncall()[0] == makeFinalPattern):
                    if (pattern.getGuard() == null && isIdentifier(pattern.getNoun().getName())):
                        pattern.subPrintOn(out, priority)
                        return
            out.print("{")
            pattern.subPrintOn(out, priority)
            out.print("}")
    return astWrapper(quasiPatternHole, makeQuasiPatternHole, [pattern], span,
        scope, term`QuasiPatternHole`, fn f {[pattern.transform(f)]})

def quasiPrint(name, quasis, out, priority):
    if (name != null):
        out.print(name)
    out.print("`")
    for i => q in quasis:
        var p := priorities["prim"]
        if (i + 1 < quasis.size()):
            def next := quasis[i + 1]
            if (next._uncall()[0] == makeQuasiText):
                if (next.getText().size() > 0 && idPart(next.getText()[0])):
                    p := priorities["braceExpr"]
        q.subPrintOn(out, p)
    out.print("`")

def makeQuasiParserExpr(name, quasis, span):
    def scope := if (name == null) {emptyScope} else {makeStaticScope([name + "__quasiParser"], [], [], [], false)} + sumScopes(quasis)
    object quasiParserExpr:
        to getName():
            return name
        to getQuasis():
            return quasis
        to subPrintOn(out, priority):
            quasiPrint(name, quasis, out, priority)
    return astWrapper(quasiParserExpr, makeQuasiParserExpr, [name, quasis], span,
        scope, term`QuasiParserExpr`, fn f {[name, transformAll(quasis, f)]})

def makeQuasiParserPattern(name, quasis, span):
    def scope := if (name == null) {emptyScope} else {makeStaticScope([name + "__quasiParser"], [], [], [], false)} + sumScopes(quasis)
    object quasiParserPattern:
        to getName():
            return name
        to getQuasis():
            return quasis
        to subPrintOn(out, priority):
            quasiPrint(name, quasis, out, priority)
    return astWrapper(quasiParserPattern, makeQuasiParserPattern, [name, quasis], span,
        scope, term`QuasiParserPattern`, fn f {[name, transformAll(quasis, f)]})

object astBuilder:
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
    to "Module"(imports, exports, body, span):
        return makeModule(imports, exports, body, span)
    to MethodCallExpr(rcvr, verb, arglist, span):
        return makeMethodCallExpr(rcvr, verb, arglist, span)
    to FunCallExpr(receiver, args, span):
        return makeFunCallExpr(receiver, args, span)
    to SendExpr(rcvr, verb, arglist, span):
        return makeSendExpr(rcvr, verb, arglist, span)
    to FunSendExpr(receiver, args, span):
        return makeFunSendExpr(receiver, args, span)
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
    to "Method"(docstring, verb, patterns, resultGuard, body, span):
        return makeMethod(docstring, verb, patterns, resultGuard, body, span)
    to "To"(docstring, verb, patterns, resultGuard, body, span):
        return makeTo(docstring, verb, patterns, resultGuard, body, span)
    to Matcher(pattern, body, span):
        return makeMatcher(pattern, body, span)
    to Catcher(pattern, body, span):
        return makeCatcher(pattern, body, span)
    to Script(extend, methods, matchers, span):
        return makeScript(extend, methods, matchers, span)
    to FunctionScript(patterns, resultGuard, body, span):
        return makeFunctionScript(patterns, resultGuard, body, span)
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
    to MapPatternAssoc(key, value, span):
        return makeMapPatternAssoc(key, value, span)
    to MapPatternImport(value, span):
        return makeMapPatternImport(value, span)
    to MapPatternRequired(keyer, span):
        return makeMapPatternRequired(keyer, span)
    to MapPatternDefault(keyer, default, span):
        return makeMapPatternDefault(keyer, default, span)
    to MapPattern(patterns, tail, span):
        return makeMapPattern(patterns, tail, span)
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

def astCodes := [
    "LiteralExpr" => 10,
    "NounExpr" => 11,
    "BindingExpr" => 12,
    "SeqExpr" => 13,
    "MethodCallExpr" => 14,
    "DefExpr" => 15,
    "EscapeExpr" => 16,
    "ObjectExpr" => 17,
    "Script" => 18,
    "Method" => 19,
    "Matcher" => 20,
    "AssignExpr" => 21,
    "FinallyExpr" => 22,
    "CatchExpr" => 23,
    "HideExpr" => 24,
    "IfExpr" => 25,
    "Meta" => 26,
    "FinalPattern" => 27,
    "IgnorePattern" => 28,
    "VarPattern" => 29,
    "ListPattern" => 30,
    "ViaPattern" => 31,
    "BindingPattern" => 32]

def asciiShift(bs):
    def result := [].diverge()
    for c in bs:
        result.push((c + 32) % 256)
    return result.snapshot()

def zze(val):
    if (val < 0):
        return ((val * 2) ^ -1) | 1
    else:
        return val * 2


def dumpVarint(var value, write):
    if (value == 0):
        write(asciiShift([0]))
    else:
        def target := [].diverge()
        while (value > 0):
            def chunk := value & 0x7f
            value >>= 7
            if (value > 0):
                target.push(chunk | 0x80)
            else:
                target.push(chunk)
        write(asciiShift(target))


def dump(item, write):
    if (item == null):
        write(asciiShift([0]))
        return
    switch (item):
        match _ :Int:
            write(asciiShift([6]))
            dumpVarint(zze(item), write)
        match _ :Str:
            write(asciiShift([3]))
            def bs := UTF8.encode(item, throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :Double:
            write(asciiShift([4]))
            write(asciiShift(item.toBytes()))
        match _ :Char:
            write(asciiShift([33]))
            write(asciiShift([3]))
            def bs := UTF8.encode(__makeString.fromChars([item]), throw)
            dumpVarint(bs.size(), write)
            write(bs)
        match _ :List:
            write(asciiShift([7]))
            dumpVarint(item.size(), write)
            for val in item:
                dump(val, write)
        match _:
            def [nodeMaker, _, arglist] := item._uncall()
            def name := item.getNodeName()
            if (name == "MetaContextExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("context", write)
            else if (name == "MetaStateExpr"):
                write(asciiShift([astCodes["Meta"]]))
                dump("getState", write)
            else if (name == "ObjectExpr"):
                write(asciiShift([astCodes[name]]))
                dump(item.getDocstring(), write)
                dump(item.getName(), write)
                dump([item.getAsExpr()] + item.getAuditors(), write)
                dump(item.getScript(), write)
            else:
                write(asciiShift([astCodes[name]]))
                def nodeArgs := arglist.slice(0, arglist.size() - 1)
                for a in nodeArgs:
                    dump(a, write)


[=> astBuilder, => dump]
