import "unittest" =~ [=> unittest :Any]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/entropy/pcg" =~ [=> makePCG]
import "lib/freezer" =~ [=> freeze]
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

    to Double():
        def edges := [NaN, Infinity, -Infinity, 0.0, -0.0, 1.0, -1.0]._makeIterator()
        return object arbInt as Arb:
            to arbitrary(entropy) :Double:
                return escape ej:
                    edges.next(ej)[1]
                catch _:
                    var d := entropy.nextDouble()
                    if (entropy.nextBool()):
                        d := d.reciprocal()
                    if (entropy.nextBool()):
                        d := -d
                    d

            to shrink(d :Double) :List[Double]:
                return []

    to Int(=> ceiling :Int := 2 ** 128):
        def edges := [0, 1, -1, 255, ceiling]._makeIterator()
        return object arbInt as Arb:
            to arbitrary(entropy) :Int:
                return escape ej:
                    edges.next(ej)[1]
                catch _:
                    # Hypothesis uses this as its ceiling.
                    def i := entropy.nextInt(ceiling)
                    if (entropy.nextBool()) {i} else {-i}

            to shrink(i :Int) :List[Int]:
                return if (i == 0 || i == -1) { [] } else { [i >> 1] }

    to Str():
        # XXX why extend here?
        return object arbStr extends arb.List(arb.Char()):
            to arbitrary(entropy) :Str:
                return _makeStr.fromChars(super.arbitrary(entropy))

            to shrink(l :List[Char]) :List[Str]:
                return [for cs in (super.shrink(l)) _makeStr.fromChars(cs)]

    to NullOk(subArb):
        var nextNull := true
        return object arbNullOk as Arb:
            to arbitrary(entropy):
                nextNull := !nextNull
                return if (nextNull) { subArb.arbitrary(entropy) }

            to shrink(val):
                return if (val == null) { [] } else { subArb.shrink(val) }

    to List(subArb, => maxSize :Int := 100):
        return object arbList as Arb:
            to arbitrary(entropy) :List:
                def size :Int := entropy.nextExponential(0.25).floor().min(maxSize)
                return if (size == 0) { [] } else {
                    [for _ in (0..!size) subArb.arbitrary(entropy)]
                }

            to shrink(l :List) :List[List]:
                def singles := [for x in (l) [x]]
                def heads := [for i => _ in (l) l.slice(0, i)]
                def tails := [for i => _ in (l) l.slice(i, l.size())]
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
                return [for k => v in (m) [k => v]]

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
                return [for x in (s) [x].asSet()]

    to Ast(subArb):
        return object arbAst as Arb:
            to arbitrary(entropy) :DeepFrozen:
                # Uncall/freeze logic should generally work for anything
                # generated by our arbs, but might not always work. We'll try
                # our best!
                return freeze(subArb.arbitrary(entropy))
            to shrink(expr :DeepFrozen) :List[DeepFrozen]:
                return [for x in (subArb.shrink(eval(expr, safeScope)))
                        freeze(x)]

    match [=="Any", subArbs, _]:
        object arbAny as Arb:
            to arbitrary(entropy):
                return entropy.nextElement(subArbs).arbitrary(entropy)

            to shrink(_) :List:
                # We don't know which of our subordinates created the value.
                return []

def prop.test(arbs, f, => iterations :Int := 2 ** 6) as DeepFrozen:
    "A property-based tester."

    def entropy := makeEntropy(makePCG(42, 5))

    return object propTest:
        to _printOn(out):
            out.print(`<property ($f)>`)

        to run(assert):
            def failures := [].diverge()
            def cases := [for _ in (0..!iterations) {
                [for arb in (arbs) arb.arbitrary(entropy)]
            }].asSet().asList().diverge()
            def tried := [].asSet().diverge()
            def failed := [].asSet().diverge()
            while (!cases.isEmpty()):
                def args :List[Near] := cases.pop()
                tried.include(args)

                def fail(message):
                    # Generate some shrunken cases. Shrink one argument at a
                    # time in order to explore as many corners of the failure
                    # as possible.
                    for i => arb in (arbs) {
                        for head in (arb.shrink(args[i])) {
                            def case := args.with(i, head)
                            if (!tried.contains(case)) {
                                cases.push(case)
                            }
                        }
                    }
                    if (!failed.contains(args)) {
                        failed.include(args)
                        failures.push([args, message])
                    }

                object hypothesis:
                    to assume(assumption :Bool) :Void:
                        "Require `assumption` or abort the test."

                        # XXX miscompile?
                        if (!assumption) { continue }

                    to assert(truth :Bool) :Void:
                        "Require `truth` or fail the test."
                        if (!truth):
                            fail("hy.assert(false)")

                    to sameEver(left, right) :Void:
                        if (left != right):
                            fail(`hy.sameEver($left, $right)`)

                    to asBigAs(left, right) :Void:
                        if (!(left <=> right)):
                            fail(`hy.asBigAs($left, $right)`)

                M.call(f, "run", [hypothesis] + args, [].asMap())
            if (!failures.isEmpty()):
                def failureSize := failures.size()
                def failuresToShow := failures.slice(0, failureSize.min(5))
                def messages := [for [args, blurb] in (failuresToShow) {
                    `Case $args failure: $blurb`
                }]
                assert.fail(`Property $f failed on $failureSize cases: ${"\n".join(messages)}`)

def testPropNoRepeatedBools(assert):
    var timesCalled :Int := 0
    prop.test([arb.Bool()], fn _hy, _b { timesCalled += 1 })(assert)
    assert.equal(timesCalled, 2)

# We won't run tests many times with the same input.
unittest([
    testPropNoRepeatedBools,
])
