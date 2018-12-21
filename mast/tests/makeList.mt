import "unittest" =~ [=> unittest :Any]
import "tests/proptests" =~ [=> arb, => prop]
exports (testMakeList)

def testMakeList(makeList) as DeepFrozen:
    def wrap(l):
        return M.call(makeList, "run", l, [].asMap())

    # Properties any container has.
    def zeroSizeIffEmpty(hy, l):
        def wrapped := wrap(l)
        hy.assert(!((wrapped.size() == 0) ^ wrapped.isEmpty()))

    # Properties that lists have and that we can compare directly.
    def makeListIsEmpty(hy, l):
        hy.sameEver(l.isEmpty(), wrap(l).isEmpty())

    def makeListSize(hy, l):
        hy.sameEver(l.size(), wrap(l).size())

    def tests := [
        zeroSizeIffEmpty,
        makeListIsEmpty,
        makeListSize,
    ]
    return [for test in (tests) prop.test([arb.List(arb.Int())], test)]

unittest(testMakeList(_makeList))
