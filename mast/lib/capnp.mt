import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
exports (main)

# Where we are currently at:
# $ capnp compile -o $(which cat) schema.capnp > meta.capn
# $ ./mt-typhon -l mast -l . loader run lib/capnp

def mask(width :Int) :Int as DeepFrozen:
    return (1 << width) - 1

def shift(i :Int, offset :(0..!64), width :(0..64)) :Int as DeepFrozen:
    return (i >> offset) & mask(width)

def makeStructPointer(message :DeepFrozen, segment :Int, offset :Int,
                      dataSize :Int, pointerSize :Int) as DeepFrozen:
    return object structPointer:
        to _printOn(out):
            out.print(`<struct @@$segment+$offset d$dataSize p$pointerSize>`)

        to signature():
            return ["struct", dataSize, pointerSize]

        to getWord(i :Int) :Int:
            return message.getSegmentWord(segment, offset + i)

        to getPointer(i :Int):
            return message.interpretPointer(segment, offset + dataSize + i)

        to getPointers() :List:
            return [for i in (0..!pointerSize) structPointer.getPointer(i)]

def storages :DeepFrozen := [
    null,
    null,
    object uint8 as DeepFrozen {
        to _printOn(out) { out.print(`uint8`) }
        to signature() { return "uint8" }
        to get(message, segment :Int, offset :Int, index :Int) {
            def indexOffset :Int := index // 8
            def word :Int := message.getSegmentWord(segment, offset + indexOffset)
            return shift(word, (index % 8) * 8, 8)
        }
    },
    null,
    null,
    null,
    null,
]

def makeCompositeStorage :DeepFrozen := {
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    def makeCompositeStorage(dataSize, pointerSize) as DeepFrozen implements makerAuditor {
        def stride :Int := dataSize + pointerSize
        return object compositeStorage implements Selfless, valueAuditor {
            to _printOn(out) { out.print(`structs (d$dataSize p$pointerSize)`) }
            to _uncall() {
                return serializer(makeCompositeStorage, [dataSize, pointerSize])
            }

            to signature() { return ["composite", dataSize, pointerSize] }

            to get(message, segment :Int, offset :Int, index :Int) {
                def structOffset :Int := offset + stride * index
                return makeStructPointer(message, segment, structOffset,
                                         dataSize, pointerSize)
            }
        }
    }
}

def makeListPointer(message :DeepFrozen, segment :Int, offset :Int, size :Int,
                    storage) as DeepFrozen:
    return object listPointer:
        to _printOn(out):
            out.print(`<list of $storage @@$segment+$offset x$size>`)

        to _makeIterator():
            var position :Int := 0
            return def listIterator.next(ej):
                if (position >= size):
                    throw.eject(ej, "End of iteration")
                def element := storage.get(message, segment, offset,
                                           position)
                def rv := [position, element]
                position += 1
                return rv

        to get(index :Int):
            return storage.get(message, segment, offset, index)

        to signature():
            return ["list", storage]

        to size() :Int:
            return size

def formatWord(word :Int) as DeepFrozen:
    # LSB 0 1 ... 63 64 MSB
    def bits := [].diverge()
    for i in (0..!64):
        if (i % 8 == 0):
            bits.push("'")
        bits.push((((word >> i) & 0x1) == 0x1).pick("@", "."))
    return "b" + "".join(bits)

