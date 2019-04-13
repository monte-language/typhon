exports (CRC32, chunksOf, packPNG)

def PNGMagic :Bytes := b`$\x89PNG$\r$\n$\x1a$\n`

def CRCTable :List[Int] := [for n in (0..!0x100) {
    var c :Int := n
    for _ in (0..!8) {
        if ((c % 2) == 1) {
            c := 0xedb88320 ^ (c >> 1)
        } else { c >>= 1 }
    }
    c
}]

def CRC32(bs :Bytes) :Int as DeepFrozen:
    var h :Int := 0xffff_ffff
    for i in (bs):
        h := CRCTable[(h ^ i) & 0xff] ^ (h >> 8)
    return h ^ 0xffff_ffff

def chunksOf(bs :Bytes) as DeepFrozen:
    return def chunkIterable._makeIterator():
        # XXX should be monotonic
        var offset :Int := 0
        def read(size :Int):
            return bs.slice(offset, offset += size)
        def long():
            var rv := 0
            for i => b in (read(4)):
                rv |= b << ((3 - i) * 8)
            return rv

        # XXX trick parser into dedent?
        if (PNGMagic != read(8)):
            throw("Bad magic signature on PNG")

        return def chunkIterator.next(ej):
            if (offset >= bs.size()):
                throw.eject(ej, "End of file")

            def length := long()
            def ty := read(4)
            def chunk := read(length)
            def crc := long()
            if (crc != CRC32(ty + chunk)):
                throw("Bad CRC on chunk")
            return [ty, chunk]

def pack(i :(0..!0x1_0000_0000)) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([
        (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff,
    ])

def buildChunk(ty :Bytes, chunk :Bytes) :Bytes as DeepFrozen:
    def length := pack(chunk.size())
    def body := ty + chunk
    def crc := pack(CRC32(body))
    return length + body + crc

def packPNG(chunkIterator) :Bytes as DeepFrozen:
    def chunks := [PNGMagic].diverge()
    for ty => chunk in (chunkIterator):
        chunks.push(buildChunk(ty, chunk))
    return b``.join(chunks)
