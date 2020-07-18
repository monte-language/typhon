import "capn/reader" =~ [=> reader :DeepFrozen]
import "lib/capn" =~ [=> makeMessageReader :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (compileCapn, main)

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
                                astBuilder.MethodCallExpr(m`reader`, n,
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

def childrenOf(nodeMap, parentId) as DeepFrozen:
    return [for id => node in (nodeMap) ? (node._which() == 1 &&
                node.struct().isGroup() && node.scopeId() == parentId)
            id => [node, childrenOf(nodeMap, id)]]

def groupMap(tree, f) as DeepFrozen:
    var result1 := [].asMap()
    var result2 := []
    for [leaf, branches] in (tree):
        def m := f(leaf)
        result1 |= m
        result2 with= ([leaf, m])
        def [rest1, rest2] := groupMap(branches, f)
        result1 |= rest1
        result2 += rest2
    return [result1, result2]

def collectFields(struct, groups) as DeepFrozen:
    def fields := [for f in (struct.fields()) ? (f._which() == 0) "f_" + f.name() => f]
    def [groupFields, fieldsByGroup] := groupMap(
        groups, fn g { [for f in (g.struct().fields()) ? (f._which() == 0)
                         `f_${shortName(g)}_${f.name()}` => f]
            })

    return [fields, groupFields, fieldsByGroup]

def getCapnTypeGuard(t) as DeepFrozen:
    return switch (t._which()):
        match ==0:
            m`Any[Absent, Void]`
        match ==1:
            m`Any[Absent, Bool]`
        match ==12:
            m`Any[Absent, Str]`
        match ==13:
            m`Any[Absent, Bytes]`
        match ==14:
            if ((def lt := getCapnTypeGuard(t.list().elementType())) != null):
                m`Any[Absent, List[$lt]]`
            else:
                m`Any[Absent, List]`

        match _ :(2..9):
            m`Any[Absent, Int]`
        match _ :(10..11):
            m`Any[Absent, Double]`
        match _:
            null

def getFieldGuard(f) as DeepFrozen:
    if (f._which() == 0):
        return getCapnTypeGuard(f.slot().type())
    else if (f._which() == 1):
        # XXX consider constraining to names in group
        return m`Map`
    return null

def fieldWriter(nodeMap, node, _, f, fname) as DeepFrozen:
    var writeExpr := m`null`
    def slot := f.slot()
    def offset := slotOffset(node, slot)
    def offsetL := L(offset)
    def typenames0 := [1 => "Bool",
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
                       15 => "Enum"]

    switch (slot.type()._which()):
        match ==0:
            null
        match ==1:
            # bool
            def arg := if (slot.hadExplicitDefault()) { m`$fname ^ ${L(extractValue(slot.defaultValue()))}` } else { fname }
            writeExpr := m`builder.writeBool(pos + ${L(slot.offset() // 8)}, ${L(slot.offset() % 8)}, $arg)`
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
                    def innerNode := nodeMap[type.struct().typeId()]
                    def innerStruct := innerNode.struct()
                    def innerStructWriter := "write_" + shortName(innerNode)
                    def structSize := L(innerStruct.dataWordCount() +
                                        innerStruct.pointerCount())
                    def fields := [for f in (innerStruct.fields()) "f_" + f.name() => f]
                    def mapPatt := astBuilder.MapPattern(
                        [for name => f in (fields)
                         astBuilder.MapPatternAssoc(
                             L(f.name()),
                             astBuilder.FinalPattern(N(name), null, null),
                             if (f._which() == 1) { m`[].asMap()` } else { N("absent") },
                             null)],
                        null, null)
                    def structWriterCall := astBuilder.MethodCallExpr(m`structWriter`, innerStructWriter, [m`listPos + (i * $structSize * 8)`, m`builder`] + [for name => _ in (fields) N(name)], [], null)
                    # consider using preferredListEncoding
                    writeExpr := m`{
                        def tagPos := builder.allocList(
                            pos + $offsetL, $sizeTag,
                            $structSize * $fname.size(),
                            ($structSize * $fname.size() + 1) * 8)
                        def listPos := builder.writeStructListTag(
                            tagPos,
                            $fname.size(),
                            ${L(innerStruct.dataWordCount())},
                            ${L(innerStruct.pointerCount())})
                        for i => map in ($fname) {
                         def $mapPatt := map
                         $structWriterCall
                        }
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
            writeExpr := m`$fname.writePointer(pos + $offsetL)`
        match ==18:
            writeExpr := m`null`
        match unknownType:
            throw(`field ${node.displayName()}#$fname has unknown type $unknownType`)
    return m`if ($fname != absent) { $writeExpr }`

def buildStructWriterMethod(nodeMap, node, groups) as DeepFrozen:
    def struct := node.struct()
    def dataSize := struct.dataWordCount()
    def ptrSize := struct.pointerCount()
    def fields := [for f in (struct.fields()) "f_" + f.name() => f]
    def sig := [for name => f in (fields)
                astBuilder.NamedParam(
                    L(f.name()),
                    astBuilder.FinalPattern(
                        N(name),
                        getFieldGuard(f), null),
                    if (f._which() == 1) {
                        m`[].asMap()`
                    } else {
                        N("absent")
                    }, null)]
    def writerSig := [for name => f in (fields)
                      astBuilder.FinalPattern(
                          N(name),
                          getFieldGuard(f), null)]
    def writerMethName := "write_" + shortName(node)
    def unionTagsWrites := [].diverge()
    def generateUnionTag(st, fi):
        def unionOffset := L(st.discriminantOffset() * 2)
        def unionMap := astBuilder.MapExpr([for name => unionField in (fi) ? (unionField.discriminantValue() != noDiscriminant) astBuilder.MapExprAssoc(L(unionField.name()), m`[${N(name)},${L(unionField.discriminantValue())}]`, null)], null)
        return m`builder.writeUnionTag(pos + $unionOffset, $unionMap)`

    if (struct.discriminantCount() > 0):
        # union handling
        unionTagsWrites.push(generateUnionTag(struct, fields))
    def unpackGroups := [].diverge()
    def writableFields := [for name => f in (fields) ? (f._which() == 0) name => f].diverge()
    def groupStack := [for name => f in (fields) ? (f._which() == 1) name => nodeMap[f.group().typeId()]].diverge()
    while (groupStack.size() > 0):
        def [name, g] := groupStack.pop()
        def groupUnpacks := [].diverge()
        def unionMap := [].asMap().diverge()
        for f in (g.struct().fields()):
            def n := `${name}_${f.name()}`
            unionMap[n] := f
            groupUnpacks.push(astBuilder.MapPatternAssoc(
                L(f.name()),
                astBuilder.FinalPattern(
                    N(n),
                    getFieldGuard(f), null),
                if (f._which() == 1) { m`[].asMap()` } else { N("absent") }, null))
            if (f._which() == 1):
                groupStack[n] := nodeMap[f.group().typeId()]
            else:
                writableFields[n] := f
        def groupUnpacker := astBuilder.MapPattern(groupUnpacks.snapshot(), null, null)
        unpackGroups.push(m`def $groupUnpacker := ${N(name)}`)
        if (g.struct().discriminantCount() > 0):
            unionTagsWrites.push(generateUnionTag(g.struct(), unionMap))

    def writes := [for name => f in (writableFields) fieldWriter(nodeMap, node, groups, f, N(name))]
    def writeFunc := astBuilder."Method"(null, writerMethName, [astBuilder.FinalPattern(N("pos"), null, null), astBuilder.FinalPattern(N("builder"), null, null)] + writerSig, [], null, astBuilder.SeqExpr(unpackGroups + unionTagsWrites + writes, null), null)
    var writeExpr := astBuilder.MethodCallExpr(N("structWriter"), writerMethName, [N("pos"), N("builder")] + [for name => _ in (fields) N(name)], [], null)

    def body := astBuilder.SeqExpr(
        [m`def pos := builder.allocate(${L((dataSize + ptrSize) * 8)}); $writeExpr; builder.makeStructPointer(pos, ${L(dataSize)}, ${L(ptrSize)})`],
        null)
    return [
        writeFunc,
        astBuilder."Method"(null, makerName(node), [], sig, null, body, null)
    ]

def compileCapn(bs :Bytes) :DeepFrozen as DeepFrozen:
    "Reads the schema-definition capn message. Reassembles node structure then
    uses the schema builder to generate methods for reader and writer
    objects. Returns an AST for a module containing reader and writer."

    def root := makeMessageReader(bs).getRoot()
    def cgr := reader.CodeGeneratorRequest(root)
    def nodeMap := [for node in (cgr.nodes()) node.id() => node]
    def nodeTree := [for id => node in (nodeMap) ? (node._which() == 1 &&
        !node.struct().isGroup()) id => [node, childrenOf(nodeMap, id)]]
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
    def writerMethods := [].diverge()
    def builderMethods := [].diverge()
    for [node, groups] in (nodeTree):
        def [writeMethod, buildMethod] := buildStructWriterMethod(nodeMap, node, groups)
        writerMethods.push(writeMethod)
        builderMethods.push(buildMethod)
    def structWriterObj := astBuilder.ObjectExpr(
        null, mpatt`structWriter`,
        m`DeepFrozen`, [],
        astBuilder.Script(null, writerMethods.snapshot(), [], null),
        null)
    def writerObj := astBuilder.ObjectExpr(
        null, mpatt`writer`,
        null, [],
        astBuilder.Script(null, builderMethods.with(m`method dump(root) { builder.dumps(root) }`) , [], null),
        null)
    def makeWriterObj := m`def makeWriter() as DeepFrozen {
        "
        Create a new message writer.

        A fresh writer is required for every message.
        "
        def builder := makeMessageWriter()
        return $writerObj
    }`
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
            def [=> Absent :DeepFrozen, => absent :DeepFrozen,
                 => makeMessageWriter :DeepFrozen,
                 => text :DeepFrozen] | _ := package."import"("lib/capn")
            def [=> makeEnum :DeepFrozen ] | _ := package."import"("lib/enum")
            def enums :DeepFrozen := $enums
            $structWriterObj
            $readerObj
            $makeWriterObj
            [=> enums, => reader, => makeWriter]
        }
    }`
    return module

def main(_argv, => stdio) :Vow[Int] as DeepFrozen:
    "Compile a schema in capn message format from stdin, write MAST to stdout."
    return when (def input := collectBytes(stdio.stdin())) ->
        def stdout := stdio.stdout()
        def expr :DeepFrozen := compileCapn(input)
        def mast := makeMASTContext()
        mast(expr.expand())
        def output :Bytes := mast.bytes()
        when (stdout(output), stdout<-complete()) -> { 0 }
