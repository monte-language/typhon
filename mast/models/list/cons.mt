import "unittest" =~ [=> unittest :Any]
exports (authorMakeList)

def nilIterator.next(ej) as DeepFrozen:
    throw.eject(ej, "End of iteration")

def authorMakeList(stamp :DeepFrozen) as DeepFrozen:
    object nil as DeepFrozen implements stamp:
        to _makeIterator():
            return nilIterator

        to isEmpty():
            return true

        to size():
            return 0

    def cons(x, xs :stamp) as DeepFrozen:
        def size :Int := 1 + xs.size()
        return object cons as stamp:
            to _makeIterator():
                var i :Int := 0
                return def listIterator.next(ej):
                    if (i >= size):
                        throw.eject(ej, "End of iteration")
                    def rv := [i, cons[i]]
                    i += 1
                    return rv

            to get(i :Int):
                return if (i == 0) { x } else { xs[i - 1] }

            to isEmpty():
                return false

            to size():
                return size

    return object makeList as DeepFrozen:
        # NB: This particular `args` list is built by somebody else and we can
        # interact with it opaquely.
        match [verb, args, _namedArgs]:
            switch (verb):
                match =="run":
                    if (args.isEmpty()):
                        nil
                    else:
                        var rv := nil
                        for x in (args.reverse()):
                            rv := cons(x, rv)
                        rv

interface TestStamp {}

def testListIsEmpty(assert):
    def makeList := authorMakeList(TestStamp)
    assert.equal(makeList().isEmpty(), true)
    assert.equal(makeList(42).isEmpty(), false)

def testListSize(assert):
    def makeList := authorMakeList(TestStamp)
    assert.equal(makeList().size(), 0)
    assert.equal(makeList(42).size(), 1)
    assert.equal(makeList(42, 5).size(), 2)

def testListIterator(assert):
    def makeList := authorMakeList(TestStamp)
    def l := makeList(2, 2, 2)
    def result := [for i => x in (l) [i, x]]
    def expected := [[0, 2], [1, 2], [2, 2]]
    assert.equal(result, expected)

def suite := [
    testListIsEmpty,
    testListSize,
    testListIterator,
]

unittest(suite)
