# Name replacement in prelude means we can't use normal module sugar.
def coreInterfaces(loader):
    def compose(f :DeepFrozen, g :DeepFrozen):
        "Compose two objects together.

         This composite object passes messages to `f`, except for those which
         raise exceptions, which are passed to `g` instead."

        # Subrange proof.
        def F :Same[f] := f

        return object composition as DeepFrozen implements SubrangeGuard[DeepFrozen]:
            "A composite core interface.

             As an interface, this object represents the collections of methods
             available on core objects. As a guard, this object guards precisely
             those core objects with those methods."

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
        "Objects which are totally ordered.

         Not all comparable objects are comparable to each other; in general,
         comparable objects are only aware of other objects with the same
         interface."

        to op__cmp(other) :Comparison


    interface WellOrdered:
        "Objects which are well ordered.

         Well-ordering for Monte generalizes in both directions: Neither `next()`
         nor `previous()` are required to reach fixed points under repeated
         application."

        to previous():
            "The preceding element.

             There is at most one element `x` such that `x.previous() == x`; if it
             exists, it is the least element."

        to next():
            "The following element.

             There is at most one element `x` such that `x.next() == x`; if it
             exists, it is the least element."


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


    interface coreChar extends Comparable, WellOrdered:
        "The Unicode codepoints."

        to add(other :Int) :Char
        to subtract(other :Int) :Char

        to asInteger() :Int
        to asString() :Str

        to getCategory() :Str

        to max(other :Char) :Char
        to min(other :Char) :Char

        to quote() :Str


    # XXX should Double be WellOrdered?
    interface coreDouble extends Comparable, Comparison:
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


    interface coreInt extends Comparable, Comparison, WellOrdered:
        "Integers."

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


    interface coreBytes extends Comparable:
        "Octet strings."

        to getSpan()

        to asList() :List[Int]
        to asSet() :Set[Int]

        to add(other) :Bytes
        to join(pieces :List[Bytes]) :Bytes
        to multiply(count :Int) :Bytes
        to replace(old :Bytes, new :Bytes) :Bytes
        to with(last :Int) :Bytes

        to contains(needle) :Bool
        to endsWith(needle :Bytes) :Bool
        to startsWith(needle :Bytes) :Bool

        to get(index :Int) :Int
        to slice(start :Int) :Bytes
        to slice(start :Int, stop :Int) :Bytes
        to split(needle :Bytes) :List[Bytes]
        to split(needle :Bytes, count :Int) :List[Bytes]

        to indexOf(needle :Bytes) :Int
        to indexOf(needle :Bytes, offset :Int) :Int
        to lastIndexOf(needle :Bytes) :Int
        to lastIndexOf(needle :Bytes, offset :Int) :Int

        to size() :Int

        to _makeIterator()

    return [
        => Comparison,
        => Comparable,
        => WellOrdered,
        "Void" => compose(Void, coreVoid),
        "Bool" => compose(Bool, coreBool),
        "Bytes" => compose(Bytes, coreBytes),
        "Char" => compose(Char, coreChar),
        "Double" => compose(Double, coreDouble),
        "Int" => compose(Int, coreInt),
        "Str" => compose(Str, coreStr),
    ]
