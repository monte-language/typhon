def entities :Map[Str, Str] := [
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "'" => "&apos;",
    "\"" => "&quot;",
]

def escapeEntities(specimen, ej) :Str as DeepFrozen:
    def unescaped :Str exit ej := specimen
    var escaped := unescaped
    for needle => entity in entities:
        escaped replace= (needle, entity)
    return escaped

def escapeFragment(fragment) as DeepFrozen:
    switch (fragment):
        match via (escapeEntities) s :Str:
            return s
        match someTag:
            return someTag

object tag as DeepFrozen:
    match [tagType, pieces, _]:
        def fragments := [for piece in (pieces) escapeFragment(piece)]
        object HTMLTag:
            to _printOn(out):
                if (fragments.size() == 0):
                    out.print(`<$tagType />`)
                else:
                    out.print(`<$tagType>`)
                    for fragment in fragments:
                        out.print(`$fragment`)
                    out.print(`</$tagType>`)

[=> tag]
