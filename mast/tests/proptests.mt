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
        return object arbBool:
            to arbitrary():
                return entropy.nextBool()

            to shrink(b :Bool) :List[Bool]:
                return []

    to Int():
        return object arbInt:
            to arbitrary():
                # Hypothesis uses this as its ceiling.
                def i := entropy.nextInt(2 ** 128)
                return if (entropy.nextBool()) {i} else {-i}

            to shrink(i :Int) :List[Int]:
                return [i >> 1]

object proptest:
    "A property-based tester."

    match [=="run", [test] + arbs, [=> iterations :Int := 500] | _]:
        # traceln(`testing $test`)
        for i in (0..!iterations):
            def args := [for arb in (arbs) arb.arbitrary()]
            # traceln(`Trying $args`)
            M.call(test, "run", args)

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
