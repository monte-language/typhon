import "unittest" =~ [=> unittest]
import "lib/entropy/entropy" =~ [=> makeEntropy :DeepFrozen]
import "lib/entropy/pcg" =~ [=> makePCG :DeepFrozen]
exports (Arb, arb, prop)

# Property-based testing.

interface Arb :DeepFrozen:
    "An arbitrary source of values."

    to arbitrary(entropy):
        "The next value."

    to shrink(value) :List:
        "Given a value, produce zero or more simpler values."

object arb as DeepFrozen:
    "Arbitrary sources of values."

    to Void():
        return object arbVoid as Arb:
            to arbitrary(_entropy) :Void:
                return null

            to shrink(_) :List:
                # The Void hungers.
                return []

    to Bool():
        return object arbBool as Arb:
            to arbitrary(entropy) :Bool:
                return entropy.nextBool()

            to shrink(b :Bool) :List[Bool]:
                return [!b]

    to Bytes():
        def makeBytes(l):
            return _makeBytes.fromInts([for i in (l) i % 256])

        return object arbBytes extends arb.List(arb.Int()):
            to arbitrary(entropy) :Bytes:
                return makeBytes(super.arbitrary(entropy))

            to shrink(l :List[Int]) :List[Bytes]:
                return [for is in (super.shrink(l)) makeBytes(is)]

    to Char():
        return object arbChar as Arb:
            to arbitrary(entropy) :Char:
                # XXX this is just a spot in the BMP below which every
                # character is valid.
                return '\x00' + entropy.nextInt(0xd7ff)

            to shrink(c :Char) :List[Char]:
                return []

    to Int():
        return object arbInt as Arb:
            to arbitrary(entropy) :Int:
                # Hypothesis uses this as its ceiling.
                def i := entropy.nextInt(2 ** 128)
                return if (entropy.nextBool()) {i} else {-i}

            to shrink(i :Int) :List[Int]:
                return [i >> 1]

    to Str():
        return object arbStr extends arb.List(arb.Char()):
            to arbitrary(entropy) :Str:
                return _makeStr.fromChars(super.arbitrary(entropy))

            to shrink(l :List[Char]) :List[Str]:
                return [for cs in (super.shrink(l)) _makeStr.fromChars(cs)]

    to List(subArb, => maxSize :Int := 100):
        return object arbList as Arb:
            to arbitrary(entropy) :List:
                def size :Int := entropy.nextExponential(0.25).floor().min(maxSize)
                return if (size == 0) { [] } else {
                    [for _ in (0..!size) subArb.arbitrary(entropy)]
                }

            to shrink(l :List) :List[List]:
                def singles := [for x in (l) [x]]
                def heads := [for i => _ in (l) [l.slice(0, i)]]
                def tails := [for i => _ in (l) [l.slice(i, l.size())]]
                return singles + heads + tails

    to Map(keyArb, valueArb, => maxSize :Int := 100):
        return object arbMap as Arb:
            to arbitrary(entropy) :Map:
                # Make larger maps more likely too.
                def size :Int := entropy.nextExponential(0.1).floor().min(maxSize)
                return if (size == 0) { [].asMap() } else {
                    [for _ in (0..!size)
                     keyArb.arbitrary(entropy) => valueArb.arbitrary(entropy)]
                }

            to shrink(m :Map) :List[Map]:
                def singles := [for k => v in (m) [k => v]]
                return singles

    to Set(subArb):
        return object arbSet as Arb:
            to arbitrary(entropy) :Set:
                # Make larger sets more likely since the set is likelier to
                # have overlap.
                def size :Int := entropy.nextExponential(0.1).floor()
                return if (size == 0) { [].asSet() } else {
                    [for _ in (0..!size) subArb.arbitrary(entropy)].asSet()
                }

            to shrink(s :Set) :List[Set]:
                def singles := [for x in (s) [x].asSet()]
                return singles

    match [=="Any", subArbs, _]:
        object arbAny as Arb:
            to arbitrary(entropy):
                return entropy.nextDraw(subArbs).arbitrary(entropy)

            to shrink(_) :List:
                # We don't know which of our subordinates created the value.
                return []

def prop.test(arbs, f, => iterations :Int := 500) as DeepFrozen:
    "A property-based tester."

    def entropy := makeEntropy(makePCG(42, 5))

    return object propTest:
        to _printOn(out):
            out.print(`<property ($f)>`)

        to run(assert):
            # traceln(`testing $test`)
            # XXX needs to have a stack of pending cases to try, in order
            # to search shrunken cases
            def failures := [].diverge()
            for _ in (0..!iterations):
                def args := [for arb in (arbs) arb.arbitrary(entropy)]

                object hypothesis:
                    to assume(assumption :Bool) :Void:
                        "Require `assumption` or abort the test."

                        if (!assumption) { continue }

                    to assert(truth :Bool) :Void:
                        "Require `truth` or fail the test."
                        if (!truth) { failures.push(args) }

                # traceln(`Trying $args`)
                M.call(f, "run", [hypothesis] + args, [].asMap())
            if (!failures.isEmpty()):
                assert.fail(`Property $f failed on cases: ${failures.snapshot()}`)

def ringAxioms(strategy):
    def ringAxiomAbelianAssociative(hy, a, b, c):
        hy.assert((a + b) + c == a + (b + c))
    def ringAxiomAbelianCommutative(hy, a, b):
        hy.assert(a + b == b + a)
    def ringAxiomAbelianIdentity(hy, a):
        hy.assert(a + 0 == a)
    def ringAxiomAbelianInverse(hy, a):
        hy.assert(a + (-a) == 0)
    def ringAxiomMonoidAssociative(hy, a, b, c):
        hy.assert((a * b) * c == a * (b * c))
    def ringAxiomMonoidIdentity(hy, a):
        hy.assert(a * 1 == a)
    def ringAxiomDistributiveLeft(hy, a, b, c):
        hy.assert(a * (b + c) == a * b + a * c)
    def ringAxiomDistributiveRight(hy, a, b, c):
        hy.assert((a + b) * c == a * c + b * c)
    def one := [strategy]
    def two := one * 2
    def three := one * 3
    unittest([
        prop.test(three, ringAxiomAbelianAssociative),
        prop.test(two, ringAxiomAbelianCommutative),
        prop.test(one, ringAxiomAbelianIdentity),
        prop.test(one, ringAxiomAbelianInverse),
        prop.test(three, ringAxiomMonoidAssociative),
        prop.test(one, ringAxiomMonoidIdentity),
        prop.test(three, ringAxiomDistributiveLeft),
        prop.test(three, ringAxiomDistributiveRight),
    ])

# Int is a ring.
ringAxioms(arb.Int())

def containers := [
    arb.Bytes(),
    arb.Str(),
    arb.List(arb.Int()),
    arb.Map(arb.Int(), arb.Int()),
    arb.Set(arb.Int()),
]

# Containers have zero size iff they are empty.
def zeroSizeIffEmpty(hy, container):
    hy.assert(!((container.size() == 0) ^ container.isEmpty()))
for container in (containers):
    unittest([
        prop.test([container], zeroSizeIffEmpty),
    ])
