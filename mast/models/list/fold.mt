import "unittest" =~ [=> unittest :Any]
exports (authorMakeList)

# Encoding lists as universal folds.

def nil(f) as DeepFrozen:
    return f.Nil()

def cons(x, xs) as DeepFrozen:
    return fn f { f.Cons(x, xs(f)) }

def isNil(f) :Bool as DeepFrozen:
    return f(object _ {
        to Nil() { return true }
        to Cons(_, _) { return false }
    })

object size as DeepFrozen:
    to Nil():
        return 0
    to Cons(_x, i):
        return i.next()

object tail as DeepFrozen:
    to Nil():
        return nil
    to Cons(_x, xs):
        return xs

# NB: We need access to the list-maker in order to produce the pair that we
# are returning.
def iterate(makeList, var f) as DeepFrozen:
    var i :Int := 0
    return def listIterator.next(ej):
        def val := f(object _ {
            to Nil() { throw.eject(ej, "end of iteration") }
            to Cons(x, _) { return x }
        })
        def rv := makeList(i, val)
        i += 1
        f := f(tail)
        return rv

def authorMakeList(stamp :DeepFrozen) as DeepFrozen:
    return object makeList as DeepFrozen:
        # NB: This particular `args` list is built by somebody else and we can
        # interact with it opaquely.
        match [verb, args, _namedArgs]:
            switch (verb):
                match =="run":
                    def fold := if (args.isEmpty()) { nil } else {
                        var rv := nil
                        for x in (args.reverse()) { rv := cons(x, rv) }
                        rv
                    }
                    object foldList as stamp:
                        to isEmpty() :Bool:
                            return isNil(fold)
                        to size() :Int:
                            return fold(size)
                        to _makeIterator():
                            return iterate(makeList, fold)

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
