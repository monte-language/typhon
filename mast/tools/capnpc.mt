import "capn/bootstrap" =~ [=> CodeGeneratorRequest :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (main)

def typeWidths :List[Pair[Int, Bool]] := [
    # void
    [0, true],
    # bool
    [1, true],
    # int8
    [8, true],
    # int16
    [16, true],
    # int32
    [32, true],
    # int64
    [64, true],
    # uint8
    [8, true],
    # uint16
    [16, true],
    # uint32
    [32, true],
    # uint64
    [64, true],
    # float32
    [32, true],
    # float64
    [64, true],
    # text
    [1, false],
    # data
    [1, false],
    # list
    [1, false],
    # XXX enums
    [16, true],
    # struct
    [1, false],
    # interface
    [1, false],
    # anyPointer
    [1, false],
]

def getWord(offset :Int, width :Int, => signed :Bool := false) as DeepFrozen:
    def fullOffset := offset * width
    def slot := fullOffset // 64
    def shift := fullOffset % 64
    var expr := m`root.getWord(${astBuilder.LiteralExpr(slot, null)})`
    if (shift != 0):
        def shiftLit := astBuilder.LiteralExpr(shift, null)
        expr := m`$expr >> $shiftLit`
    if (width != 64):
        def mask := astBuilder.LiteralExpr(2 ** width - 1, null)
        expr := m`$expr & $mask`
    if (signed):
        def widthLit := astBuilder.LiteralExpr(2 ** width, null)
        expr := m`$expr - $widthLit & -$widthLit`
    return expr

def getPointer(offset :Int) as DeepFrozen:
    return m`root.getPointer(${astBuilder.LiteralExpr(offset, null)})`

def bootstrap(bs :Bytes) as DeepFrozen:
    def cgr := CodeGeneratorRequest.unpack(bs)
    def nodeNames := [for node in (cgr.nodes()) node.id() => {
        def displayName := node.displayName()
        displayName.slice(node.displayNameLengthPrefix(), displayName.size())
    }]
    def nodes := [for node in (cgr.nodes()) {
        def displayName := node.displayName()
        def shortName := displayName.slice(node.displayNameLengthPrefix(),
                                           displayName.size())
        traceln(node.id(), displayName, shortName, node._which())
        def noun := astBuilder.NounExpr(shortName, null)
        def maker := if (node._which() == 1) {
            def fields := node.fields()
            def accessors := [for field in (fields) {
                def name := field.name()
                def body := if (field._which() != 0) { m`null` } else {
                    def slot := field.slot()
                    def type := slot.type()
                    def [width, isData] := typeWidths[type._which()]
                    def offset := slot.offset()
                    traceln(`field $name offset $offset width $width isData $isData`)
                    switch (type._which()) {
                        match ==0 { m`null` }
                        match ==1 { m`${getWord(offset, 1)} == 1` }
                        match ==2 { getWord(offset, 8, "signed" => true) }
                        match ==3 { getWord(offset, 16, "signed" => true) }
                        match ==4 { getWord(offset, 32, "signed" => true) }
                        match ==5 { getWord(offset, 64, "signed" => true) }
                        match ==6 { getWord(offset, 8) }
                        match ==7 { getWord(offset, 16) }
                        match ==8 { getWord(offset, 32) }
                        match ==9 { getWord(offset, 64) }
                        # XXX floats?
                        match ==10 { m`null` }
                        match ==11 { m`null` }
                        match ==12 { m`text(${getPointer(offset)})` }
                        # XXX ???
                        match ==13 { m`null` }
                        match ==14 {
                            def innerType := type.elementType()
                            def innerExpr := switch (innerType._which()) {
                                match ==16 {
                                    def n := nodeNames[innerType.typeId()]
                                    astBuilder.NounExpr(n, null)
                                }
                            }
                            m`[for r in (${getPointer(offset)}) $innerExpr(r)]`
                        }
                        # XXX enums?
                        match ==15 { m`null` }
                        match ==16 {
                            def n := nodeNames[type.typeId()]
                            def expr := astBuilder.NounExpr(n, null)
                            m`$expr(${getPointer(offset)})`
                        }
                        # XXX ???
                        match ==18 { m`null` }
                    }
                }
                astBuilder."Method"(null, name, [], [], null, body, null)
            }]
            traceln(`made accessors $accessors`)
            def script := astBuilder.Script(null, accessors, [], null)
            def patt := astBuilder.FinalPattern(astBuilder.NounExpr(displayName, null),
                                                null, null)
            def struct := astBuilder.ObjectExpr(null, patt, m`DeepFrozen`, [],
                                                script, null)
            m`object $noun as DeepFrozen {
                method unpack(bs :Bytes) {
                    $noun.fromRoot(makeMessage(bs).getRoot())
                }
                method fromRoot(root :DeepFrozen) { $struct }
            }`
        } else {
            m`object $noun as DeepFrozen {}`
        }
        [maker, noun]
    }]
    def listPatt := astBuilder.ListPattern(
        [for [_, ex] in (nodes) astBuilder.FinalPattern(ex, null, null)],
        null, null)
    def listExpr := astBuilder.ListExpr([for [obj, _] in (nodes) obj], null)
    def body := m`def $listPatt := $listExpr`
    def exportExpr := astBuilder.MapExpr(
        [for [_, ex] in (nodes) astBuilder.MapExprExport(ex, null)], null)
    def module := m`object _ as DeepFrozen {
        method dependencies() :List[Str] { ["lib/codec/utf8", "lib/capn"] }
        method run(package) :Map[Str, DeepFrozen] { $body; $exportExpr }
    }`
    return module

def compile(bs :Bytes) :Bytes as DeepFrozen:
    def expr := bootstrap(bs)
    def mast := makeMASTContext()
    mast(expr.expand())
    return mast.bytes()

def main(_argv, => stdio) :Vow[Int] as DeepFrozen:
    return when (def input := collectBytes(stdio.stdin())) ->
        def stdout := stdio.stdout()
        def output :Bytes := compile(input)
        when (stdout(output), stdout<-complete()) -> { 0 }
