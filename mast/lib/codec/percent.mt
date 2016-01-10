import "unittest" =~ [=> unittest]
exports (PercentEncoding)

def unreserved :Set[Int] := b`ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/`.asSet()
def percent :Int := 0x25
def hexDigits :Bytes := b`0123456789abcdef`
def digitToInt :Map[Int, Int] := [for i => b in (hexDigits) b => i] | [for i => b in (b`ABCDEF`) b => i + 10]

object PercentEncoding as DeepFrozen:
    "Percent-encoding as per RFC 3986."

    to encode(bs :Bytes, _) :Bytes:
        var rv := b``
        for i in bs:
            if (unreserved.contains(i)):
                rv with= (i)
            else:
                rv with= (percent)
                rv with= (hexDigits[i >> 4])
                rv with= (hexDigits[i & 0xf])
        return rv

    to decode(bs :Bytes, _) :Bytes:
        def rv := [].diverge()
        var i := 0
        while (i < bs.size()):
            switch (bs[i]):
                match ==percent:
                    i += 1
                    def upper := digitToInt[bs[i]]
                    i += 1
                    def lower := digitToInt[bs[i]]
                    rv.push((upper << 4) + lower)
                match b:
                    rv.push(b)
            i += 1
        return _makeBytes.fromInts(rv)

def testPercentEncode(assert):
    assert.equal(PercentEncoding.encode(b`/test stuff`, null),
                 b`/test%20stuff`)

def testPercentDecode(assert):
    assert.equal(PercentEncoding.decode(b`/test%20stuff`, null),
                 b`/test stuff`)

unittest([
    testPercentEncode,
    testPercentDecode,
])
