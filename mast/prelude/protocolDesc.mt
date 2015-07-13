def __makeParamDesc(name :Str, guard :DeepFrozen) as DeepFrozen:
    return object paramDesc as DeepFrozen:
        pass


def __makeMessageDesc(unknown :DeepFrozen, verb :Str, params :DeepFrozen,
                      guard :DeepFrozen) as DeepFrozen:
    return object messageDesc as DeepFrozen:
        to getArity() :Int:
            return params.size()

        to getVerb() :Str:
            return verb


object __makeProtocolDesc as DeepFrozen:
    "Produce an interface."

    to run(docString :DeepFrozen, name :Str, alsoUnknown :DeepFrozen,
           stillUnknown :DeepFrozen, messages :List[DeepFrozen]):
        # Precalculate [verb, arity] set of required methods.
        def desiredMethods :DeepFrozen := [for message in (messages)
                                           [message.getVerb(),
                                           message.getArity()]].asSet()

        object protocolDesc as DeepFrozen implements Selfless, TransparentStamp:
            "An interface; a description of an object protocol.

             As an auditor, this object proves that audited objects implement
             this interface by examining the object protocol.

             As a guard, this object is an unretractable guard which admits
             all objects with this interface."

            to _printOn(out):
                out.print("<interface ")
                out.print(name)
                out.print(">")

            to _uncall():
                return [__makeProtocolDesc, "run", [docString, name,
                                                    alsoUnknown, stillUnknown,
                                                    messages]]

            to audit(audition) :Bool:
                "Determine whether an object implements this object as an
                 interface."

                # Check that all the methods are there and have the right
                # verb/arity.
                def script := audition.getObjectExpr().getScript()
                def scriptMethods := [for m in (script.getMethods())
                                      [m.getVerb(),
                                       m.getPatterns().size()]].asSet()
                def missingMethods := desiredMethods - scriptMethods
                if (missingMethods.size() != 0):
                    traceln(`audit/1: Missing methods: $missingMethods`)
                    # XXX return false

                return true

            to coerce(specimen, ej):
                "Admit objects which implement this object's interface."

                if (__auditedBy(protocolDesc, specimen)):
                    return specimen

                def conformed := specimen._conformTo(protocolDesc)
                if (__auditedBy(protocolDesc, conformed)):
                    return conformed

                throw.eject(ej, "Specimen did not implement " + name)

        return protocolDesc

    to makePair(docString :DeepFrozen, name :Str, alsoUnknown :DeepFrozen,
                stillUnknown :DeepFrozen, messages :List[DeepFrozen]):
        def protocolDescStamp := __makeProtocolDesc(docString, name,
                                                    alsoUnknown, stillUnknown,
                                                    messages)

        object protocolDesc extends protocolDescStamp implements Selfless, TransparentStamp:
            "The guard for an interface."

            to _uncall():
                return [
                    [__makeProtocolDesc, "makePair", [docString, name,
                                                      alsoUnknown,
                                                      stillUnknown,
                                                      messages]],
                    "get", [0]]

            to audit(_):
                throw("Can't audit with this object")

        return [protocolDesc, protocolDescStamp]

[=> __makeMessageDesc, => __makeParamDesc, => __makeProtocolDesc]
