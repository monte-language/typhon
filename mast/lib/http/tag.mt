exports (tag)

def entities :Map[Str, Str] := [
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "'" => "&apos;",
    "\"" => "&quot;",
]

def flatten(pieces) as DeepFrozen:
    var rv := []
    for piece in (pieces):
        if (piece =~ l :List):
            rv += l
        else:
            rv with= (piece)
    return rv

def escapeEntities(specimen, ej) :Str as DeepFrozen:
    def unescaped :Str exit ej := specimen
    var escaped := unescaped
    for needle => entity in (entities):
        escaped replace= (needle, entity)
    return escaped

def escapeFragment(fragment) as DeepFrozen:
    switch (fragment):
        match via (escapeEntities) s :Str:
            return s
        match someTag:
            return someTag

object tag as DeepFrozen:
    match [tagType :Str, pieces, namedArgs]:
        def allPieces := flatten(pieces)
        def fragments :List[DeepFrozen] := [for piece in (allPieces)
                                            escapeFragment(piece)]
        def attributes :Map[Str, Str] := [for k => v in (namedArgs)
                                          if (k =~ sk :Str && v =~ sv :Str)
                                          sk => sv]
        object HTMLTag as DeepFrozen:
            to _printOn(out):
                def attrStr := "".join([for k => v in (attributes) `$k="$v"`])
                if (fragments.size() == 0):
                    out.print(`<$tagType $attrStr />`)
                else:
                    if (attributes.size() == 0):
                        out.print(`<$tagType>`)
                    else:
                        out.print(`<$tagType $attrStr>`)
                    for fragment in (fragments):
                        out.print(`$fragment`)
                    out.print(`</$tagType>`)
