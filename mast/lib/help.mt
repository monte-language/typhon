imports
exports (help)
"Descriptions of objects."

def mirandaMessages :Set[DeepFrozen] := [
    ["_conformTo", 1],
    ["_printOn", 1],
    ["_respondsTo", 2],
    ["_sealedDispatch", 1],
    ["_uncall", 0],
    ["_whenMoreResolved", 1],
].asSet()

def defaultMessages :Map[DeepFrozen, Str] := [
    ["coerce", 2] => "Coerce a specimen with this object, ejecting on failure.",

    # Miranda.
    ["_conformTo", 1] => "Conform this object to an interface.",
    ["_printOn", 1] => "Print this object onto a printer.",
    ["_respondsTo", 2] => "Determine whether this object is likely to respond to a message.",
    ["_sealedDispatch", 1] => "Perform generic sealed dispatch.",
    ["_uncall", 0] => "Uncall this object into its components.",
    ["_whenMoreResolved", 1] => "This object has become more resolved.",
]

def dedent(paragraph :Str) :Str as DeepFrozen:
    "Remove leading spaces from every line of a paragraph."

    def pieces := [for line in (paragraph.split("\n")) line.trim()]
    return "\n".join([for piece in (pieces) if (piece.size() != 0) piece])

object help as DeepFrozen:
    "A gentle introspection assistant."

    to _printOn(out):
        out.print("To obtain help on an object, try: help(anObject)")

    to run(specimen, => showMiranda :Bool := false) :Str:
        def lines := [].diverge()

        def iface := specimen._getAllegedInterface()
        lines.push(`Object: $specimen Object type: $iface`)

        def doc := iface.getDocstring()
        if (doc != null):
            lines.push(dedent(doc))

        var anyMethods :Bool := false
        for meth in iface.getMethods():
            anyMethods := true
            def message := def [verb, arity] := [meth.getVerb(), meth.getArity()]
            if (showMiranda || !mirandaMessages.contains(message)):
                lines.push(`Method: $verb/$arity`)
                def methodDoc := meth.getDocstring()
                if (methodDoc != null):
                    lines.push(dedent(methodDoc))
        if (!anyMethods):
            if (showMiranda):
                lines.push("No methods declared")
            else:
                lines.push("No (non-Miranda) methods declared")

        return "\n".join(lines)

    to run(specimen, verb :Str, arity :Int) :Str:
        def lines := [].diverge()

        def iface := specimen._getAllegedInterface()
        lines.push(`Object: $specimen Object type: $iface`)

        var found :Bool := false
        for meth in iface.getMethods():
            if (meth.getVerb() == verb && meth.getArity() == arity):
                found := true
                lines.push(`Method: $verb/$arity`)
                # If the docstring isn't null, then use it.
                if ((def doc := meth.getDocstring()) != null):
                    lines.push(dedent(doc))
                # Otherwise, if there's a default docstring, then use it.
                else if (defaultMessages =~ [([verb, arity]) => doc] | _):
                    lines.push("(Undocumented method; default docstring:)")
                    lines.push(dedent(doc))
                else:
                    lines.push("(Undocumented method)")
                break

        if (!found):
            lines.push("(Method not found)")

        return "\n".join(lines)
