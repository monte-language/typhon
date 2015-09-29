def FinalSlot := _makeFinalSlot.asType()

object SubrangeGuard as DeepFrozenStamp:
    to get(superguard):
        return object SpecializedSubrangeGuard implements Selfless, TransparentStamp:
            to _uncall():
                return [SubrangeGuard, "get", [superguard], [].asMap()]
            to audit(audition):
                def expr := audition.getObjectExpr()
                def meth := escape e {
                    expr.getScript().getMethodNamed("coerce", e)
                } catch _ {
                    throw(audition.getFQN() + " has no coerce/2 method")
                }
                if ((def resultGuardExpr := meth.getResultGuard()) != null && resultGuardExpr.getNodeName() == "NounExpr"):
                    def resultGuardSlotGuard := audition.getGuard(resultGuardExpr.getName())
                    if (resultGuardSlotGuard =~ via (FinalSlot.extractGuard) via (Same.extractValue) resultGuard):
                        if (resultGuard == superguard || superguard._respondsTo("supersetOf", 1) && superguard.supersetOf(resultGuard)):
                            return true
                        throw(audition.getFQN() + " does not have a result guard implying " + M.toQuote(superguard) + ", but " + M.toQuote(resultGuard))
                    throw(audition.getFQN() + " does not have a determinable result guard, but <& " + M.toString(resultGuardExpr) + "> :" + M.toQuote(resultGuardSlotGuard))

            to coerce(specimen, ej):
                if (__auditedBy(SpecializedSubrangeGuard, specimen)):
                    return specimen
                else if (__auditedBy(SpecializedSubrangeGuard,
                                    def c := specimen._conformTo(SpecializedSubrangeGuard))):
                    return c
                else:
                    throw.eject(ej, ["Not approved as a subrange of " + M.toQuote(superguard)])

            to passes(specimen):
                escape notOk:
                    SpecializedSubrangeGuard.coerce(specimen, notOk)
                    return true
                return false

            to _printOn(out):
                out.quote(SubrangeGuard)
                out.print("[")
                out.quote(superguard)
                out.print("]")


def checkDeepFrozen(specimen, sofar, ej, root) as DeepFrozenStamp:
    def key := __equalizer.makeTraversalKey(specimen)
    if (sofar.contains(key)):
        # Oops, been here already.
        return
    def sofarther := sofar.with(key)
    if (__auditedBy(DeepFrozenStamp, specimen)):
        return
    else if (Ref.isBroken(specimen)):
        # Broken refs are DF if their problem is DF.
        checkDeepFrozen(Ref.optProblem(specimen), sofarther, ej, root)
        return
    else if (__auditedBy(Selfless, specimen) &&
             __auditedBy(TransparentStamp, specimen)):
        def [maker, verb, args :List, namedArgs :Map] := specimen._uncall()
        checkDeepFrozen(maker, sofarther, ej, root)
        checkDeepFrozen(verb, sofarther, ej, root)
        for arg in args:
            checkDeepFrozen(arg, sofarther, ej, root)
        for argkey => argval in namedArgs:
            checkDeepFrozen(argkey, sofarther, ej, root)
            checkDeepFrozen(argval, sofarther, ej, root)
    else:
        if (__equalizer.sameYet(specimen, root)):
            throw.eject(ej, M.toQuote(root) + " is not DeepFrozen")
        else:
            throw.eject(ej, M.toQuote(root) + " is not DeepFrozen because " +
                        M.toQuote(specimen) + " is not")


def auditDeepFrozen
def dataGuards := [Bool, Char, Double, Int, Str, Void]
object DeepFrozen implements DeepFrozenStamp:
    "Transitive immutability.

     As an auditor, this object proves that a specimen is transitively
     immutable; that is, that a specimen is immutable and that all of its
     referents are also transitively immutable."

    to audit(audition):
        auditDeepFrozen(audition, throw)
        audition.ask(DeepFrozenStamp)
        return false

    to coerce(specimen, ej):
        checkDeepFrozen(specimen, [].asSet(), ej, specimen)
        return specimen

    to supersetOf(guard):
        if (guard == DeepFrozen):
            return true
        if (guard == DeepFrozenStamp):
            return true
        if (dataGuards.contains(guard)):
            return true
        # XXX orderedspace version of data guards
        if (guard =~ via (Same.extractValue) sameVal):
            escape notOk:
                checkDeepFrozen(sameVal, [].asSet(), notOk, sameVal)
                return true
            return false

        # Extractable guards in the prelude.
        for superGuard in [FinalSlot, List, NullOk, Set]:
            if (guard =~ via (superGuard.extractGuard) subGuard):
                return DeepFrozen.supersetOf(subGuard)

        # Map is special since it has two subguards.
        if (guard =~ via (Map.extractGuards) [keyGuard, valueGuard]):
            return (DeepFrozen.supersetOf(keyGuard) &&
                    DeepFrozen.supersetOf(valueGuard))

        if (SubrangeGuard[DeepFrozen].passes(guard)):
            return true

        # Any is also special since it has many subguards.
        if (guard =~ via (Any.extractGuards) subGuards):
            for g in subGuards:
                if (!DeepFrozen.supersetOf(g)):
                    return false
            return true
        return false

    to _printOn(out):
        out.print("DeepFrozen")

    #to optionally():
    #to eventually():

bind auditDeepFrozen(audition, fail) as DeepFrozenStamp:
    def objectExpr := audition.getObjectExpr()
    def patternSS := objectExpr.getName().getStaticScope()
    def objNouns := patternSS.getDefNames().asList()
    def objName := if (objNouns.size() > 0 && objNouns[0] != null) { objNouns[0].getName()} else {null}
    def closureNames := [].diverge()
    for noun in objectExpr.getScript().getStaticScope().namesUsed():
        if (noun.getName() != objName):
            closureNames.push(noun.getName())
    def errors := [].diverge()
    for name in closureNames:
        if (patternSS.getVarNames().contains(name)):
            errors.push(M.toQuote(name) + " in the definition of " +
                        audition.getFQN() + " is a variable pattern " +
                        "and therefore not DeepFrozen")
        else:
            def guard := audition.getGuard(name)
            if (!DeepFrozen.supersetOf(guard)):
                errors.push(M.toQuote(name) + " in the lexical scope of " +
                            audition.getFQN() + " does not have a guard " +
                            "implying DeepFrozen, but " + M.toQuote(guard))
    if (errors.size() > 0):
        throw.eject(fail, ";\n".join(errors))

[=> SubrangeGuard, => DeepFrozen]
