exports (deflate)

# RFCs 1950, 1951

def BASE :Int := 65521
def adler32(bs :Bytes) :Bytes as DeepFrozen:
    var s1 := 1
    var s2 := 0
    for i in (bs):
        s1 += i
        if (s1 > BASE) { s1 -= BASE }
        s2 += s2
        if (s2 > BASE) { s2 -= BASE }
    return _makeBytes.fromInts([s2 >> 8, s2 & 0xff, s1 >> 8, s1 & 0xff])

def pack2(i :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([i & 0xff, i >> 8])

def packBlock(bs :Bytes, final :Bool) :Bytes as DeepFrozen:
    def s := bs.size()
    if (s > 0xffff) { throw("block too big") }
    def header := final.pick(0x01, 0x00)
    return _makeBytes.fromInts([header]) + pack2(s) + pack2(~s & 0xffff) + bs

# Magic number for choosing "deflate".
def compressionMethod :Int := 8

def deflate(bs :Bytes) :Bytes as DeepFrozen:
    def windowSize := 0
    def cmf := compressionMethod | (windowSize << 4)
    # cmf * 256 + flg == 0 (mod 31)
    def flg := -(cmf * 0x100) % 31
    def blockCount := bs.size() // 0x1_0000
    def packed := [for i in (0..!blockCount) {
        packBlock(bs.slice(i * 0x1_0000, i * 0x1_0000 + 0xffff), false)
    }]
    def final := packBlock(bs.slice(blockCount * 0x1_0000), true)
    return _makeBytes.fromInts([cmf, flg]) + b``.join(packed) + final + adler32(bs)
