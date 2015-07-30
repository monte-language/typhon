def unreserved := b`ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~/`.asSet()
def percent := 0x25
def hexDigits := b`0123456789abcdef`
def digitToInt := [for i => b in (hexDigits) b => i] | [for i => b in (b`ABCDEF`) b => i + 10]

def percentEncode(s :Str) :Bytes:
    def rv := [].diverge()
    # XXX for c :(Int < 256) in s:
    for c in s:
        def i := c.asInteger()
        if (unreserved.contains(i)):
            rv.push(i)
        else:
            rv.push(percent)
            rv.push(hexDigits[i >> 4])
            rv.push(hexDigits[i & 0xf])
    return rv.snapshot()

def testPercentEncode(assert):
    assert.equal(percentEncode("/test stuff"), b`/test%20stuff`)

unittest([testPercentEncode])

def percentDecode(bs :Bytes) :Str:
    def rv := [].diverge()
    var i := 0
    while (i < bs.size()):
        switch (bs[i]):
            match ==percent:
                i += 1
                def upper := digitToInt[bs[i]]
                i += 1
                def lower := digitToInt[bs[i]]
                rv.push('\x00' + (upper << 4) + lower)
            match b:
                rv.push('\x00' + b)
        i += 1
    return "".join([for c in (rv) c.asString()])

def testPercentDecode(assert):
    assert.equal(percentDecode(b`/test%20stuff`), "/test stuff")

unittest([testPercentDecode])

[=> percentDecode, => percentEncode]
