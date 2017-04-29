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

def isMiranda(meth) :Bool as DeepFrozen:
    return mirandaMessages.contains([meth.getVerb(), meth.getArity()])

def defaultMessages :Map[DeepFrozen, DeepFrozen] := [
    # Guard protocol.
    ["coerce", 2] => "Coerce a specimen with this object, ejecting on failure.",

    # Codec protocol.
    ["decode", 2] => "Decode a value with this codec, ejecting on failure.",
    ["encode", 2] => "Encode a value with this codec, ejecting on failure.",

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
    return "\n".join([for piece in (pieces) ? (piece.size() != 0) piece])

def makeRibbon(=> sep :Str := " ", => width :Int := 78) as DeepFrozen:
    var currentLine := [].diverge()
    var currentWidth :Int := 0
    def lines := [].diverge()

    return object ribbon:
        to push(fragment :Str):
            if (currentWidth + sep.size() + fragment.size() > width):
                # Too wide. Make a new line.
                lines.push("".join(currentLine))
                currentLine := [fragment].diverge()
                currentWidth := fragment.size()
            else:
                if (!currentLine.isEmpty()):
                    currentLine.push(sep)
                    currentWidth += sep.size()
                currentLine.push(fragment)
                currentWidth += fragment.size()

        to snapshot() :Str:
            return "\n".join(lines.with("".join(currentLine)))

object help as DeepFrozen:
    "A gentle introspection assistant."

    to _printOn(out):
        out.print("<help is a gentle introspection assistant. To obtain help on an object, try m`help(obj)`>")

    to run(specimen, => showMiranda :Bool := false) :Str:
        def lines := [].diverge()

        def iface := specimen._getAllegedInterface()
        lines.push(`Object: ${M.toQuote(specimen)} Object interface: $iface`)

        def doc := iface.getDocstring()
        if (doc != null):
            lines.push(dedent(doc))

        def methods := [for meth in (iface.getMethods())
                        ? (showMiranda || !isMiranda(meth)) meth]
        if (methods.isEmpty()):
            lines.push("No methods declared")
        else:
            def ribbon := makeRibbon()
            ribbon.push("Methods declared:")
            for meth in (methods):
                ribbon.push(`${meth.getVerb()}/${meth.getArity()}`)
            lines.push(ribbon.snapshot())

        return "\n".join(lines)

    to run(specimen, verb :Str, arity :Int) :Str:
        def lines := [].diverge()

        def iface := specimen._getAllegedInterface()
        lines.push(`Object: $specimen Object type: $iface`)

        var found :Bool := false
        for meth in (iface.getMethods()):
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
