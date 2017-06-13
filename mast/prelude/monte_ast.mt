import "boot" =~ [=> DeepFrozenStamp, => TransparentStamp, => KernelAstStamp]
import "ast_printer" =~ [=> printerActions]
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

def sumScopes(nodes) as DeepFrozenStamp:
    var result := emptyScope
    for node in (nodes):
        if (node != null):
            result += node.getStaticScope()
    return result

def scopeMaybe(optNode) as DeepFrozenStamp:
    if (optNode == null):
        return emptyScope
    return optNode.getStaticScope()

def all(iterable, pred) as DeepFrozenStamp:
    for item in (iterable):
        if (!pred(item)):
            return false
    return true

def maybeTransform(node, f) as DeepFrozenStamp:
    if (node == null):
        return null
    return node.transform(f)

def transformAll(nodes, f) as DeepFrozenStamp:
    def results := [].diverge()
    for n in (nodes):
        results.push(n.transform(f))
    return results.snapshot()

def astStamp.audit(_audition) :Bool as DeepFrozenStamp:
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
        def nodeGuard.coerce(specimen, ej) as DeepFrozenStamp:
            def sp := Ast.coerce(specimen, ej)
            if (nodeNames.contains(sp.getNodeName())):
                return sp
            throw.eject(ej, "m`" + M.toString(sp) + "`'s type is not one of " + M.toString(nodeNames))

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
            astNode.subPrintOn(out, 0)
        to subPrintOn(out, priority):
            if (printerActions.contains(nodeName)):
                printerActions[nodeName](astNode, out, priority)
            else:
                node.subPrintOn(out, priority)
# 'value' is unguarded because the optimized uses LiteralExprs for non-literal
# constants.
def makeLiteralExpr(value, span) as DeepFrozenStamp:
    def literalExpr.getValue():
        return value
    return astWrapper(literalExpr, makeLiteralExpr, [value], span,
        &emptyScope, "LiteralExpr", fn _f {[value]})

def makeNounExpr(name :Str, span) as DeepFrozenStamp:
    def nounExpr.getName():
        return name

    # XXX why do we do it this way? Why can't we just put the name directly
    # into `makeStaticScope`?
    def scope
    def node := astWrapper(nounExpr, makeNounExpr, [name], span,
         &scope, "NounExpr", fn _f {[name]})
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
        to subPrintOn(out, _priority):
            out.print("$<temp ")
            out.print(namePrefix)
            out.print(">")
    bind scope := makeStaticScope([tempNounExpr.withoutSpan()], [], [], [], false)
    return tempNounExpr

def makeSlotExpr(noun :Noun, span) as DeepFrozenStamp:
    def scope := noun.getStaticScope()
    def slotExpr.getNoun():
        return noun

    return astWrapper(slotExpr, makeSlotExpr, [noun], span,
        &scope, "SlotExpr", fn f {[noun.transform(f)]})

def makeMetaContextExpr(span) as DeepFrozenStamp:
    def metaContextExpr.subPrintOn(out, _priority):
        out.print("meta.context()")

    return astWrapper(metaContextExpr, makeMetaContextExpr, [], span,
        &emptyScope, "MetaContextExpr", fn _f {[]})

def makeMetaStateExpr(span) as DeepFrozenStamp:
    def scope := makeStaticScope([], [], [], [], true)
    def metaStateExpr.subPrintOn(out, _priority):
        out.print("meta.getState()")

    return astWrapper(metaStateExpr, makeMetaStateExpr, [], span,
        &scope, "MetaStateExpr", fn _f {[]})

def makeBindingExpr(noun :Noun, span) as DeepFrozenStamp:
    def scope := noun.getStaticScope()
    def bindingExpr.getNoun():
        return noun

    return astWrapper(bindingExpr, makeBindingExpr, [noun], span,
        &scope, "BindingExpr", fn f {[noun.transform(f)]})

