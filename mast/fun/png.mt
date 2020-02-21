import "fun/deflate" =~ [=> deflate]
exports (chunkType, CRC32, chunksOf, makePNG)

# http://www.libpng.org/pub/png/spec/1.2/PNG-Chunks.html

def fifthBitUnset(c :Int) :Bool as DeepFrozen:
    return (c & (1 << 5)).isZero()

object chunkType as DeepFrozen:
    to isCritical(type :Bytes) :Bool:
        return fifthBitUnset(type[0])

    to isPublic(type :Bytes) :Bool:
        return fifthBitUnset(type[1])

    to isSafeToCopy(type :Bytes) :Bool:
        return fifthBitUnset(type[3])

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

def Int4 :DeepFrozen := 0..!0x1_0000_0000
def pack4(i :Int4) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([
        (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff,
    ])

def buildChunk(ty :Bytes, chunk :Bytes) :Bytes as DeepFrozen:
    def length := pack4(chunk.size())
    def body := ty + chunk
    def crc := pack4(CRC32(body))
    return length + body + crc

object makePNG as DeepFrozen:
    to fromChunks(chunkIterator) :Bytes:
        "
        Build a PNG from an iterator of PNG chunks.

        The iterator ought to return pairs of Bytes to Bytes, with the keys
        being PNG chunk headers like IHDR or IDAT, and the values being the
        chunk bodies.
        "
        def chunks := [PNGMagic].diverge()
        for ty => chunk in (chunkIterator):
            chunks.push(buildChunk(ty, chunk))
        return b``.join(chunks)

    to drawingFrom(d):
        "
        Draw from drawable/shader `d` repeatedly to form an image.
        "
        return def draw(width :Int4, height :Int4):
            # Width, height, bit depth, color type, compression, filter,
            # interlace
            def ihdr := pack4(width) + pack4(height) + _makeBytes.fromInts([
                # XXX as soon as possible, implement interlacing
                16, 6, 0, 0, 0,
            ])
            def body := [].diverge(0..!256)
            def push(chan :Double):
                # Simplest arrangement that will handle infinity
                # correctly.
                def c := (0xffff * chan).floor().min(0xffff)
                body.push(c >> 8)
                body.push(c & 0xff)

            def aspectRatio :Double := width / height
            for h in (0..!height):
                # Filter type for this scanline: 0 for no filtering.
                body.push(0)
                for w in (0..!width):
                    def color := d.drawAt(w / width, h / height, => aspectRatio)
                    # Kludge: Color is premultiplied, but PNG stores colors
                    # unpremultiplied. Fortunately, alpha is a Double and we
                    # can recover the original color with negligible loss.
                    def [r, g, b, a] := color.sRGB()
                    # Don't divide by zero; it'll NaN. Instead, think: If
                    # alpha is zero, then we can pick an arbitrary color.
                    # The PNG specification asks that we pick black, which is
                    # encoded as all zeroes.
                    if (a.isZero()):
                        body.extend([0] * 2 * 4)
                    else:
                        for chan in ([r, g, b]):
                            push(chan * a.reciprocal())
                        push(a)
            def idat := deflate(_makeBytes.fromInts(body))

            return makePNG.fromChunks([
                b`IHDR` => ihdr,
                # NB: We don't emit compatibility gAMA or cHRM; too much work
                # to emit fixed values from the specification. We also don't
                # have a strong preference as to how our sRGB values will be
                # interpreted.
                b`sRGB` => b`$\x00`,
                b`IDAT` => idat,
                b`IEND` => b``,
            ])
