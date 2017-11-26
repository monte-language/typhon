import "boot" =~ [=> TransparentStamp :DeepFrozen]
exports (_makeMessageDesc, _makeParamDesc, _makeProtocolDesc)

def _makeParamDesc(name :Str, guard :DeepFrozen) as DeepFrozen:
    "Describe a parameter."

    return object paramDesc as DeepFrozen implements Selfless, TransparentStamp:
        to _printOn(out):
            out.print(`<param $name`)
            if (guard != null):
                out.print(` :$guard`)
            out.print(">")

        to _uncall():
            return [_makeParamDesc, "run", [name, guard], [].asMap()]

        to getGuard() :DeepFrozen:
            return guard

        to getName() :Str:
            return name


def _makeMessageDesc(docstring :Any[Void, Str], verb :Str, params :DeepFrozen,
                     namedParams :DeepFrozen, guard :DeepFrozen) as DeepFrozen:
    "Describe a message."

    return object messageDesc as DeepFrozen implements Selfless, TransparentStamp:
        to _printOn(out):
            out.print(`<message $verb/${params.size()}>`)

        to _uncall():
            return [_makeMessageDesc, "run", [docstring, verb, params, namedParams, guard],
                    [].asMap()]

        to getArity() :Int:
            return params.size()

        to getParams():
            return params

        to getNamedParams():
            return namedParams

        to getDocstring() :Any[Void, Str]:
            return docstring

        to getVerb() :Str:
            return verb

def getMethods(auditor) :Set as DeepFrozen:
    if (auditor._respondsTo("getMethods", 0)):
        return auditor.getMethods()
    else:
        return [].asSet()

def reduce(sets :List[Set]) :Set as DeepFrozen:
    var rv := [].asSet()
    for set in (sets):
        rv |= set
    return rv

object _makeProtocolDesc as DeepFrozen:
    "Produce an interface."

    to run(docstring :Any[Void, Str], name :Str, parents :List,
           stillUnknown :DeepFrozen, messages :List):
        # Precalculate [verb, arity] set of required methods.
        def ownMethods :Set := messages.asSet()
        def parentMethods :List[Set] := [for parent in (parents)
                                         getMethods(parent)]
        def allMethods :Set := ownMethods | reduce(parentMethods)

        object protocolDesc implements Selfless, TransparentStamp:
            "An interface; a description of an object protocol.

             As an auditor, this object proves that audited objects implement
             this interface by examining the object protocol.

             As a guard, this object is an unretractable guard which admits
             all objects with this interface."

            to _printOn(out):
                out.print("<interface ")
                out.print(name)
                if (parents.size() != 0):
                    out.print(" extends ")
                    parents._printOn(out)
                out.print(">")

            to _uncall():
                return [_makeProtocolDesc, "run", [docstring, name, parents,
                                                   stillUnknown, messages],
                        [].asMap()]

            to audit(audition) :Bool:
                "Determine whether an object implements this object as an
                 interface."

                # If any parent interface fails, then we must fail as well.
                for parent in (parents):
                    if (!audition.ask(parent)):
                        return false

                return true

            to coerce(specimen, ej):
                "Admit objects which implement this object's interface."

                if (_auditedBy(protocolDesc, specimen)):
                    return specimen

                def conformed := specimen._conformTo(protocolDesc)
                if (_auditedBy(protocolDesc, conformed)):
                    return conformed

                throw.eject(ej, "Specimen did not implement " + name)

            to getDocstring() :Any[Void, Str]:
                return docstring

            to getMethods() :Set:
                return allMethods

            to supersetOf(guard):
                "Whether `guard` admits a proper subset of this interface."

                if (guard == protocolDesc):
                    return true
                else if (parents.contains(guard)):
                    return true
                return false

        return protocolDesc

    to makePair(docstring :Any[Void, Str], name :Str, parents :List,
                stillUnknown :DeepFrozen, messages :List):
        def protocolDescStamp := _makeProtocolDesc(docstring, name, parents,
                                                   stillUnknown, messages)

        object protocolDesc extends protocolDescStamp implements Selfless, TransparentStamp:
            "The guard for an interface."

            to _uncall():
                def makePair := [_makeProtocolDesc, "makePair",
                                 [docstring, name, parents, stillUnknown,
                                  messages],
                                 [].asMap()]
                return [makePair, "get", [0], [].asMap()]

            to audit(_audition):
                return false

        return [protocolDesc, protocolDescStamp]
