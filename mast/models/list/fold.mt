import "unittest" =~ [=> unittest :Any]
import "tests/makeList" =~ [=> testMakeList]
exports (authorMakeList)

# Encoding lists as universal folds.

def nil(f) as DeepFrozen:
    return f.Nil()

def cons(x, xs) as DeepFrozen:
    return fn f { f.Cons(x, xs(f)) }

def isNil(f) :Bool as DeepFrozen:
    return f(object isNilChecker {
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

def iterate(var f) as DeepFrozen:
    var i :Int := 0
    return def listIterator.next(ej):
        if (isNil(f)):
            throw.eject(ej, "end of iteration")
        var val := null;
        f(object unfolder {
            to Nil() { return nil }
            to Cons(x, xs) {val := x; f := xs; return cons(x, xs)}
        })
        def rv := [i, val]
        i += 1
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
                            return iterate(fold)

interface TestStamp {}

def testListIterator(assert):
    def makeList := authorMakeList(TestStamp)
    def l := makeList(2, 2, 2)
    def result := [for i => x in (l) [i, x]]
    def expected := [[0, 2], [1, 2], [2, 2]]
    assert.equal(result, expected)

def suite := [
    testListIterator,
]

unittest(suite)

unittest(testMakeList(authorMakeList(TestStamp)))