def makeMessage(bs :Bytes) as DeepFrozen:
    def get32LE(i :Int) :Int:
        var acc := 0
        for j in (0..!4):
            acc <<= 8
            acc |= bs[i * 4 + (3 - j)]
        return acc

    def segmentSizes :List[Int] := {
        def count := get32LE(0) + 1
        [for i in (1..count) get32LE(i)]
    }

    def segmentPositions :List[Int] := {
        def wordPadding := segmentSizes.size() // 2 + 1
        def l := [].diverge()
        var offset := wordPadding
        for size in (segmentSizes) {
            l.push(offset)
            offset += size
        }
        l.snapshot()
    }

    return object message as DeepFrozen:
        to getSegments() :List[Int]:
            return segmentPositions

        to getWord(i :Int) :Int:
            var acc := 0
            for j in (0..!8):
                acc <<= 8
                acc |= bs[i * 8 + (7 - j)]
            return acc

        to getSegmentWord(segment :Int, i :Int) :Int:
            def rv := message.getWord(segmentPositions[segment] + i)
            # traceln(`getSegmentWord($segment, $i) -> ${formatWord(rv)}`)
            return rv

        to getRoot():
            return message.interpretPointer(0, 0)

        to interpretPointer(segment :Int, offset :Int) :NullOk[Any]:
            "
            Dereference a word as a pointer.

            Zero pointers are represented as None.
            "
            def i := message.getSegmentWord(segment, offset)
            # traceln(`message.interpretPointer($segment, $offset) ${formatWord(i)}`)
            if (i == 0x0):
                return null
            return switch (i & 0x3):
                match ==0x0:
                    def structOffset :Int := 1 + offset + shift(i, 2, 30)
                    def dataSize :Int := shift(i, 32, 16)
                    def pointerCount :Int := shift(i, 48, 16)
                    makeStructPointer(message, segment, structOffset,
                                      dataSize, pointerCount)
                match ==0x1:
                    def listOffset :Int := 1 + offset + shift(i, 2, 30)
                    def elementType :Int := shift(i, 32, 3)
                    if (elementType == 7):
                        # Tag must be shaped like a struct pointer.
                        # XXX this doesn't work with current example data. Not
                        # sure why; currently guessing that the capnpc serializer
                        # just doesn't care whether those bits get trashed.
                        # def tag :Int ? ((tag & 0x3) == 0x0) := getWord(listOffset)
                        def tag :Int := message.getSegmentWord(segment, listOffset)
                        def listSize :Int := shift(tag, 2, 30)
                        def structSize :Int := shift(tag, 32, 16)
                        def pointerCount :Int := shift(tag, 48, 16)
                        def wordSize :Int := shift(i, 35, 29)
                        makeListPointer(message, segment, listOffset + 1, listSize,
                                 makeCompositeStorage(structSize, pointerCount))
                    else:
                        def listSize :Int := shift(i, 35, 29)
                        makeListPointer(message, segment, listOffset, listSize,
                                 storages[elementType])
                match ==0x2:
                    def targetSegment :Int := shift(i, 32, 32)
                    def targetOffset :Int := shift(i, 3, 29)
                    def wideLanding :Bool := 1 == shift(i, 2, 1)
                    if (wideLanding):
                        throw("Can't handle wide landings yet!")
                    else:
                        message.interpretPointer(targetSegment, targetOffset)
                match ==0x3 ? (shift(i, 2, 30) == 0x0):
                    object capPointer:
                        to _printOn(out):
                            out.print(`<cap $i>`)
                        to type() :Str:
                            return "cap"
                        to index() :Bool:
                            return shift(i, 32, 32)

def asData(wrapper) as DeepFrozen:
    return if (wrapper._respondsTo("_asData", 0)):
        wrapper._asData()
    else if (wrapper =~ l :List):
        [for item in (l) asData(item)]
    else:
        wrapper

object void as DeepFrozen:
    to signature():
        return "void"

    to interpret(_pointer):
        return null

object text as DeepFrozen:
    to signature():
        return "text"

    to interpret(pointer):
        return if (pointer == null):
            null
        else:
            def bs := _makeBytes.fromInts(_makeList.fromIterable(pointer))
            def s := UTF8.decode(bs, null)
            # Slice off the trailing NULL byte.
            s.slice(0, s.size() - 1)

