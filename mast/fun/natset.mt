exports (makeNatSet)

def Nat :DeepFrozen := Int >= 0

def testBit(n :Nat, k :Nat) :Bool as DeepFrozen:
    return !(n & (1 << k)).isZero()

def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
object makeNatSet as DeepFrozen implements makerAuditor:
    to run(arg):
        def n :Nat := arg
        return object natSet implements Selfless, valueAuditor:
            "An unordered set of natural numbers."

            to _uncall():
                return serializer(makeNatSet, [arg])

            to _makeIterator():
                var i := 0
                var k := 0
                return def natSetIterator.next(ej):
                    while (!testBit(n, k)):
                        k += 1
                        if (k >= n.bitLength()):
                            throw.eject(ej, "End of iteration")
                    def rv := [i, k]
                    i += 1
                    k += 1
                    return rv

            to _printOn(out):
                out.print("{")
                out.print(", ".join([for elt in (natSet) M.toString(elt)]))
                out.print("}")

            to op__cmp(other):
                def o := other.asBits()
                return if (n == o) {
                    0
                } else if ((n & ~o).isZero()) {
                    -1
                } else if ((~n & o).isZero()) {
                    1
                } else { NaN }

            to asBits() :Nat:
                return n

            to contains(k :Nat) :Bool:
                return testBit(n, k)

            to size() :Nat:
                return n.bitSum()

            to isEmpty() :Bool:
                return n.isZero()

            to with(elt :Nat):
                return makeNatSet(n | (1 << elt))

            to without(elt :Nat):
                return makeNatSet(n & ~(1 << elt))

            to or(other):
                return makeNatSet(n | other.asBits())

            to and(other):
                return makeNatSet(n & other.asBits())

    to singleton(x :Nat):
        return makeNatSet(1 << x)

    to fromIterable(iterable):
        var bits := 0
        for i in (iterable):
            bits |= 1 << i
        return makeNatSet(bits)
