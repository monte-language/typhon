exports (adler32, deflate)

# RFCs 1950, 1951

# Adler's own tools at https://github.com/madler/infgen/ are very useful.

def BASE :Int := 65521
def adler32(bs :Bytes) :Int as DeepFrozen:
    var s1 := 1
    var s2 := 0
    for i in (bs):
        s1 += i
        if (s1 >= BASE) { s1 -= BASE }
        s2 += s1
        if (s2 >= BASE) { s2 -= BASE }
    return (s2 << 16) | s1

def pack4be(i :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts(
        [i >> 24, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff])

def pack2le(i :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([i & 0xff, i >> 8])

def packBlock(bs :Bytes, final :Bool) :Bytes as DeepFrozen:
    def s := bs.size()
    if (s > 0xffff) { throw("block too big") }
    def header := final.pick(0x01, 0x00)
    return _makeBytes.fromInts([header]) + pack2le(s) + pack2le(~s & 0xffff) + bs

# Magic number for choosing "deflate".
def compressionMethod :Int := 8

# Block size. Cannot be larger than 0xffff.
def blockSize :Int := 0xffff

def deflate(bs :Bytes) :Bytes as DeepFrozen:
    def windowSize := 0
    def cmf := compressionMethod | (windowSize << 4)
    # cmf * 256 + flg == 0 (mod 31)
    def flg := -(cmf * 0x100) % 31
    def blockCount := bs.size() // blockSize
    def packed := [for i in (0..!blockCount) {
        packBlock(bs.slice(i * blockSize, (i + 1) * blockSize), false)
    }]
    def final := packBlock(bs.slice(blockCount * blockSize), true)
    return _makeBytes.fromInts([cmf, flg]) + b``.join(packed) + final + pack4be(adler32(bs))
