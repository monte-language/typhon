def [=> UTF8] | _ := import("lib/codec/utf8")
def [=> nullPump] | _ := import("lib/tubes/nullPump")
def [=> makeMapPump] | _ := import("lib/tubes/mapPump")

def makeUTF8DecodePump():
    var buf :Bytes := []

    return object UTF8DecodePump extends nullPump:
        to received(bs :Bytes) :List[Str]:
            buf += bs
            def [s, leftovers] := UTF8.decodeExtras(buf, null)
            buf := leftovers
            return if (s.size() != 0) {[s]} else {[]}

def makeUTF8EncodePump():
    return makeMapPump(fn s {UTF8.encode(s, null)})

[
    => makeUTF8DecodePump,
    => makeUTF8EncodePump,
]
