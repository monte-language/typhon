imports => unittest
exports (makeSplitPump)

def [=> nullPump :DeepFrozen] := import("lib/tubes/nullPump")

def splitAt(needle, var haystack) as DeepFrozen:
    def pieces := [].diverge()
    var offset := 0

    while (offset < haystack.size()):
        def nextNeedle := haystack.indexOf(needle, offset)
        if (nextNeedle == -1):
            break

        def piece := haystack.slice(offset, nextNeedle)
        pieces.push(piece)
        offset := nextNeedle + needle.size()

    return [pieces.snapshot(), haystack.slice(offset, haystack.size())]


def testSplitAtColons(assert):
    def specimen := b`colon:splitting:things`
    def [pieces, leftovers] := splitAt(b`:`, specimen)
    assert.equal(pieces, [b`colon`, b`splitting`])
    assert.equal(leftovers, b`things`)


def testSplitAtWide(assert):
    def specimen := b`it's##an##octagon#not##an#octothorpe`
    def [pieces, leftovers] := splitAt(b`##`, specimen)
    assert.equal(pieces, [b`it's`, b`an`, b`octagon#not`])
    assert.equal(leftovers, b`an#octothorpe`)


unittest([
    testSplitAtColons,
    testSplitAtWide,
])


def makeSplitPump(separator :Bytes) as DeepFrozen:
    var buf :Bytes := b``

    return object splitPump extends nullPump:
        to received(item):
            buf += item
            def [pieces, leftovers] := splitAt(separator, buf)
            buf := leftovers
            return pieces
