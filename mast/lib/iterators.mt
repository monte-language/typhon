import "unittest" =~ [=> unittest]
exports (zip)

# A prelude-safe library of tools for working with iterators.

object noPadding as DeepFrozen {}

def makeZipper(iterables :List, padding) as DeepFrozen:
    def iterators := [for iterable in (iterables) iterable._makeIterator()]
    return if (padding == noPadding):
        object truncatingZippingIterator:
            to next(ej) :Pair[List, List]:
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
        object paddingZippingIterator:
            to next(ej) :Pair[List, List]:
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
    return if (iterables =~ [head] + tail):
        def headSize := trySize(head)
        for t in (tail):
            if (headSize != trySize(t)):
                break false
        true
    else:
        true

object zip as DeepFrozen:
    "
    Turn a list of iterables into an iterable of lists.

    Also known as a transposition or a convolution.
    "

    match [=="run", iterables ? (allSameLength(iterables)), _]:
        object zipped:
            "
            A zipping iterator.

            This iterator has made a sincere effort to ensure that it will not
            run ragged.
            "

            to _makeIterator():
                return makeZipper(iterables, noPadding)

    match [=="ragged", iterables, [=> padding := noPadding] | _]:
        object zippedRagged:
            "A ragged zipping iterator."

            to _makeIterator():
                return makeZipper(iterables, padding)

def testZipLists(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10]
    def expected := [[1, 6], [2, 7], [3, 8], [4, 9], [5, 10]]
    assert.equal(_makeList.fromIterable(zip(l, r)), expected)

def testZipListsSameLengthCheck(assert):
    def l := [1, 2, 3, 4, 5]
    def r := [6, 7, 8, 9, 10, 11]
    assert.throws(fn { _makeList.fromIterable(zip.ragged(l, r)) })

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