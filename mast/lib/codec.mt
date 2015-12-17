imports
exports (composeCodec)

def composeCodec(outer :DeepFrozen, inner :DeepFrozen) as DeepFrozen:
    "Compose an outer codec with an inner codec.
    
     The nesting is always oriented so that the 'outer' codec is on the
     encoding side, and the 'inner' codec is on the decoding side."

    return object composedCodec as DeepFrozen implements Selfless:
        "A combination of two codecs."

        to _printOn(out):
            out.print(`composedCodec($outer ⤳ $inner)`)

        to _uncall():
            return [composeCodec, "run", [outer, inner], [].asMap()]

        to encode(specimen, ej):
            return outer.encode(inner.encode(specimen, ej), ej)

        to decode(specimen, ej):
            return inner.decode(outer.decode(specimen, ej), ej)
