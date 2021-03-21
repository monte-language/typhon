```
exports (help)
```

# Descriptions of Objects

An introspection assistant is a simple tool which takes arbitrary specimens
and pretty-prints information about their behavior. We cannot avoid calling
some methods on these specimens, but we will limit ourselves to [Miranda
methods](https://github.com/monte-language/monte/blob/master/docs/source/miranda.rst)
since those are always available.

## Miranda Methods

Speaking of Miranda methods, we will want to respect objects which have
overridden them with custom behaviors. In most cases, objects do not want
special attention drawn to these overridden methods, and wish to be treated
uniformly like any other object. Additionally, we do not want to repeatedly
inform the user that an object has a custom pretty-printing method, as those
are extremely common and thus somewhat noisy.

```
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
```

## Common Protocols

There are some object protocols which are well-known. Some of them are built
into Monte's semantics:

* Guards
* Miranda

And some of them are common throughout the standard library:

* Codecs

```
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
```

## Handling Docstrings

XXX this dedent tool could be reused in tools/docs?

```
def dedent(paragraph :Str) :Str as DeepFrozen:
    "Remove leading spaces from every line of a paragraph."

    def pieces := [for line in (paragraph.split("\n")) line.trim()]
    return "\n".join([for piece in (pieces) ? (piece.size() != 0) piece])
```

## Handling Methods

Some objects have lots of methods. For those objects, we want to wrap the line
with all of the method signatures so that it is more readable.

```
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
```

## Introspection Assistant

We have some common code for retrieving the methods from a specimen. We'll
also pre-format the specimen's main description.

```
def extractMethods(specimen, => showMiranda :Bool) as DeepFrozen:
    if (!Ref.isNear(specimen)):
        return [`Object $specimen is not near.`, []]

    def preamble := [].diverge(Str)

    def iface := specimen._getAllegedInterface()
    preamble.push(`Object: ${M.toQuote(specimen)}`)
    preamble.push(`Object interface: $iface`)

    def doc := iface.getDocstring()
    if (doc != null):
        preamble.push(dedent(doc))

    def methods := [for meth in (iface.getMethods())
                    ? (showMiranda || !isMiranda(meth)) meth]
    return ["\n".join(preamble), methods]

def filterVerb(methods, verb :Str) as DeepFrozen:
    return [for m in (methods) ? (m.getVerb() == verb) m]

def filterAtom(methods, verb :Str, arity :Int) as DeepFrozen:
    return [for m in (methods) ? (m.getVerb() == verb && m.getArity() == arity) m]

def documentMethod(m) :Str as DeepFrozen:
    def verb := m.getVerb()
    def arity := m.getArity()
    def header := `Method: $verb/$arity`

    # If the docstring isn't null, then use it.
    def body := if ((def doc := m.getDocstring()) != null) {
        dedent(doc)
    # Otherwise, if there's a default docstring, then use it.
    } else if (defaultMessages =~ [([verb, arity]) => doc] | _) {
        "(Undocumented method; default docstring:)\n" + dedent(doc)
    } else { "(Undocumented method)" }

    return header + "\n" + body
```

Finally, putting everything together, we have a top-level tool which users can
call from a REPL.

```
object help as DeepFrozen:
    "A gentle introspection assistant."

    to _printOn(out):
        out.print("<help is a gentle introspection assistant. To obtain help on an object, try m`help(obj)`>")

    to run(specimen, => showMiranda :Bool := false) :Str:
        def [preamble, methods] := extractMethods(specimen, => showMiranda)

        def body := switch (methods) {
            match [] { "No methods declared." }
            match [m] { "Single-method object:\n" + documentMethod(m) }
            match _ {
                def ribbon := makeRibbon()
                ribbon.push("Methods declared:")
                for m in (methods) {
                    ribbon.push(`${m.getVerb()}/${m.getArity()}`)
                }
                ribbon.snapshot()
            }
        }

        return preamble + "\n" + body

    to run(specimen, verb :Str, => showMiranda :Bool := false) :Str:
        "
        Explain the method `verb` on `specimen`.

        If `specimen` has multiple methods for `verb`, then they will all be
        displayed.
        "

        def [preamble, methods] := extractMethods(specimen, => showMiranda)

        def candidates := filterVerb(methods, verb)

        def body := if (candidates.isEmpty()) { "(Method not found)" } else {
            "\n".join([for m in (candidates) documentMethod(m)])
        }

        return preamble + "\n" + body

    to run(specimen, verb :Str, arity :Int, => showMiranda :Bool := false) :Str:
        "
        Explain the method `verb` with `arity` arguments on `specimen`.
        "

        def [preamble, methods] := extractMethods(specimen, => showMiranda)

        def candidates := filterAtom(methods, verb, arity)

        def body := if (candidates.isEmpty()) { "(Method not found)" } else {
            "\n".join([for m in (candidates) documentMethod(m)])
        }

        return preamble + "\n" + body
```
