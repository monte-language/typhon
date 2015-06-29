object Really as DeepFrozenStamp:
    "Non-coercing guard wrapper."
    to get(guard):
        return object reallyGuard:
            to coerce(specimen, ej):
                def coerced := guard.coerce(specimen, ej)
                if (coerced != specimen):
                  throw.eject(ej, M.toQuote(coerced) + " must be same as original specimen " + M.toQuote(specimen))
                return coerced

def FinalSlot := _makeFinalSlot.asType()

object SubrangeGuard as DeepFrozenStamp:
    to get(superguard):
        return object SpecializedSubrangeGuard implements Selfless, TransparentStamp:
            to _uncall():
                return [SubrangeGuard, "get", [superguard]]
            to audit(audition):
                def expr := audition.getObjectExpr()
                def meth := escape e {
                    expr.getScript().getMethodNamed("coerce", e)
                } catch _ {
                    throw(audition.getFQName() + " has no coerce/2 method")
                }
                if ((def resultGuardExpr := meth.getResultGuard()) != null && resultGuardExpr.getNodeName() == "NounExpr"):
                    def resultGuardSlotGuard := audition.getGuard(resultGuardExpr.getName())
                    if (resultGuardSlotGuard =~ via (FinalSlot.extractGuard) via (Same.extractValue) resultGuard):
                        if (resultGuard == superguard || superguard._respondsTo("supersetOf", 1) && superguard.supersetOf(resultGuard)):
                            return true
                        throw(audition.getFQN() + " does not have a result guard implying " + M.toQuote(superguard) + ", but " + M.toQuote(resultGuard))
                    throw(audition.getFQN() + " does not have a determinable result guard, but <& " + resultGuardExpr.getName() + "> :" + M.toQuote(resultGuardSlotGuard))

            to coerce(specimen, ej):
                if (__auditedBy(SpecializedSubrangeGuard, specimen)):
                    return specimen
                else if (__auditedBy(SpecializedSubrangeGuard,
                                    def c := specimen._conformTo(SpecializedSubrangeGuard))):
                    return c
                else:
                    throw.eject(ej, ["Not approved as a subrange of " + M.toQuote(superguard)])

            to _printOn(out):
                out.quote(SubrangeGuard)
                out.print("[")
                out.quote(superguard)
                out.print("]")


def dataGuards := [Bool, Char, Double, Int, Str]
object DeepFrozen implements DeepFrozenStamp:

    to audit(audition):
        #requireAudit(audition, throw)
        audition.ask(DeepFrozenStamp)
        return false

    to isDeepFrozen(specimen):
        return false

    to coerce(specimen, ej):
        return specimen

    to supersetOf(guard):
        if (dataGuards.contains(guard)):
            return true
        # XXX orderedspace version of data guards
        return false

    to _printOn(out):
        out.print("DeepFrozen")

    #to optionally():
    #to eventually():

[=> SubrangeGuard, => DeepFrozen]
