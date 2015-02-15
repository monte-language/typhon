def [=> simple__quasiParser] | _ := import("lib/simple")

# TODO: How to guard on iterable?
def comp(src):

    return object compObject:
        to _makeIterator():
            def iter := src._makeIterator()
            return object compIter:
                to _makeIterator():
                    return compIter

                to next(ej):
                    return iter.next(ej)

        to map(func):
            def iter := src._makeIterator()
            object mapIter:
                to _makeIterator():
                    return mapIter

                to next(ej):
                    def [idx, val] := iter.next(ej)
                    return [idx, func(val)]
            return comp(mapIter)

        to filter(func):
            def iter := src._makeIterator()
            object filterIter:
                to _makeIterator():
                    return filterIter

                to next(ej):
                    while (true):
                        def [idx, val] := iter.next(ej)
                        if (func(val)):
                            return [idx, val]
            return comp(filterIter)

        to reduce(var memo, func):
            for val in src:
                memo := func(memo, val)
            return memo


def testIter(assert):
    def src := [1, 2, 3]
    def expected := src
    var acc := []
    for obj in comp(src):
        acc with= obj
    assert.equal(acc, src)

def testMap(assert):
    def src := [1, 2, 3]
    def expected := [2, 4, 6]
    var acc := []
    for obj in comp(src).map(fn x {x * 2}):
        acc with= obj
    assert.equal(acc, expected)

def testMapChain(assert):
    def src := [1, 2, 3]
    def expected := [3, 5, 7]
    var acc := []
    for obj in comp(src).map(fn x {x * 2}).map(fn x {x + 1}):
        acc with= obj
    assert.equal(acc, expected)

def testFilter(assert):
    def src := [1, 2, 3]
    def expected := [1, 3]
    var acc := []
    for obj in comp(src).filter(fn x {x % 2 == 1}):
        acc with= obj
    assert.equal(acc, expected)

def testReduce(assert):
    def src := [1, 2, 3]
    def res := comp(src).reduce(0, fn x, y {x + y})
    assert.equal(res, 6)

unittest([
    testIter,
    testMap,
    testMapChain,
    testFilter,
    testReduce,
])

[=> comp]
