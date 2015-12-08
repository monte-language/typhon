imports
exports (makeUTF8DecodePump, makeUTF8EncodePump)

def [=> UTF8 :DeepFrozen] | _ := import.script("lib/codec/utf8")
def [=> nullPump :DeepFrozen] | _ := import.script("lib/tubes/nullPump")
def [=> makeMapPump :DeepFrozen] | _ := import.script("lib/tubes/mapPump")

def makeUTF8DecodePump() as DeepFrozen:
    var buf :Bytes := b``

    return object UTF8DecodePump extends nullPump:
        to received(bs :Bytes) :List[Str]:
            buf += bs
            def [s, leftovers] := UTF8.decodeExtras(buf, null)
            buf := leftovers
            return if (s.size() != 0) {[s]} else {[]}

def makeUTF8EncodePump() as DeepFrozen:
    return makeMapPump(fn s {UTF8.encode(s, null)})
