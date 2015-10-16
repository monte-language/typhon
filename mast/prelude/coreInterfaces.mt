def compose(f :SubrangeGuard[DeepFrozen], g :DeepFrozen):
    "Compose two objects together.

     This composite object passes messages to `f`, except for those which
     raise exceptions, which are passed to `g` instead."

    # Subrange proof.
    def F :Same[f] := f

    return object composition as DeepFrozen implements SubrangeGuard[F]:
        to coerce(specimen, ej) :F:
            return f.coerce(specimen, ej)

        match message:
            try:
                M.callWithMessage(f, message)
            catch _:
                M.callWithMessage(g, message)


interface Comparison:
    "An instance of comparing."

    to aboveZero() :Bool
    to atLeastZero() :Bool
    to atMostZero() :Bool
    to belowZero() :Bool
    to isZero() :Bool


interface Comparable:
    "An object with total ordering."

    to op__cmp(other) :Comparison


interface coreVoid:
    "The void."


interface coreBool extends Comparable:
    "The Boolean values."

    to and(other :Bool) :Bool
    to butNot(other :Bool) :Bool
    to or(other :Bool) :Bool
    to xor(other :Bool) :Bool

    to not() :Bool

    to pick(ifTrue, ifFalse):
        "Return `ifTrue` if true, else `ifFalse` if false."


interface coreChar extends Comparable:
    "The Unicode codepoints."

    to add(other :Int) :Char
    to subtract(other :Int) :Char

    to asInteger() :Int
    to asString() :Str

    to getCategory() :Str

    to max(other :Char) :Char
    to min(other :Char) :Char

    to previous() :Char
    to next() :Char

    to quote() :Str


interface coreDouble extends Comparable:
    "IEEE 754 double-precision floating-point numbers."

    to add(other) :Double
    to approxDivide(other) :Double
    to multiply(other) :Double
    to subtract(other) :Double

    # XXX should be asBytes() ~ C.
    to toBytes() :Bytes

    to abs() :Double
    to floor() :Double
    to negate() :Double

    # XXX Should we rename these? They could all be expanded by a few
    # characters and they're pretty rare... ~ C.
    to sqrt() :Double
    to log() :Double
    to log(base) :Double
    to sin() :Double
    to cos() :Double
    to tan() :Double


interface coreInt extends Comparable:
    "Integers."

    to aboveZero() :Bool
    to atLeastZero() :Bool
    to atMostZero() :Bool
    to belowZero() :Bool
    to isZero() :Bool

    to and(other :Int) :Int
    to butNot(other :Int) :Int
    to or(other :Int) :Int
    to xor(other :Int) :Int

    to complement() :Int
    to negate() :Int

    to add(other)
    to approxDivide(other) :Double
    to floorDivide(other :Int) :Int
    to mod(modulus :Int) :Int
    to modPow(exponent :Int, modulus :Int) :Int
    to multiply(other :Int) :Int
    to pow(exponent :Int) :Int
    to subtract(other)

    to max(other :Int) :Int
    to min(other :Int) :Int

    to next() :Int
    to previous() :Int

    to bitLength() :Int
    to shiftLeft(width :Int) :Int
    to shiftRight(width :Int) :Int


interface coreStr extends Comparable:
    "Unicode strings."

    to getSpan()

    to asList() :List[Char]
    to asSet() :Set[Char]

    to add(other) :Str
    to join(pieces :List[Str]) :Str
    to multiply(count :Int) :Str
    to replace(old :Str, new :Str) :Str
    to with(last :Char) :Str

    to contains(needle) :Bool
    to endsWith(needle :Str) :Bool
    to startsWith(needle :Str) :Bool

    to get(index :Int) :Char
    to slice(start :Int) :Str
    to slice(start :Int, stop :Int) :Str
    to split(needle :Str) :List[Str]
    to split(needle :Str, count :Int) :List[Str]

    to indexOf(needle :Str) :Int
    to indexOf(needle :Str, offset :Int) :Int
    to lastIndexOf(needle :Str) :Int
    to lastIndexOf(needle :Str, offset :Int) :Int

    to quote() :Str
    # Should be asLowerCase(), etc. ~ C.
    to toLowerCase() :Str
    to toUpperCase() :Str
    to trim() :Str

    to size() :Int

    to _makeIterator()


[
    "Void" => compose(Void, coreVoid),
    "Bool" => compose(Bool, coreBool),
    "Char" => compose(Char, coreChar),
    "Double" => compose(Double, coreDouble),
    "Int" => compose(Int, coreInt),
    "Str" => compose(Str, coreStr),
]
