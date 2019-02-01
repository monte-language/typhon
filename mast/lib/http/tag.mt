import "unittest" =~ [=> unittest :Any]
exports (tag)

# This table is only sufficient for handling tag bodies. It cannot fix up tag
# attributes. See https://wonko.com/post/html-escaping for details. ~ C.
def entities :Map[Str, Str] := [
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "'" => "&apos;",
    "\"" => "&quot;",
    # MSIE only: Backticks are legal quote characters!
    "`" => "&#096;",
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

def escapeFragment(fragment) :DeepFrozen as DeepFrozen:
    return if (fragment =~ via (escapeEntities) s :Str) { s } else { fragment }

object tag as DeepFrozen:
    match [tagType :Str, pieces, namedArgs]:
        def allPieces := flatten(pieces)
        def fragments :List[DeepFrozen] := [for piece in (allPieces)
                                            escapeFragment(piece)]
        def attributes :Map[Str, Str] := [for k => v in (namedArgs)
                                          ? (k =~ sk :Str && v =~ sv :Str)
                                          sk => sv]

        def &repr := makeLazySlot(fn {
            def attrStr := "".join([for k => v in (attributes) `$k="$v"`])
            if (fragments.isEmpty()) { `<$tagType $attrStr />` } else {
                def head := if (attributes.isEmpty()) { `<$tagType>` } else {
                    `<$tagType $attrStr>`
                }
                def frags := "".join([for f in (fragments) M.toString(f)])
                head + frags + `</$tagType>`
            }
        }, "guard" => Str)
        object HTMLTag as DeepFrozen:
            to _printOn(out):
                out.print(repr)

            to asStr() :Str:
                return repr

def testHTMLTagNest(assert):
    def t := tag.h1(tag.p("test"))
    assert.equal(t.asStr(), "<h1><p>test</p></h1>")

def testHTMLTagEscape(assert):
    def t := tag.p("<blink/>")
    assert.equal(t.asStr(), "<p>&lt;blink/&gt;</p>")

def testHTMLTagEscapeMSIE(assert):
    def t := tag.p("superhero: the `")
    assert.equal(t.asStr(), "<p>superhero: the &#096;</p>")

unittest([
    testHTMLTagNest,
    testHTMLTagEscape,
    testHTMLTagEscapeMSIE,
])
