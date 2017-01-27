import "unittest" =~ [=> unittest]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/entropy/pcg" =~ [=> makePCG]

exports ()


def entropy := makeEntropy(makePCG(42, 5))

interface Arb:
    "An arbitrary source of values."

    to arbitrary():
        "The next value."

    to shrink(value) :List:
        "Given a value, produce zero or more simpler values."

object arb:
    "Arbitrary sources of values."

    to Bool():
        return object arbBool as Arb:
            to arbitrary() :Bool:
                return entropy.nextBool()

            to shrink(b :Bool) :List[Bool]:
                return []

    to Bytes():
        def makeBytes(l):
            return _makeBytes.fromInts([for i in (l) i % 256])

        return object arbBytes extends arb.List(arb.Int()):
            to arbitrary() :Bytes:
                return makeBytes(super.arbitrary())

            to shrink(l :List[Int]) :List[Bytes]:
                return [for is in (super.shrink(l)) makeBytes(is)]

    to Char():
        return object arbChar as Arb:
            to arbitrary() :Char:
                # XXX this is just a spot in the BMP below which every
                # character is valid.
                return '\x00' + entropy.nextInt(0xd7ff)

            to shrink(c :Char) :List[Char]:
                return []

    to Int():
        return object arbInt as Arb:
            to arbitrary() :Int:
                # Hypothesis uses this as its ceiling.
                def i := entropy.nextInt(2 ** 128)
                return if (entropy.nextBool()) {i} else {-i}

            to shrink(i :Int) :List[Int]:
                return [i >> 1]

    to Str():
        return object arbStr extends arb.List(arb.Char()):
            to arbitrary() :Str:
                return _makeStr.fromChars(super.arbitrary())

            to shrink(l :List[Char]) :List[Str]:
                return [for cs in (super.shrink(l)) _makeStr.fromChars(cs)]

    to List(subArb):
        return object arbList as Arb:
            to arbitrary() :List:
                def size :Int := entropy.nextExponential(0.25).floor()
                return if (size == 0) { [] } else {
                    [for _ in (0..!size) subArb.arbitrary()]
                }

            to shrink(l :List) :List[List]:
                def singles := [for x in (l) [x]]
                def heads := [for i => _ in (l) [l.slice(0, i)]]
                def tails := [for i => _ in (l) [l.slice(i, l.size())]]
                return singles + heads + tails

    to Map(keyArb, valueArb):
        return object arbMap as Arb:
            to arbitrary() :Map:
                # Make larger maps more likely too.
                def size :Int := entropy.nextExponential(0.1).floor()
                return if (size == 0) { [].asMap() } else {
                    [for _ in (0..!size)
                     keyArb.arbitrary() => valueArb.arbitrary()]
                }

            to shrink(m :Map) :List[Map]:
                def singles := [for k => v in (m) [k => v]]
                return singles

    to Set(subArb):
        return object arbSet as Arb:
            to arbitrary() :Set:
                # Make larger sets more likely since the set is likelier to
                # have overlap.
                def size :Int := entropy.nextExponential(0.1).floor()
                return if (size == 0) { [].asSet() } else {
                    [for _ in (0..!size) subArb.arbitrary()].asSet()
                }

            to shrink(s :Set) :List[Set]:
                def singles := [for x in (s) [x].asSet()]
                return singles

object proptest:
    "A property-based tester."

    match [=="run", [test] + arbs, [=> iterations :Int := 500] | _]:
        # traceln(`testing $test`)
        for _ in (0..!iterations):
            def args := [for arb in (arbs) arb.arbitrary()]
            # traceln(`Trying $args`)
            M.call(test, "run", args, [].asMap())

def IntFormsARing(assert):
    def ringAxiomAbelianAssociative(a, b, c):
        assert.equal((a + b) + c, a + (b + c))
    proptest(ringAxiomAbelianAssociative, arb.Int(), arb.Int(), arb.Int())
    def ringAxiomAbelianCommutative(a, b):
        assert.equal(a + b, b + a)
    proptest(ringAxiomAbelianCommutative, arb.Int(), arb.Int())
    def ringAxiomAbelianIdentity(a):
        assert.equal(a + 0, a)
    proptest(ringAxiomAbelianIdentity, arb.Int())
    def ringAxiomAbelianInverse(a):
        assert.equal(a + (-a), 0)
    proptest(ringAxiomAbelianInverse, arb.Int())
    def ringAxiomMonoidAssociative(a, b, c):
        assert.equal((a * b) * c, a * (b * c))
    proptest(ringAxiomMonoidAssociative, arb.Int(), arb.Int(), arb.Int())
    def ringAxiomMonoidIdentity(a):
        assert.equal(a * 1, a)
    proptest(ringAxiomMonoidIdentity, arb.Int())
    def ringAxiomDistributiveLeft(a, b, c):
        assert.equal(a * (b + c), a * b + a * c)
    proptest(ringAxiomDistributiveLeft, arb.Int(), arb.Int(), arb.Int())
    def ringAxiomDistributiveRight(a, b, c):
        assert.equal((a + b) * c, a * c + b * c)
    proptest(ringAxiomDistributiveRight, arb.Int(), arb.Int(), arb.Int())

unittest([IntFormsARing])

def ThingsWithZeroSizeAreEmpty(assert):
    def zeroSizeIffEmpty(container):
        assert.iff(container.size() == 0, container.isEmpty())
    proptest(zeroSizeIffEmpty, arb.Bytes())
    proptest(zeroSizeIffEmpty, arb.Str())
    proptest(zeroSizeIffEmpty, arb.List(arb.Int()))
    proptest(zeroSizeIffEmpty, arb.Map(arb.Int(), arb.Int()))
    proptest(zeroSizeIffEmpty, arb.Set(arb.Int()))

unittest([ThingsWithZeroSizeAreEmpty])
