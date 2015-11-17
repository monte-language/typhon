"
Transparent guard and auditor factory.
"
object Transparent as DeepFrozenStamp:
    "Objects that Transparent admits have reliable ._uncall() methods, in the sense
    that they correctly identify their maker and their entire state, and that
    invoking the maker with the given args will produce an object with the same
    state. Objects that are both Selfless and Transparent are compared for sameness
    by comparing their uncalls."
    to coerce(specimen, ej):
        if (__auditedBy(TransparentStamp, specimen)):
            return specimen
        throw.eject(ej, M.toQuote(specimen) + " is not Transparent")

    to makeAuditorKit():
        "Creates the tools needed to implement a Transparent object:
         a maker auditor, a value auditor binding, and a serializer binding.
         Example usage:

             def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
             def makeFoo(...) as DeepFrozen implements makerAuditor:
                 ...
                 return object foo implements Selfless, valueAuditor:
                     ...
                     to _uncall():
                         return serializer(makeFoo, [...])
        "
        var makerAuditorUsed := false

        def FinalSlot :DeepFrozen := _makeFinalSlot.asType()
        def Ast :DeepFrozen := astBuilder.getAstGuard()
        def _valueAuditor
        def _serializer
        def positionalArgNames
        def namedArgNames
        object makerAuditor implements DeepFrozenStamp:
            to audit(audition):
                if (Ref.isResolved(positionalArgNames)):
                    throw("Maker auditor has already been used")
                def objectExpr := audition.getObjectExpr()
                def patternSS := objectExpr.getName().getStaticScope()
                def objNouns := patternSS.getDefNames().asList()
                def objName := if (objNouns.size() > 0 && objNouns[0] != null) {objNouns[0]} else {null}
                def closureNames := [].diverge()
                for name in objectExpr.getScript().getStaticScope().namesUsed():
                    if (name != objName):
                        closureNames.push(name)
                var valueAuditorNoun := null
                var serializerNoun := null
                for n in closureNames:
                    def g := audition.getGuard(n)
                    if (g =~ via (FinalSlot.extractGuard) via (Same.extractValue) ==_valueAuditor):
                        valueAuditorNoun := n
                    else if (g =~ via (FinalSlot.extractGuard) via (Same.extractValue) ==_serializer):
                        serializerNoun := astBuilder.NounExpr(n, null)
                    else if (!DeepFrozen.supersetOf(g)):
                        throw("non-DeepFrozen binding &&" + n + " :" + M.toString(g) + " not allowed in Transparent maker")

                if (valueAuditorNoun == null):
                    throw("Value auditor not used in body of maker")
                if (serializerNoun == null):
                    throw("Serializer not used in value's uncall method")

                def meth := escape e {
                    objectExpr.getScript().getMethodNamed("run", e)
                } catch _ {
                    throw(audition.getFQN() + " has no \"run\" method")
                }
                def params := meth.getPatterns()
                def pnames := [].diverge()
                def npnames := [].asMap().diverge()
                for p in params:
                    if (p.getNodeName() != "FinalPattern" || p.getGuard() != null):
                        throw("Makers of Transparent objects currently must " +
                              "have only unguarded FinalSlot patterns in " +
                              "their signature, not " + M.toQuote(p))
                    pnames.push(p.getNoun().getName())
                def namedParams := meth.getNamedPatterns()
                for np in namedParams:
                    def p := np.getPattern()
                    if (p.getNodeName() != "FinalPattern" || p.getGuard() != null):
                        throw("Makers of Transparent objects currently must " +
                              "have only unguarded FinalSlot patterns in  " +
                              "their signature, not " + M.toQuote(np))
                    def k := np.getKey()
                    if (k.getNodeName() == "LiteralExpr"):
                        npnames[k.getValue()] := p.getNoun()
                    else if (k.getNodeName() == "NounExpr" &&
                             DeepFrozen.supersetOf(audition.getGuard(k.getName()))):
                        npnames[k] := p.getNoun()
                    else:
                        throw("Makers of Transparent objects must have only " +
                          "literal or DeepFrozen names as keys, not " +
                          M.toQuote(k))
                bind positionalArgNames  := pnames.snapshot()
                bind namedArgNames := npnames.snapshot()
                def body := meth.getBody()
                var targetExpr := body
                if (targetExpr =~ m`escape __return { @ebody }`):
                    def exprs := if (ebody.getNodeName() == "SeqExpr") {
                            ebody.getExprs()} else {[ebody]}
                    var returnFound := false
                    for ex in exprs:
                        if (ex.getStaticScope().getNamesRead().contains("__return")):
                            if (ex.getNodeName() == "MethodCallExpr" && ex.getReceiver() =~ m`__return`):
                                returnFound := true
                                targetExpr := ex
                            else:
                                throw("return must be done at top level of maker body")
                    if (!returnFound):
                        throw("Maker body doesn't use \"return\"")

                    if (targetExpr =~ m`__return.run(@obj)` && obj.getNodeName() == "ObjectExpr"):
                        targetExpr := obj
                    else:
                        throw("Maker body must end with \"return object ...\"")
                else:
                    if (targetExpr.getNodeName() == "SeqExpr"):
                        targetExpr := targetExpr.getExprs().last()
                    if (targetExpr.getNodeName() != "ObjectExpr"):
                            throw("Maker body must have \"object ...\" as final expr")
                var usesValueAuditor := false
                for audPatt in [targetExpr.getAsExpr()] + targetExpr.getAuditors():
                    if (audPatt != null && audPatt.getNodeName() == "NounExpr" &&
                        audPatt.getName() == valueAuditorNoun):
                        usesValueAuditor := true
                if (!usesValueAuditor):
                    throw("Object returned does not implement this " +
                          "maker's value auditor")
                def uncallMethod := escape e {
                        targetExpr.getScript().getMethodNamed("_uncall", e)
                } catch _ {
                    throw("Value object has no ._uncall() method")
                }
                if (uncallMethod.getPatterns().size() != 0 ||
                    uncallMethod.getNamedPatterns().size() != 0):
                    throw("Value object's _uncall method must not take any parameters")
                def makerNoun := objectExpr.getName().getNoun()
                var uncallExpr := uncallMethod.getBody()
                if (uncallExpr =~ m`escape __return { @{var uncallBody} }`):
                    if (uncallBody.getNodeName() == "SeqExpr"):
                        uncallBody := uncallBody.getExprs()[0]
                    if (uncallBody =~ m`__return.run(@uc)`):
                        uncallExpr := uc
                    else:
                        throw("Value object's uncall method may not " +
                              "contain anything other than a single " +
                              " return statement (found: " + M.toQuote(uncallBody) +
                              ")")
                else:
                    if (uncallExpr.getNodeName() == "SeqExpr"):
                        def exprs := uncallExpr.getExprs().size()
                        if (exprs != 1):
                            throw("Value object's uncall method may not " +
                                  "contain anything other than a single " +
                                  " expression (found: " + M.toQuote(exprs) +
                                  ")")
                        uncallExpr := exprs.last()
                def collectSerializerArgs(args, namedArgs):
                    if (args.getNodeName() == "MethodCallExpr" &&
                        args.getReceiver() =~ m`__makeList` &&
                        args.getVerb() == "run"):
                        def paNames := [for a in (args.getArgs())
                                        if (a.getNodeName() == "NounExpr")
                                        a.getName()]
                        def unwrapKey(kn, ej):
                            if (kn.getNodeName() == "NounExpr"):
                                return (kn :Ast)
                            else if (kn.getNodeName() == "LiteralExpr"):
                                return kn.getValue()
                            else:
                                ej(`Serializer argument names must be literals or nouns, not $kn`)
                        def naNames := if (namedArgs != null &&
                                namedArgs.getNodeName() == "MethodCallExpr" &&
                                namedArgs.getReceiver() =~ m`__makeMap` &&
                                namedArgs.getVerb() == "fromPairs") {
                                    def [pairListExpr] := namedArgs.getArgs()
                                    if (pairListExpr.getNodeName() != "MethodCallExpr" ||
                                        pairListExpr.getReceiver() !~ m`__makeList` ||
                                        pairListExpr.getVerb() != "run") {
                                        throw(`Named args map must be a literal, not $pairListExpr`)
                                    }
                                    [for m`__makeList.run(@{via (unwrapKey) k}, @v)` in (pairListExpr.getArgs())
                                     if (v.getNodeName() == "NounExpr")
                                     k => (v :Ast)]
                                } else { [].asMap() }
                        if (paNames == positionalArgNames &&
                            naNames.size() == namedArgNames.size()):
                            for k => v in naNames:
                                if (!namedArgNames.contains(k) ||
                                    namedArgNames[k].getName() != v.getName()):
                                    return false
                            return true
                    return false

                if (uncallExpr =~ m`$serializerNoun.run($makerNoun, @serializerArgs)` &&
                    collectSerializerArgs(serializerArgs, null)):
                        return true
                if (uncallExpr =~ m`$serializerNoun.run($makerNoun, @serializerArgs, @namedSerializerArgs)` &&
                    collectSerializerArgs(serializerArgs, namedSerializerArgs)):
                        return true
                throw("Value uncall method body must be: " +
                      M.toString(serializerNoun) + "(" +
                      M.toString(makerNoun) + ", [" + ", ".join([for n in (positionalArgNames) M.toString(n)]) + "]" +
                      if (namedArgNames.size() > 0) { ", " + M.toString(namedArgNames)
                      } else { "" } + ")")

        bind _valueAuditor implements DeepFrozenStamp:
            to audit(audition):
                audition.ask(TransparentStamp)
                return true

        bind _serializer implements DeepFrozenStamp:
            to run(maker, args :List, namedArgs :Map):
                return [maker, "run", args, namedArgs]
            match [=="run", [maker, args], _]:
                [maker, args, [].asMap()]

        def valueAuditor :Same[_valueAuditor] := _valueAuditor
        def serializer :Same[_serializer] := _serializer
        return [makerAuditor, &&valueAuditor, &&serializer]
[=> Transparent]
