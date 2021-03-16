import "unittest" =~ [=> unittest :Any]
import "lib/proptests" =~ [=> arb, => prop]
exports (Base64)

def table :Str := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
def untable :Map[Char, Int] := [for i => c in (table) c => i].with('=', -1)

def padSlice(bs :Bytes) :Str as DeepFrozen:
    return _makeStr.fromChars(if (bs.size() == 2) {
        [
            table[bs[0] >> 2],
            table[((bs[0] & 0x3) << 4) | (bs[1] >> 4)],
            table[(bs[1] & 0xf) << 2],
            '=',
        ]
    } else if (bs.size() == 1) {
        [
            table[bs[0] >> 2],
            table[(bs[0] & 0x3) << 4],
            '=',
            '=',
        ]
    })

def finishThree(i1 :Int, i2 :Int, i3 :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([
        (i1 << 2) | (i2 >> 4),
        ((i2 & 0xf) << 4) | (i3 >> 2),
    ])

def finishTwo(i1 :Int, i2 :Int) :Bytes as DeepFrozen:
    return _makeBytes.fromInts([
        (i1 << 2) | (i2 >> 4),
    ])

object Base64 as DeepFrozen:
    "The standard Base64 armor for binary data."

    to decode(specimen, ej) :Bytes:
        def s :Str exit ej := specimen

        return b``.join([for i in (0..!(s.size() // 4)) {
            def [i1, i2, i3, i4] := [for c in (s.slice(i * 4, (i + 1) * 4)) untable[c]]
            if (i3 == -1) {
                finishTwo(i1, i2)
            } else if (i4 == -1) {
                finishThree(i1, i2, i3)
            } else {
                _makeBytes.fromInts([
                    (i1 << 2) | (i2 >> 4),
                    ((i2 & 0xf) << 4) | (i3 >> 2),
                    ((i3 & 0x3) << 6) | i4,
                ])
            }
        }])

    to encode(specimen, ej) :Str:
        def bs :Bytes exit ej := specimen

        return "".join([for i in (0..!((bs.size() + 2) // 3)) {
            def slice := bs.slice(i * 3, (i + 1) * 3)
            if (slice.size() == 3) {
                def cs := [
                    slice[0] >> 2,
                    ((slice[0] & 0x3) << 4) | (slice[1] >> 4),
                    ((slice[1] & 0xf) << 2) | (slice[2] >> 6),
                    slice[2] & 0x3f,
                ]
                _makeStr.fromChars([for c in (cs) table[c]])
            } else { padSlice(slice) }
        }])

def testBase64RoundTrip(hy, bs):
    def rt := Base64.decode(Base64.encode(bs, null), null)
    hy.sameEver(bs, rt)

unittest([
    prop.test([arb.Bytes()], testBase64RoundTrip),
])
