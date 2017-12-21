import "unittest" =~ [=> unittest :Any]
exports (zip)

# A prelude-safe library of tools for working with iterators.

object noPadding as DeepFrozen {}

def makeZipper(iterables :List, padding) as DeepFrozen:
    def iterators := [for iterable in (iterables) iterable._makeIterator()]
    return if (padding == noPadding):
        def truncatingZippingIterator.next(ej) :Pair[List, List]:
            def ks := [].diverge()
            def vs := [].diverge()
            for iterator in (iterators):
                def [k, v] := iterator.next(ej)
                ks.push(k)
                vs.push(v)
            return [ks.snapshot(), vs.snapshot()]
    else:
        # Flag for figuring out whether we're finished with iteration.
        var finished :Bool := true
        def paddingZippingIterator.next(ej) :Pair[List, List]:
            finished := true
            def ks := [].diverge()
            def vs := [].diverge()
            for iterator in (iterators):
                escape needsPadding:
                    def [k, v] := iterator.next(needsPadding)
                    finished := false
                    ks.push(k)
                    vs.push(v)
                catch _:
                    ks.push(padding)
                    vs.push(padding)
            if (finished):
                ej("Iteration finished")
            return [ks.snapshot(), vs.snapshot()]

def allSameLength(iterables) :Bool as DeepFrozen:
    def ej := __return
    def trySize(i):
        return try { i.size() } catch _ {
            traceln("zip: Couldn't tell size of iterable")
            ej(true)
        }
    if (iterables =~ [head] + tail):
        def headSize := trySize(head)
        for t in (tail):
            if (headSize != trySize(t)):
                return false
        return true
    else:
        return true

object zip as DeepFrozen:
    "
    Turn a list of iterables into an iterable of lists.

    Also known as a transposition or a convolution.
    "

    match [=="run", iterables ? (allSameLength(iterables)), _]:
        def zipped._makeIterator():
            "
            A zipping iterator.

            This iterator has made a sincere effort to ensure that it will not
            run ragged.
            "

            return makeZipper(iterables, noPadding)

    match [=="ragged", iterables, [=> padding := noPadding] | _]:
        def zippedRagged._makeIterator():
            "A ragged zipping iterator."

            return makeZipper(iterables, padding)

def testZipLists(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10]
    def expected := [[1, 6], [2, 7], [3, 8], [4, 9], [5, 10]]
    assert.equal(_makeList.fromIterable(zip(l, r)), expected)

def testZipListsSameLengthCheck(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10, 11]
    assert.throws(fn { _makeList.fromIterable(zip(l, r)) })

def testZipListsRagged(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10, 11]
    def expected := [[1, 6], [2, 7], [3, 8], [4, 9], [5, 10]]
    assert.equal(_makeList.fromIterable(zip.ragged(l, r)), expected)

def testZipListsRaggedPadding(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10, 11]
    def padding := 42
    def expected := [[1, 6], [2, 7], [3, 8], [4, 9], [5, 10], [42, 11]]
    assert.equal(_makeList.fromIterable(zip.ragged(l, r, => padding)),
                 expected)

unittest([
    testZipLists,
    testZipListsSameLengthCheck,
    testZipListsRagged,
    testZipListsRaggedPadding,
])


object async as DeepFrozen:
    "Various asynchronous iteration combinators."

    to "for"(iterable, body) :Vow[Void]:
        "An asynchronous for-loop."

        def iter := iterable._makeIterator()

        def go():
            return escape ej:
                def [k, v] := iter.next(ej)
                when (body(k, v)) -> { go() }
            catch _:
                null

        return go()

    to "while"(test, body) :Vow[Void]:
        "An asynchronous while-loop."

        def go():
            return if (test()):
                when (body()) -> { go() }
            else:
                null

        return go()

def testAsyncFor(assert):
    def l := [1, 2, 3]
    var acc := 0
    return when (async."for"(l, fn _, v { acc += v })) ->
        assert.equal(acc, 6)

def testAsyncWhile(assert):
    var acc := 0
    return when (async."while"(fn { acc < 6 }, fn { acc += 1 })) ->
        assert.equal(acc, 6)

unittest([
    testAsyncFor,
    testAsyncWhile,
])
