def [=> Bytes, "b" => b__quasiParser] := import("lib/bytes")

def charsToInt(cs :Bytes) :int:
    var rv :int := 0
    for c in cs:
        rv := rv * 10 + (c - 48)
    return rv

def toNetstring(cs :Bytes) :Bytes:
    def header := [c.asInteger() for c in cs.size().toString()]
    return b`$header:$cs,`

def findNetstring(cs :Bytes):
    def colon :int := cs.indexOf(':'.asInteger())
    if (colon == -1):
        return null

    def size := charsToInt(cs.slice(0, colon))
    def end := colon + 1 + size
    if (cs.size() < end):
        return null

    return [cs.slice(colon + 1, end), end + 1]

def testToNetstringEmpty(assert):
    assert.equal(b`0:,`, toNetstring([]))

def testToNetstring(assert):
    assert.equal(b`3:123,`, toNetstring(b`123`))

def testFindNetstringEmpty(assert):
    assert.equal([[], 3], findNetstring(b`0:,`))

def testFindNetstring(assert):
    assert.equal([b`hello world!`, 16], findNetstring(b`12:hello world!,`))

unittest([
    testToNetstringEmpty,
    testToNetstring,
    testFindNetstringEmpty,
    testFindNetstring,
])