def makeStruct(dataFields :Map[Str, Any],
               pointerFields :Map[Str, Any],
               groupFields :Map[Str, Any]) as DeepFrozen:
    def dataSize := {
        var lastByte :Int := 0
        for field in (dataFields) {
            def stop := field[1]
            lastByte max= (((stop - 1) // 8) + 1)
        }
        ((lastByte - 1) // 8) + 1
    }
    def pointerSize := {
        var lastWord :Int := -1
        for field in (pointerFields) { lastWord max= (field[0]) }
        lastWord + 1
    }
    def signature := ["struct", dataSize, pointerSize]

    def lookupField(pointer, start :Int, stop :Int):
        if (start == stop):
            # Mercy conversion to Void.
            return null
        def i := start // 64
        def word := pointer.getWord(i)
        def offset := start % 64
        def width := stop - start
        return if (width == 1):
            # Mercy conversion to Bool.
            (word & (1 << offset)) != 0
        else:
            # Unsigned int.
            shift(word, offset, width)

    return object schema:
        to signature():
            return signature

        to interpret(pointer):
            # XXX this should probably return defaults instead!
            if (pointer == null):
                return null

            def [=="struct", ds, ps] := pointer.signature()
            if (dataSize > ds || pointerSize > ps):
                throw(`Struct can't be interpreted: [$dataSize, $pointerSize] too big for [$ds, $ps]`)

            return object interpretedStruct:
                to _asData():
                    var dataKeys := dataFields.getKeys()
                    var pointerKeys := pointerFields.getKeys()
                    var groupKeys := groupFields.getKeys()
                    if (dataKeys.contains("_which")):
                        # Dig out the union tag and ensure that we only copy
                        # keys which have the right tag.
                        def which := interpretedStruct._which()
                        dataKeys := [for k in (dataKeys)
                                     ? (dataFields[k] !~ [_, _, !=which]) k]
                        pointerKeys := [for k in (pointerKeys)
                                        ? (pointerFields[k] !~ [_, _, !=which]) k]
                        groupKeys := [for k in (groupKeys)
                                      ? (groupFields[k] !~ [_, !=which]) k]
                    return [for name in (dataKeys + pointerKeys + groupKeys)
                            name => asData(M.call(interpretedStruct, name, [], [].asMap()))]

                match [via (dataFields.fetch) field, [], _]:
                    switch (field):
                        match [start, stop]:
                            lookupField(pointer, start, stop)
                        match [start, stop, unionTag]:
                            def which := interpretedStruct._which()
                            if (which == unionTag):
                                lookupField(pointer, start, stop)
                            else:
                                throw(`Incorrect union tag: Needed $unionTag but got $which`)
                match [via (pointerFields.fetch) field, [], _]:
                    switch (field):
                        match [index, s]:
                            def p := pointer.getPointer(index)
                            s.interpret(p)
                        match [index, s, unionTag]:
                            def which := interpretedStruct._which()
                            if (which == unionTag):
                                def p := pointer.getPointer(index)
                                s.interpret(p)
                            else:
                                throw(`Incorrect union tag: Needed $unionTag but got $which`)
                match [via (groupFields.fetch) field, [], _]:
                    switch (field):
                        match [struct, unionTag]:
                            def which := interpretedStruct._which()
                            if (which == unionTag):
                                struct.interpret(pointer)
                            else:
                                throw(`Incorrect union tag: Needed $unionTag but got $which`)
                        match struct:
                            struct.interpret(pointer)

def makeStructList(struct) as DeepFrozen:
    def [=="struct", dataSize, pointerSize] := struct.signature()
    def storage := makeCompositeStorage(dataSize, pointerSize)
    def signature := ["list", storage]
    return object listSchema:
        to signature():
            return signature

        to interpret(pointer):
            # traceln(`considering list $pointer`)
            if (pointer == null || pointer.size() == 0):
                # As a courtesy, null list pointers dereference to empty
                # lists. This gives callers a uniform List-like interface.
                # We also do this as an optimization for empty lists. ~ C.
                return []
            def [=="list", s] := pointer.signature()
            def [=="composite", ds, ps] := s.signature()
            if (dataSize > ds || pointerSize > ps):
                throw(`Composite list can't be interpreted: [$dataSize, $pointerSize] too big for [$ds, $ps]`)

            return object interpretedList:
                to _conformTo(guard):
                    if (guard == List):
                        return _makeList.fromIterable(interpretedList)

                to _makeIterator():
                    var position :Int := 0
                    return def interpretedListIterator.next(ej):
                        if (position >= pointer.size()):
                            throw.eject(ej, "End of iteration")
                        def rv := [position, interpretedList[position]]
                        position += 1
                        return rv

                to _asData():
                    return [for x in (interpretedList) asData(x)]

                # Odd asymmetry here; the storage is also known to the
                # pointer, so we don't have to invoke it again here.
                match [=="get", [index :Int], _]:
                    struct.interpret(pointer[index])

def buildList(builder, l :List) as DeepFrozen:
    def Ast := builder.getAstGuard()
    def exprs := [for x in (l) if (x =~ expr :Ast) { expr } else {
        builder.LiteralExpr(x, null)
    }]
    return builder.ListExpr(exprs, null)

def buildMap(builder, m :Map) as DeepFrozen:
    return if (m.isEmpty()) { m`[].asMap()` } else {
        def assocs := [for k => v in (m)
            builder.MapExprAssoc(builder.LiteralExpr(k, null), v, null)]
        builder.MapExpr(assocs, null)
    }

def buildType(builder, names, ty) as DeepFrozen:
    return switch (ty._which()):
        match ==0:
            m`void`
        match ==12:
            m`text`
        match ==13:
            m`data`
        match ==14:
            def elementType := ty.list().elementType()
            def inner := buildType(builder, names, elementType)
            if (elementType._which() == 16):
                m`makeStructList($inner)`
            else:
                m`makeListOf($inner)`
        match ==16:
            builder.NounExpr(names[ty.struct().typeId()], null)
        match ==18:
            # XXX there's a struct we're skipping over
            m`anyPointer`

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

def makeCompiler() as DeepFrozen:
    def nodes := [].asMap().diverge()
    def nodeNames := [].asMap().diverge()

    return object compiler:
        to addNode(node):
            def id := node.id()
            def displayName := node.displayName()
            nodes[id] := node
            nodeNames[id] := displayName.slice(node.displayNamePrefixLength(),
                                               displayName.size())

        to addFile(file):
            def data := asData(file)
            traceln(`Processing file $data`)

        to run():
            def builder := ::"m``".getAstBuilder()
            def structs := [].asMap().diverge()
            for id => node in (nodes):
                traceln(`node $id, name ${node.displayName()}`)
                # traceln(`node ${asData(node)}`)
                switch (node._which()) {
                    # file
                    match ==0 { traceln(`node is file`) }
                    # struct
                    match ==1 {
                        traceln(`node is struct`)
                        def struct := node.struct()
                        def dataSize := struct.dataWordCount()
                        def pointerSize := struct.pointerCount()
                        traceln(`struct signature $dataSize $pointerSize`)
                        def dataFields := [].asMap().diverge()
                        def pointerFields := [].asMap().diverge()
                        def groupFields := [].asMap().diverge()
                        for field in (struct.fields()) {
                            def name := field.name()
                            traceln(`Looking at field $name`)
                            # Union tag. 0xffff means no union.
                            def unionTag := field.discriminantValue() ^ 0xffff
                            switch (field._which()) {
                                # slot
                                match ==0 {
                                    def slot := field.slot()
                                    def type := slot.type()
                                    def [width, isData] := typeWidths[type._which()]
                                    if (isData) {
                                        def start := slot.offset() * width
                                        def stop := start + width
                                        dataFields[name] := if (unionTag == 0xffff) {
                                            buildList(builder, [start, stop])
                                        } else {
                                            buildList(builder, [start, stop, unionTag])
                                        }
                                    } else {
                                        def builtType := buildType(builder,
                                                                   nodeNames,
                                                                   slot.type())
                                        def offset := slot.offset()
                                        pointerFields[name] := if (unionTag == 0xffff) {
                                            buildList(builder, [offset,
                                                                builtType])
                                        } else {
                                            buildList(builder, [offset,
                                                                builtType,
                                                                unionTag])
                                        }
                                    }
                                }
                                # group
                                match ==1 {
                                    def typeId := field.group().typeId()
                                    def noun := builder.NounExpr(nodeNames[typeId],
                                                                 null)
                                    groupFields[name] := if (unionTag == 0xffff) {
                                        noun
                                    } else {
                                        buildList(builder, [noun, unionTag])
                                    }
                                }
                            }
                        }
                        structs[id] := m`makeStruct(
                            ${buildMap(builder, dataFields.snapshot())},
                            ${buildMap(builder, pointerFields.snapshot())},
                            ${buildMap(builder, groupFields.snapshot())},
                        )`
                    }
                    # enum
                    match ==2 {
                        traceln(`node is enum ${asData(node.enum())}`)
                    }
                    # const
                    match ==4 {
                        traceln(`node is const ${asData(node.const())}`)
                    }
                    # annotation
                    match ==5 {
                        traceln(`node is annotation ${asData(node.annotation())}`)
                    }
                }
            # N.B. the two node maps should be in the same order since they
            # were built element-wise at the same time, and thus the struct
            # map should also be in this order.
            def lhs := builder.ListPattern(
                [for n in (nodeNames.getValues())
                 builder.FinalPattern(builder.NounExpr(n, null), null, null)],
                null, null)
            def rhs := builder.ListExpr(structs.getValues(), null)
            def expr := m`def $lhs := $rhs`
            def Ast := builder.getAstGuard()
            traceln("expr", expr :Ast)
            return expr

def bootstrap() as DeepFrozen:

    # struct Value from schema.capnp @0xa93fc509624c72d9;
    # For bootstrapping, we use the start/stop info from:
    #   capnpc -o capnp schema.capnp
    # for example
    #     void @0 :Void;  # bits[0, 0), union tag = 0
    #     bool @1 :Bool;  # bits[16, 17), union tag = 1
    #     int8 @2 :Int8;  # bits[16, 24), union tag = 2
    def value := makeStruct(
        [
            "_which" => [0, 16],
            "void" => [0, 0, 0],
            "bool" => [16, 17, 1],
            "int8" => [16, 24, 2],
            "int16" => [16, 32, 3],
            "int32" => [32, 64, 4],
            "int64" => [64, 128, 5],
            "uint8" => [16, 24, 6],
            "uint16" => [16, 32, 7],
            "uint32" => [32, 64, 8],
            "uint64" => [64, 128, 9],
            "enum" => [16, 32, 15],
            # XXX ...
        ],
        [
            "text" => [0, text, 12],
        ],
        [].asMap(),
    )
    def type
    def binding := makeStruct(
        [
            "unbound" => [0, 0, 0],
            "_which" => [0, 16],
        ],
        ["type" => [0, type, 1]],
        [].asMap(),
    )
    def scope := makeStruct(
        [
            "inherit" => [0, 0, 1],
            "scopeId" => [0, 64],
            "_which" => [64, 80],
        ],
        [
            "bind" => [0, makeStructList(binding), 0],
        ],
        [].asMap(),
    )
    def brand := makeStruct(
        [].asMap(),
        ["scopes" => [0, makeStructList(scope)]],
        [].asMap(),
    )
    bind type := makeStruct(
        [
            "_which" => [0, 16],
            "void" => [0, 0, 0],
            "uint64" => [0, 0, 9],
            "text" => [0, 0, 12],
            # XXX ...
        ],
        [
            "elementType" => [0, type, 14],
            # XXX ...
        ],
        [
            "list" => [makeStruct(
                [].asMap(),
                ["elementType" => [0, type]],
                [].asMap(),
            ), 14],
            "enum" => [makeStruct(
                ["typeId" => [64, 128]],
                ["brand" => [0, brand]],
                [].asMap(),
            ), 15],
            "struct" => [makeStruct(
                ["typeId" => [64, 128]],
                ["brand" => [0, brand]],
                [].asMap(),
            ), 16],
        ],
    )
    def annotation := makeStruct(
        ["id" => [0, 64]],
        [
            "value" => [0, value],
            "brand" => [1, brand],
        ],
        [].asMap(),
    )
    def parameter := makeStruct([].asMap(), ["name" => [0, text]], [].asMap())
    def field := makeStruct(
        [
            "codeOrder" => [0, 16],
            "discriminantValue" => [16, 32],
            "_which" => [64, 80],
        ],
        [
            "name" => [0, text],
            "annotations" => [1, makeStructList(annotation)],
        ],
        [
            "slot" => [makeStruct(
                [
                    "offset" => [32, 64],
                    "hadExplicitDefault" => [128, 129],
                ],
                [
                    "type" => [2, type],
                    "defaultValue" => [3, value],
                ],
                [].asMap(),
            ), 0],
            "group" => [makeStruct(
                ["typeId" => [128, 192]],
                [].asMap(),
                [].asMap(),
            ), 1],
            "ordinal" => makeStruct(
                [
                    "implicit" => [0, 0, 0],
                    "explicit" => [96, 112, 1],
                    "_which" => [80, 96],
                ],
                [].asMap(),
                [].asMap(),
            ),
        ],
    )

    def enumerant := makeStruct(
        ["codeOrder" => [0, 16]],
        [
            "name" => [0, text],
            "annotations" => [1, makeStructList(annotation)],
        ],
        [].asMap(),
    )

    # cf. struct CodeGeneratorRequest
    def schema := makeStruct(
        [].asMap(),
        [
            "nodes" => [0, makeStructList(makeStruct(
                [
                    "file" => [0, 0, 0],
                    "id" => [0, 64],
                    "displayNamePrefixLength" => [64, 96],
                    "_which" => [96, 112],
                    "scopeId" => [128, 192],
                    # XXX ...
                    "isGeneric" => [288, 289],
                ],
                [
                    "displayName" => [0, text],
                    "nestedNodes" => [1, makeStructList(makeStruct(
                        ["id" => [0, 64]],
                        ["name" => [0, text]],
                        [].asMap(),
                    ))],
                    "annotations" => [2, makeStructList(annotation)],
                    "parameters" => [5, makeStructList(parameter)],
                ],
                [
                    "struct" => [makeStruct(
                        [
                            "dataWordCount" => [112, 128],
                            "pointerCount" => [192, 208],
                        ],
                        [
                            "fields" => [3, makeStructList(field)],
                        ],
                        [].asMap(),
                    ), 1],
                    "enum" => [makeStruct(
                        [].asMap(),
                        ["enumerants" => [3, makeStructList(enumerant)]],
                        [].asMap(),
                    ), 2],
                    "const" => [makeStruct(
                        [].asMap(),
                        [
                            "type" => [3, type],
                            "value" => [3, value],
                        ],
                        [].asMap(),
                    ), 4],
                    "annotation" => [makeStruct(
                        [
                            "targetsFile" => [112, 113],
                        ],
                        [
                            "type" => [3, type],
                        ],
                        [].asMap(),
                    ), 5],
                ],
            ))],
            "requestedFiles" => [1, makeStructList(makeStruct(
                ["id" => [0, 64]],
                [
                    "filename" => [0, text],
                    "imports" => [1, makeStructList(makeStruct(
                        ["id" => [0, 64]],
                        ["name" => [0, text]],
                        [].asMap(),
                    ))],
                ],
                [].asMap(),
            ))],
        ],
        [].asMap(),
    )
    return schema

def main(_argv, => makeFileResource) as DeepFrozen:
    def schema := bootstrap()
    def handle := makeFileResource("meta.capn")
    return when (def bs := handle<-getContents()) ->
        traceln(`Read in ${bs.size()} bytes`)
        def message := makeMessage(bs)
        def root := message.getRoot()
        def request := schema.interpret(root)
        def compiler := makeCompiler()
        traceln(`processing requested files`)
        for file in (request.requestedFiles()):
            compiler.addFile(file)
        traceln(`processing nodes`)
        for node in (request.nodes()):
            compiler.addNode(node)
        compiler()
        0
