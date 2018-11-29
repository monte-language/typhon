import "capn/reader" =~ [=> reader :DeepFrozen]
import "lib/capn" =~ [=> makeMessageReader :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (main)

"This is the tool for generating a Monte module containing a reader and writer
for a given capn schema."
def typenames :Map[Int, Str]:= [
    0 => "void",
    1 => "bool",
    2 => "int8",
    3 => "int16",
    4 => "int32",
    5 => "int64",
    6 => "uint8",
    7 => "uint16",
    8 => "uint32",
    9 => "uint64",
    10 => "float32",
    11 => "float64",
    12 => "text",
    13 => "data",
    14 => "list",
    15 => "enum",
    16 => "struct",
    17 => "interface",
    18 => "anyPointer",
]

def LIST_SIZE_VOID :Int := 0
def LIST_SIZE_BIT :Int := 1
def LIST_SIZE_8 :Int := 2
def LIST_SIZE_16 :Int := 3
def LIST_SIZE_32 :Int := 4
def LIST_SIZE_64 :Int := 5
def LIST_SIZE_PTR :Int := 6
def LIST_SIZE_COMPOSITE :Int := 7

def sizeTags :Map[Str, Int] := [
    "void" => LIST_SIZE_VOID,
    "bool" => LIST_SIZE_BIT,
    "int8" => LIST_SIZE_8,
    "int16" => LIST_SIZE_16,
    "int32" => LIST_SIZE_32,
    "int64" => LIST_SIZE_64,
    "uint8" => LIST_SIZE_8,
    "uint16" => LIST_SIZE_16,
    "uint32" => LIST_SIZE_32,
    "uint64" => LIST_SIZE_64,
    "float32" => LIST_SIZE_32,
    "float64" => LIST_SIZE_64,
    "enum" => LIST_SIZE_16,
    "text" => LIST_SIZE_PTR,
    "data" => LIST_SIZE_PTR,
    "list" => LIST_SIZE_PTR,
    "struct" => LIST_SIZE_COMPOSITE,
    "interface" => LIST_SIZE_PTR,
    "anyPointer" => LIST_SIZE_PTR,
]

def typeSize :Map[Int, Int] := [
    0 => 0, # void
    1 => 0, # bool (just 1 bit)
    2 => 1, # int8
    3 => 2, # int16
    4 => 4, # int32
    5 => 8, # int64
    6 => 1, # uint8
    7 => 2, # uint16
    8 => 4, # uint32
    9 => 8, # uint64
    10 => 4, # float32
    11 => 8, # float64
    15 => 2, # enum
]

def L(value) as DeepFrozen:
    switch (value):
        match ==true:
            return astBuilder.NounExpr("true", null)
        match ==false:
            return astBuilder.NounExpr("false", null)
        match _:
            return astBuilder.LiteralExpr(value, null)
def N(name) as DeepFrozen:
    return astBuilder.NounExpr(name, null)

def extractValue(valueNode) as DeepFrozen:
    return M.call(valueNode, typenames[valueNode._which()], [], [].asMap())

def getWord(offset :Int, width :Int, => signed :Bool := false) as DeepFrozen:
    def fullOffset := offset * width
    def slot := fullOffset // 64
    def shift := fullOffset % 64
    var expr := m`root.getWord(${L(slot)})`
    if (shift != 0):
        expr := m`$expr >> ${L(shift)}`
    if (width != 64):
        def mask := L(2 ** width - 1)
        expr := m`$expr & $mask`
    if (signed):
        expr := m`$expr - ${L(2 ** width)} & ${L(2 ** width - 1)}`
    return expr

def getPointer(offset :Int) as DeepFrozen:
    return m`root.getPointer(${L(offset)})`

def shortName(node) as DeepFrozen:
    "Return a node name without the FQN prefix."
    def displayName := node.displayName()
    return displayName.slice(node.displayNamePrefixLength(),
                             displayName.size())

def makerName(node) as DeepFrozen:
    def n := shortName(node)
    def cap := if (n[0] >= 'a') { n[0] - 32 } else { n[0] }
    return "make" + cap + n.slice(1)

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
                def e := switch (type._which()) {
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
                    # XXX data?
                    match ==13 { m`_makeBytes.fromInts(_makeList.fromIterable(${getPointer(offset)}))` }
                    match ==14 {
                        def innerType := type.list().elementType()
                        def innerExpr := switch (innerType._which()) {
                            match ==16 {
                                def n := shortName(nodeMap[innerType.struct().typeId()])
                                astBuilder.MethodCallExpr(m`builder`, n,
                                                          [m`r`], [],
                                                          null)
                            }
                            match ==12 {
                                m`text(r)`
                            }
                            match ==13 {
                                m`_makeBytes.fromInts(_makeList.fromIterable(r))`
                            }
                            match _ {
                                m`r`
                            }
                        }
                        m`[for r in (${getPointer(offset)}) $innerExpr]`
                    }
                    match ==15 {
                            def n := L(shortName(nodeMap[type.enum().typeId()]))
                            m`enums[$n].getValues()[${getWord(offset, 16)}]`
                    }
                    match ==16 {
                        def n := shortName(nodeMap[type.struct().typeId()])
                        astBuilder.MethodCallExpr(m`reader`, n,
                                                  [getPointer(offset)],
                                                  [], null)
                    }
                    # XXX anyPointer?
                    match ==18 { m`null` }
                }
                if (slot.hadExplicitDefault()) {
                    if (type._which() !~ _ :(1..11 | 15..15)) {
                        throw(`Explicit defaults not supported for ${typenames[type._which()]} field $name`)
                    }
                    m`$e ^ ${L(extractValue(slot.defaultValue()))}`
                } else {
                    e
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

def noDiscriminant :Int := 65535

def slotOffset(node, slot) as DeepFrozen:
    def w := slot.type()._which()
    # pointer type
    if ([12, 13, 14, 16, 18].contains(w)) {
        return slot.offset() * 8 + node.struct().dataWordCount() * 8
    }
    def size := typeSize[w]
    return slot.offset() * size


def runtimeName(nodeMap, node) as DeepFrozen:
    if (node.scopeId() == 0): # XXX current-scope check?
        return shortName(node)
    def parent := nodeMap[node.scopeId()]
    return `${runtimeName(nodeMap, parent)}.${shortName(node)}`

def fieldWriter(nodeMap, groups, node, f) as DeepFrozen:
    if (f._which() == 1):
        def [groupNode, groupGroups] := groups[f.group().typeId()]
        def argNames := astBuilder.ListPattern([for subf in (groupNode.struct().fields()) astBuilder.FinalPattern(N(subf.name()), null, null)], null, null)
        return astBuilder.SeqExpr([m`def $argNames := ${N(f.name())}`] + [for subf in (groupNode.struct().fields()) fieldWriter(nodeMap, groupGroups, groupNode, subf)], null)
    var writeExpr := m`null`
    def slot := f.slot()
    def offset := slotOffset(node, slot)
    def offsetL := L(offset)
    def fname := N("f_" + f.name())
    def typenames0 := [ 1 => "Bool",
                        2 => "Int8",
                       3 => "Int16",
                       4 => "Int32",
                       5 => "Int64",
                       6 => "Uint8",
                       7 => "Uint16",
                       8 => "Uint32",
                       9 => "Uint64",
                       10 => "Float32",
                       11 => "Float64",
                       15 => "Enum" ]
    switch (slot.type()._which()):
        match ==0:
            null
        match ==1:
            # bool
            def arg := if (slot.hadExplicitDefault()) { m`$fname ^ ${L(extractValue(slot.defaultValue()))}` } else { m`${astBuilder.NounExpr(f.name(), null)}`}
            writeExpr := m`builder.writeBool(${L(slot.offset() // 8)}, ${L(slot.offset() % 8)}, $arg)`
        match _ :(2..11 | 15..15):
            # enum, primitive
            def arg := if (slot.hadExplicitDefault()) { m`$fname ^ ${L(extractValue(slot.defaultValue()))}` } else { fname }
            def verb := "write" + typenames0[slot.type()._which()]
            writeExpr := m`builder.$verb(pos + $offsetL, $arg)`
        match ==12:
            # text
            writeExpr := m`builder.allocText(pos + $offsetL, $fname)`
        match ==13:
            # data
            writeExpr := m`builder.allocData(pos + $offsetL, $fname, "trailing_zero" => false)`
        match ==14:
            # list
            def type := slot.type().list().elementType()
            def sizeTag := L(sizeTags[typenames[type._which()]])
            switch (type._which()):
                match ==16:
                    def innerStruct := nodeMap[type.struct().typeId()].struct()
                    def structSize := L(innerStruct.dataWordCount() +
                                        innerStruct.pointerCount())
                    # consider using preferredListEncoding
                    writeExpr := m`{
                        def listPos := builder.allocList(
                            pos + $offsetL, $sizeTag,
                            $structSize * $fname.size(),
                            ($structSize * $fname.size() + 1) * 8)
                        builder.writeStructList(listPos, $fname)
                    }`
                match ==12:
                    writeExpr := m`{
                        def listPos := builder.allocList(
                            pos, $sizeTag, $fname.size(),
                            $fname.size() * 8)
                        for _i => _item in ($fname) {
                            builder.allocText(listPos + (_i * 8), _item)
                        }
                    }`
                match ==13:
                    writeExpr := m`{
                        def listPos := builder.allocList(
                            pos, $sizeTag, $fname.size(),
                            $fname.size() * 8)
                        for _i => _item in ($fname) {
                            builder.allocData(listPos + (_i * 8), _item)
                        }
                    }`
                match ==1:
                    writeExpr := m`{
                        def listPos := builder.allocList(pos, $sizeTag, $fname.size(),
                                                         -$fname.size())
                        for _i => _item in ($fname) {
                            builder.writeBool(listPos + (_i // 8), _i % 8, _item)
                        }
                    }`
                match ==0:
                    writeExpr := m`def listPos := builder.allocList(pos, $sizeTag, $fname.size(), 0)`
                match t:
                    def verb := "write" + typenames0[t]
                    def width := L(typeSize[t])
                    def totalSize := m`$fname.size() * $width`
                    writeExpr := m`{
                        def listPos := builder.allocList(pos, $sizeTag, $fname.size(),
                                                         $totalSize)
                        for _i => _item in ($fname) {
                            builder.$verb(listPos + (_i * $width), _item)
                        }
                    }`
        match ==16:
            # struct
            def structName := runtimeName(nodeMap, nodeMap[slot.type().struct().typeId()])
            writeExpr := m`$fname.writePointer(pos + $offsetL)`
        match ==18:
            writeExpr := m`null`
        match unknownType:
            throw(`field ${node.displayName()}#${f.name()} has unknown type $unknownType`)
    if (f.discriminantValue() != noDiscriminant):
        # union handling
        def unionOffset := node.struct().discriminantOffset() * 2
        def fieldName := shortName(node)
        def v0 := N(f.name())
        def v1 := N(f.name() + "_curtag")
        def v3 := L(fieldName)
        def v4 := L(unionOffset)
        def v5 := L(f.discriminantValue())
        return m`if ($v0 != null) { $v1 := builder.checkTag($v1, $v3); builder.writeInt16($v4, $v5); $writeExpr }`
    else:
        return writeExpr

def getCapnTypeGuard(t) as DeepFrozen:
    return switch (t._which()):
        match ==0:
            m`Void`
        match ==1:
            m`Bool`
        match ==12:
            m`Str`
        match ==13:
            m`Bytes`
        match ==14:
            if ((def lt := getCapnTypeGuard(t.list().elementType())) != null):
                m`List[$lt]`
            else:
                m`List` 

        match _ :(2..9):
            m`Int`
        match _ :(10..11):
            m`Double`
        match _:
            null

def getFieldGuard(f) as DeepFrozen:
    if (f._which() == 0):
        return getCapnTypeGuard(f.slot().type())
    return null

def buildStructWriterMethod(nodeMap, node, groups) as DeepFrozen:
    def struct := node.struct()
    def fields := struct.fields()
    def dataSize := struct.dataWordCount()
    def ptrSize := struct.pointerCount()
    def sig := [for f in (fields)
                astBuilder.FinalPattern(
                    astBuilder.NounExpr("f_" + f.name(), null),
                    getFieldGuard(f), null)]
    def unions := [for u in (fields)
                   ? (u._which() == 1 &&
                      nodeMap[u.group().typeId()].struct().discriminantCount() > 0)
                   m`var ${N(u.name() + "_curtag")} := null`]
    def writes := unions + [for f in (fields) fieldWriter(nodeMap, groups, node, f)]
    def body := astBuilder.SeqExpr(
        [m`def pos := builder.allocate(${L((dataSize + ptrSize) * 8)})`] +
        writes +
        [m`builder.makeStructPointer(pos, ${L(dataSize)}, ${L(ptrSize)})`],
        null)
    return [sig, body]

def bootstrap(bs :Bytes) as DeepFrozen:
    "Reads the schema-definition capn message. Reassembles node structure then
    uses the schema builder to generate methods for reader and writer
    objects. Returns an AST for a module containing reader and writer."

    def root := makeMessageReader(bs).getRoot()
    def cgr := reader.CodeGeneratorRequest(root)
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
    def writerMethods := [for [node, groups] in (nodeTree) (
        def [sig, body] := buildStructWriterMethod(nodeMap, node, groups)
        astBuilder."Method"(null, makerName(node), sig, [], null, body, null))]
    def writerObj := astBuilder.ObjectExpr(
        null, mpatt`writer`,
        null, [],
        astBuilder.Script(null, writerMethods.with(m`method dump(root) { builder.dumps(root) }`) , [], null),
        null)
    def makeWriterObj := m`def makeWriter() as DeepFrozen { def builder := makeMessageWriter(); return $writerObj }`
    def mapEnum(node):
        def ens := [for en in (node.enum().enumerants())
                    [en.codeOrder(), L(en.name())]].sort()
        return m`makeEnum.asMap(${astBuilder.ListExpr([for [_, n] in (ens) n], null)})`
    def enums := astBuilder.MapExpr(
        [for node in (nodeMap) ? (node._which() == 2)
            astBuilder.MapExprAssoc(L(shortName(node)), mapEnum(node), null)],
        null)

    def module := m`object _ as DeepFrozen {
        method dependencies() :List[Str] { ["lib/capn", "lib/enum"] }
        method run(package) :Map[Str, DeepFrozen] {
            def [=> makeMessageWriter :DeepFrozen, => text :DeepFrozen] | _ := package."import"("lib/capn")
            def [=> makeEnum :DeepFrozen ] | _ := package."import"("lib/enum")
            def enums :DeepFrozen := $enums
            $readerObj
            $makeWriterObj
            [=> enums, => reader, => makeWriter]
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

