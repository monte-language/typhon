import "capn/bootstrap" =~ [=> builder :DeepFrozen]
import "lib/capn" =~ [=> makeMessageReader :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (main)

"This is the tool for generating a Monte module containing a reader and writer
for a given capn schema."


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

def shortName(node) as DeepFrozen:
    "Return a node name without the FQN prefix."
    def displayName := node.displayName()
    return displayName.slice(node.displayNamePrefixLength(),
                             displayName.size())

def buildStructReader(nodeMap, node ? (node._which() == 1), groups) as DeepFrozen:
    "Generate the code for reading a single capn structure."
    def struct := node.struct()
    def [whichExpr, whichMeths] := if (struct.discriminantCount() != 0) {
        def d := m`def which :Int := ${getWord(struct.discriminantOffset(), 16)}`
        def meth := m`method _which() { which }`
        [d, [meth]]
    } else { [m`null`, []] }
    def fields := struct.fields()
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
                        def innerType := type.list().elementType()
                        def innerExpr := switch (innerType._which()) {
                            match ==16 {
                                def n := shortName(nodeMap[innerType.struct().typeId()])
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
                        def n := shortName(nodeMap[type.struct().typeId()])
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
                def [groupNode, groupGroups] := groups[group.typeId()]
                buildStructReader(nodeMap, groupNode, groupGroups)
            }
        }
        astBuilder."Method"(null, name, [], [], null, body, null)
    }]
    def script := astBuilder.Script(null, accessors + whichMeths, [], null)
    def patt := astBuilder.FinalPattern(astBuilder.NounExpr(node.displayName(), null),
                                        null, null)
    def structObj := astBuilder.ObjectExpr(null, patt, m`DeepFrozen`, [],
                                        script, null)
    return m`{
        $whichExpr
        $structObj
    }`

def bootstrap(bs :Bytes) as DeepFrozen:
    "Reads the schema-definition schema. Reassembles node structure then uses
    the schema builder to generate methods for reader and writer
    objects. Returns an AST for a module containing reader and writer."

    def root := makeMessageReader(bs).getRoot()
    def cgr := builder.CodeGeneratorRequest(root)
    def nodeMap := [for node in (cgr.nodes()) node.id() => node]
    def childrenOf(parentId):
        return [for id => node in (nodeMap) ? (node._which() == 1 &&
                    node.struct().isGroup() && node.scopeId() == parentId)
                id => [node, childrenOf(id)]]
    def nodeTree := [for id => node in (nodeMap) ? (node._which() == 1 &&
        !node.struct().isGroup()) id => [node, childrenOf(id)]]
    def readerNodes := [for [node, groups] in (nodeTree)
                  astBuilder."Method"(null, shortName(node),
                                      [mpatt`root :DeepFrozen`], [], null,
                                      buildStructReader(nodeMap, node, groups),
                                      null)]
    def readerObj := astBuilder.ObjectExpr(
        null,
        mpatt`reader`,
        m`DeepFrozen`,
        [],
        astBuilder.Script(null, readerNodes, [], null),
        null)
    def module := m`object _ as DeepFrozen {
        method dependencies() :List[Str] { ["lib/capn"] }
        method run(package) :Map[Str, DeepFrozen] {
            def [=> makeMessageReader :DeepFrozen, => text :DeepFrozen] | _ := package."import"("lib/capn")
            $readerObj
            [=> reader, builder => reader]
        }
    }`
    return module

def compile(bs :Bytes) :Bytes as DeepFrozen:
    "Generate code from capn schema. Build AST and dump as MAST."
    def expr := bootstrap(bs)
    def mast := makeMASTContext()
    mast(expr.expand())
    return mast.bytes()

def main(_argv, => stdio) :Vow[Int] as DeepFrozen:
    "Compile a schema in capn message format from stdin, write MAST to stdout."
    return when (def input := collectBytes(stdio.stdin())) ->
        def stdout := stdio.stdout()
        def output :Bytes := compile(input)
        when (stdout(output), stdout<-complete()) -> { 0 }
