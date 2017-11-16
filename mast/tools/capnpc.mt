import "capn/bootstrap" =~ [=> builder :DeepFrozen]
import "lib/capn" =~ [=> makeMessage :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (main)

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
    def root := makeMessage(bs).getRoot()
    def cgr := builder.CodeGeneratorRequest(root)
    def nodeNames := [for node in (cgr.nodes()) node.id() => {
        def displayName := node.displayName()
        displayName.slice(node.displayNameLengthPrefix(), displayName.size())
    }]
    def nodes := [for node in (cgr.nodes()) ? (node._which() == 1) {
        def displayName := node.displayName()
        def shortName := displayName.slice(node.displayNameLengthPrefix(),
                                           displayName.size())
        def fields := node.fields()
        def accessors := [for field in (fields) {
            def name := field.name()
            def body := switch (field._which()) {
                match ==0 {
                    def slot := field.slot()
                    def type := slot.type()
                    def offset := slot.offset()
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
                                    astBuilder.MethodCallExpr(m`builder`, n,
                                                              [m`r`], [],
                                                              null)
                                }
                            }
                            m`[for r in (${getPointer(offset)}) $innerExpr]`
                        }
                        # XXX enums?
                        match ==15 { m`null` }
                        match ==16 {
                            def n := nodeNames[type.typeId()]
                            astBuilder.MethodCallExpr(m`builder`, n,
                                                      [getPointer(offset)],
                                                      [], null)
                        }
                        # XXX ???
                        match ==18 { m`null` }
                    }
                }
                match ==1 {
                    def group := field.group()
                    def n := nodeNames[group.typeId()]
                    astBuilder.MethodCallExpr(m`builder`, n, [m`root`], [],
                                              null)
                }
            }
            astBuilder."Method"(null, name, [], [], null, body, null)
        }]
        def script := astBuilder.Script(null, accessors, [], null)
        def patt := astBuilder.FinalPattern(astBuilder.NounExpr(displayName, null),
                                            null, null)
        def struct := astBuilder.ObjectExpr(null, patt, m`DeepFrozen`, [],
                                            script, null)
        astBuilder."Method"(null, shortName, [mpatt`root :DeepFrozen`],
                            [], null, struct, null)
    }]
    def script := astBuilder.Script(null, nodes, [], null)
    def builderObj := astBuilder.ObjectExpr(null, mpatt`builder`,
                                            m`DeepFrozen`, [], script, null)
    def module := m`object _ as DeepFrozen {
        method dependencies() :List[Str] { ["lib/capn"] }
        method run(package) :Map[Str, DeepFrozen] {
            def [=> makeMessage :DeepFrozen, => text :DeepFrozen] | _ := package."import"("lib/capn")
            $builderObj
            [=> builder]
        }
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
