import "lib/pen" =~ [=> pk, => makeSlicer]
exports (Bencode)

def bracketTag(parser, tag :Bytes) as DeepFrozen:
    return pk.equals(tag[0]) >> parser << pk.equals(b`e`[0])

def makeParser() as DeepFrozen:
    def zero := b`0`[0]
    def nine := b`9`[0]
    def digit := pk.satisfies(zero..nine)
    def digits := digit.oneOrMore() % fn ds {
        var i :Int := 0
        for d in (ds) { i := i * 10 + (d - zero) }
        i
    }
    def int := (pk.equals(b`-`[0]) >> digits) % fn i { -i } / digits
    def i := bracketTag(int, b`i`)

    def bs(slicer1, ej):
        def [size :Int, slicer2] := (digits << pk.equals(b`:`[0]))(slicer1, ej)
        # XXX Too bad we can't take a slice. lib/pen doesn't support it.
        return (pk.anything() * size % _makeBytes.fromInts)(slicer2, ej)

    def val

    def list := bracketTag((pk.pure(null) >> val).zeroOrMore(), b`l`)

    def pair := (pk.pure(null) >> bs) + val
    def dict := bracketTag(pair.zeroOrMore() % _makeMap.fromPairs, b`d`)

    # Try bytestrings last; the other three start with a one-byte tag, so that
    # we should be able to quickly reject them if they're not the right
    # constructor.
    bind val := i / list / dict / bs

    return val

object Bencode as DeepFrozen:
    "Bencoding, as in BitTorrent."

    to decode(specimen, ej):
        def parser := makeParser()
        def bs :Bytes exit ej := specimen
        def slicer := makeSlicer.fromBytes(bs)
        return parser(slicer, ej)[0]

    to encode(specimen, ej):
        return switch (specimen):
            match bs :Bytes:
                b`${M.toString(bs.size())}:$bs`
            match i :Int:
                b`i${M.toString(i)}e`
            match l :List:
                def pieces := b``.join([for x in (l) Bencode.encode(x, ej)])
                b`l${pieces}e`
            match m :Map[Bytes, Any]:
                def pieces := b``.join([for k => v in (m.sortKeys())
                                        Bencode.encode(k, ej) +
                                        Bencode.encode(v, ej)])
                b`d${pieces}e`
            match _:
                throw.eject(ej, `$specimen isn't Bencodable`)