def makeSeqExpr(exprs :List[Expr], span) as DeepFrozenStamp:
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
    def &scope := makeLazySlot(fn {sumScopes(fixedExprs)})
    def seqExpr.getExprs():
        return fixedExprs

    return astWrapper(seqExpr, makeSeqExpr, [fixedExprs], span, &scope,
                      "SeqExpr", fn f {[transformAll(fixedExprs, f)]})

def makeModule(importsList, exportsList, body, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        def interiorScope := (sumScopes([for [_n, p] in (importsList) p]) +
                              body.getStaticScope())
        def exportListScope := sumScopes(exportsList)
        def exportScope := makeStaticScope(
            exportListScope.getNamesRead() - interiorScope.outNames(),
            [], [for e in (exportsList)
                 ? (interiorScope.outNames().contains(e.getName()))
                 e.getName()], [], false)
        interiorScope.hide() + exportScope})
    object module:
        to getImports():
            return importsList
        to getExports():
            return exportsList
        to getBody():
            return body
    return astWrapper(module, makeModule, [importsList, exportsList, body], span,
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
    return astWrapper(namedArg, makeNamedArg, [k, v], span, &scope, "NamedArg",
                      fn f {[k.transform(f), v.transform(f)]})

def makeNamedArgExport(v :Expr, span) as DeepFrozenStamp:
    def scope := v.getStaticScope()
    def namedArgExport.getValue():
        return v

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
    return astWrapper(funSendExpr, makeFunSendExpr, [receiver, args, namedArgs], span,
        &scope, "FunSendExpr", fn f {[receiver.transform(f), transformAll(args, f), transformAll(namedArgs, f)]})

def makeGetExpr(receiver :Expr, indices :List[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(indices + [receiver])})
    object getExpr:
        to getReceiver():
            return receiver
        to getIndices():
            return indices

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
        to getPriorityName():
            return operatorsToNamePrio[op][1]
        to getRight():
            return right
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
    return astWrapper(curryExpr, makeCurryExpr, [receiver, verb, isSend], span,
        &scope, "CurryExpr", fn f {[receiver.transform(f), verb, isSend]})

def makeExitExpr(name :Str, value :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {scopeMaybe(value)})
    object exitExpr:
        to getName():
            return name
        to getValue():
            return value
    return astWrapper(exitExpr, makeExitExpr, [name, value], span,
        &scope, "ExitExpr", fn f {[name, maybeTransform(value, f)]})

def makeForwardExpr(patt :Ast["FinalPattern"], span) as DeepFrozenStamp:
    def scope := patt.getStaticScope()
    def forwardExpr.getNoun():
        return patt.getNoun()

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
        to getGuard():
            return guard
        to refutable() :Bool:
            return guard != null

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
        to getVerb():
            return verb
        to getLvalue():
            return lvalue
        to getRvalues():
            return rvalues
    return astWrapper(verbAssignExpr, makeVerbAssignExpr, [verb, lvalue, rvalues], span,
        &scope, "VerbAssignExpr", fn f {[verb, lvalue.transform(f), transformAll(rvalues, f)]})


def makeAugAssignExpr(op :Str, lvalue :Expr, rvalue :Expr, span) as DeepFrozenStamp:
    def lname := lvalue.getNodeName()
    def lscope := if (lname == "NounExpr" || lname == "TempNounExpr") {
        # We both read and write to the name on the LHS.
        makeStaticScope([lvalue.getName()], [lvalue.getName()], [], [], false)
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

    return astWrapper(::"method", makeMethod, [docstring, verb, patterns, namedPatts, resultGuard, body], span,
        &scope, "Method", fn f {[docstring, verb, transformAll(patterns, f), transformAll(namedPatts, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeTo(docstring :NullOk[Str], verb :Str, patterns :List[Pattern],
           namedPatts :List[Ast["NamedParam", "NamedParamImport"]], resultGuard :NullOk[Expr],
           body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        def ps := sumScopes(patterns + namedPatts)
        def returnScope := makeStaticScope([], [], ["__return"], [], false)
        def b := sumScopes([resultGuard, body])
        (ps + returnScope + b).hide()
    })
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
    return astWrapper(catcher, makeCatcher, [pattern, body], span,
        &scope, "Catcher", fn f {[pattern.transform(f), body.transform(f)]})

def makeScript(extend :NullOk[Expr], methods :List[Ast["Method", "To"]],
               matchers :List[Ast["Matcher"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        def ss := sumScopes(methods + matchers)
        if (extend == null) {
            ss
        } else {
            extend.getStaticScope() + makeStaticScope([], [], ["super"], [], false) + ss
        }})
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

            for meth in (methods):
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

    return astWrapper(script, makeScript, [extend, methods, matchers], span,
        &scope, "Script", fn f {[maybeTransform(extend, f), transformAll(methods, f), transformAll(matchers, f)]})

def makeFunctionScript(verb :Str, patterns :List[Pattern],
                       namedPatterns :List[Ast["NamedParam", "NamedParamImport"]],
                       resultGuard :NullOk[Expr], body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        def ps := sumScopes(patterns + namedPatterns)
        def returnScope := makeStaticScope([], [], ["__return"], [], false)
        def b := sumScopes([resultGuard, body])
        (ps + returnScope + b).hide()
    })
    object functionScript:
        to getVerb():
            return verb
        to getPatterns():
            return patterns
        to getNamedPatterns():
            return namedPatterns
        to getResultGuard():
            return resultGuard
        to getBody():
            return body
    return astWrapper(functionScript, makeFunctionScript, [patterns, namedPatterns, resultGuard, body], span,
        &scope, "FunctionScript", fn f {[verb, transformAll(patterns, f), transformAll(namedPatterns, f), maybeTransform(resultGuard, f), body.transform(f)]})

def makeFunctionExpr(patterns :List[Pattern],
                     namedPatterns :List[Ast["NamedParam", "NamedParamImport"]],
                     body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {(sumScopes(patterns + namedPatterns) +
                                    body.getStaticScope()).hide()})
    object functionExpr:
        to getPatterns():
            return patterns

        to getNamedPatterns():
            return namedPatterns

        to getBody():
            return body

    return astWrapper(functionExpr, makeFunctionExpr,
                      [patterns, namedPatterns, body], span, &scope,
                      "FunctionExpr", fn f {[transformAll(patterns, f),
                      transformAll(namedPatterns, f), body.transform(f)]})

def makeListExpr(items :List[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(items)})
    def listExpr.getItems():
        return items

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
    return astWrapper(mapExprAssoc, makeMapExprAssoc, [key, value], span,
        &scope, "MapExprAssoc", fn f {[key.transform(f), value.transform(f)]})

def makeMapExprExport(value :Ast["NounExpr", "BindingExpr", "SlotExpr", "TempNounExpr"], span) as DeepFrozenStamp:
    def scope := value.getStaticScope()
    def mapExprExport.getValue():
        return value

    return astWrapper(mapExprExport, makeMapExprExport, [value], span,
        &scope, "MapExprExport", fn f {[value.transform(f)]})

def makeMapExpr(pairs :List[Ast["MapExprAssoc", "MapExprExport"]] ? (pairs.size() > 0), span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(pairs)})
    def mapExpr.getPairs():
        return pairs

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
    return astWrapper(mapComprehensionExpr, makeMapComprehensionExpr, [iterable, filter, key, value, bodyk, bodyv], span,
        &scope, "MapComprehensionExpr", fn f {[iterable.transform(f), maybeTransform(filter, f), maybeTransform(key, f), value.transform(f), bodyk.transform(f), bodyv.transform(f)]})

def makeForExpr(iterable :Expr, key :NullOk[Pattern], value :Pattern,
                body :Expr, catchPattern :NullOk[Pattern],
                catchBody :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        ((makeStaticScope([], [], ["__break"], [], false) +
          sumScopes([iterable, key, value]) +
          makeStaticScope([], [], ["__continue"], [], false) +
          body.getStaticScope()).hide() +
         scopeMaybe(catchPattern) + scopeMaybe(catchBody)).hide()})
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

    return astWrapper(ObjectExpr, makeObjectExpr, [docstring, name, asExpr, auditors, script], span,
        &scope, "ObjectExpr", fn f {[docstring, name.transform(f), maybeTransform(asExpr, f), transformAll(auditors, f), script.transform(f)]})

def makeParamDesc(name :Str, guard :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {scopeMaybe(guard)})
    object paramDesc:
        to getName():
            return name
        to getGuard():
            return guard
    return astWrapper(paramDesc, makeParamDesc, [name, guard], span,
        &scope, "ParamDesc", fn f {[name, maybeTransform(guard, f)]})

def makeMessageDesc(docstring :NullOk[Str], verb :Str,
                    params :List[Ast["ParamDesc"]],
                    namedParams :List[Ast["ParamDesc"]],
                    resultGuard :NullOk[Expr],
                    span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {sumScopes(params + [resultGuard])})
    object messageDesc:
        to getDocstring():
            return docstring
        to getVerb():
            return verb
        to getParams():
            return params
        to getNamedParams():
            return namedParams
        to getResultGuard():
            return resultGuard
    return astWrapper(messageDesc, makeMessageDesc, [docstring, verb, params, namedParams, resultGuard], span,
        &scope, "MessageDesc", fn f {[docstring, verb, transformAll(params, f), transformAll(namedParams, f), maybeTransform(resultGuard, f)]})


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
    return astWrapper(ifExpr, makeIfExpr, [test, consq, alt], span,
        &scope, "IfExpr", fn f {[test.transform(f), consq.transform(f), maybeTransform(alt, f)]})

def makeWhileExpr(test :Expr, body :Expr, catcher :NullOk[Ast["Catcher"]], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        ((makeStaticScope([], [], ["__break"], [], false) +
        test.getStaticScope() +
         makeStaticScope([], [], ["__continue"], [], false) +
         body.getStaticScope()).hide() +
        scopeMaybe(catcher)).hide()})
    object whileExpr:
        to getTest():
            return test
        to getBody():
            return body
        to getCatcher():
            return catcher
    return astWrapper(whileExpr, makeWhileExpr, [test, body, catcher], span,
        &scope, "WhileExpr", fn f {[test.transform(f), body.transform(f), maybeTransform(catcher, f)]})

def makeHideExpr(body :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {body.getStaticScope().hide()})
    def hideExpr.getBody():
        return body

    return astWrapper(hideExpr, makeHideExpr, [body], span,
        &scope, "HideExpr", fn f {[body.transform(f)]})

def makeValueHoleExpr(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object valueHoleExpr implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return valueHoleExpr
    return astWrapper(valueHoleExpr, makeValueHoleExpr, [index], span,
        &scope, "ValueHoleExpr", fn _f {[index]})

def makePatternHoleExpr(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object patternHoleExpr implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return patternHoleExpr
    return astWrapper(patternHoleExpr, makePatternHoleExpr, [index], span,
        &scope, "PatternHoleExpr", fn _f {[index]})

def makeValueHolePattern(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object valueHolePattern implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return valueHolePattern
    return astWrapper(valueHolePattern, makeValueHolePattern, [index], span,
        &scope, "ValueHolePattern", fn _f {[index]})

def makePatternHolePattern(index :Int, span) as DeepFrozenStamp:
    def scope := emptyScope
    object patternHolePattern implements DeepFrozenStamp:
        to getIndex():
            return index
        to getName():
            return patternHolePattern
    return astWrapper(patternHolePattern, makePatternHolePattern, [index], span,
        &scope, "PatternHolePattern", fn _f {[index]})

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

    return astWrapper(slotPattern, makeSlotPattern, [noun, guard], span,
        &scope, "SlotPattern", fn f {[noun.transform(f), maybeTransform(guard, f)]})

def makeBindingPattern(noun :Noun, span) as DeepFrozenStamp:
    def scope := makeStaticScope([], [], [], [noun.getName()], false)
    object bindingPattern:
        to getNoun():
            return noun

        to refutable() :Bool:
            return false

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
    return astWrapper(mapPatternAssoc, makeMapPatternAssoc, [key, value, default], span,
        &scope, "MapPatternAssoc", fn f {[key.transform(f), value.transform(f), maybeTransform(default, f)]})

def makeMapPatternImport(pattern :NamePattern, default :NullOk[Expr], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {pattern.getStaticScope() + scopeMaybe(default)})
    object mapPatternImport:
        to getPattern():
            return pattern
        to getDefault():
            return default
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

    return astWrapper(viaPattern, makeViaPattern, [expr, subpattern], span,
        &scope, "ViaPattern", fn f {[expr.transform(f), subpattern.transform(f)]})

def makeSuchThatPattern(subpattern :Pattern, expr :Expr, span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {subpattern.getStaticScope() +
                                   expr.getStaticScope()})
    object suchThatPattern:
        to getExpr():
            return expr
        to getPattern():
            return subpattern

        to refutable() :Bool:
            return true

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

    return astWrapper(samePattern, makeSamePattern, [value, direction], span,
        &scope, "SamePattern", fn f {[value.transform(f), direction]})

def makeQuasiText(text :Str, span) as DeepFrozenStamp:
    def scope := emptyScope
    def quasiText.getText():
            return text

    return astWrapper(quasiText, makeQuasiText, [text], span,
        &scope, "QuasiText", fn _f {[text]})

def makeQuasiExprHole(expr :Expr, span) as DeepFrozenStamp:
    def scope := expr.getStaticScope()
    def quasiExprHole.getExpr():
        return expr

    return astWrapper(quasiExprHole, makeQuasiExprHole, [expr], span,
        &scope, "QuasiExprHole", fn f {[expr.transform(f)]})


def makeQuasiPatternHole(pattern :Pattern, span) as DeepFrozenStamp:
    def scope := pattern.getStaticScope()
    def quasiPatternHole.getPattern():
        return pattern

    return astWrapper(quasiPatternHole, makeQuasiPatternHole, [pattern], span,
        &scope, "QuasiPatternHole", fn f {[pattern.transform(f)]})

def QuasiPiece :DeepFrozen := Ast["QuasiText", "QuasiExprHole",
                                  "QuasiPatternHole"]

def makeQuasiParserExpr(name :NullOk[Str], quasis :List[QuasiPiece], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        if (name == null) {emptyScope} else {
            makeStaticScope([name + "``"], [], [], [], false)
        } + sumScopes(quasis)
    })
    object quasiParserExpr:
        to getName():
            return name
        to getQuasis():
            return quasis
    return astWrapper(quasiParserExpr, makeQuasiParserExpr, [name, quasis], span,
        &scope, "QuasiParserExpr", fn f {[name, transformAll(quasis, f)]})

def makeQuasiParserPattern(name :NullOk[Str], quasis :List[QuasiPiece], span) as DeepFrozenStamp:
    def &scope := makeLazySlot(fn {
        if (name == null) {emptyScope} else {
            makeStaticScope([name + "``"], [], [], [], false)
        } + sumScopes(quasis)
    })
    object quasiParserPattern:
        to getName():
            return name
        to getQuasis():
            return quasis

        to refutable() :Bool:
            return true

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
    to FunctionScript(verb, patterns, namedPatterns, resultGuard, body, span):
        return makeFunctionScript(verb, patterns, namedPatterns, resultGuard, body, span)
    to FunctionExpr(patterns, namedPatterns, body, span):
        return makeFunctionExpr(patterns, namedPatterns, body, span)
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
    to MessageDesc(docstring, verb, params, namedParams, resultGuard, span):
        return makeMessageDesc(docstring, verb, params, namedParams, resultGuard, span)
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
