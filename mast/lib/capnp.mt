import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
exports (main)

def mask(width :Int) :Int as DeepFrozen:
    return (1 << width) - 1

def shift(i :Int, offset :Int, width :Int) :Int as DeepFrozen:
    return (i >> offset) & mask(width)

def makeStruct(message :DeepFrozen, segment :Int, offset :Int, dataSize :Int,
               pointerSize :Int) as DeepFrozen:
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
        to get(message, segment :Int, offset :Int, index :Int) {
            def word :Int := message.getSegmentWord(segment, offset)
            return shift(word, index * 8, 8)
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

            to get(message, segment :Int, offset :Int, index :Int) {
                def structOffset :Int := offset + stride * index
                return makeStruct(message, segment, structOffset, dataSize,
                                  pointerSize)
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
            return object listIterator:
                to next(ej):
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

        to interpretPointer(segment :Int, offset :Int):
            def i := message.getSegmentWord(segment, offset)
            return switch (i & 0x3):
                match ==0x0:
                    def structOffset :Int := 1 + offset + shift(i, 2, 30)
                    def dataSize :Int := shift(i, 32, 16)
                    def pointerCount :Int := shift(i, 48, 16)
                    makeStruct(message, segment, structOffset, dataSize, pointerCount)
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

object text as DeepFrozen:
    to signature():
        return "text"

    to interpret(pointer):
        def bs := _makeBytes.fromInts(_makeList.fromIterable(pointer))
        def s := UTF8.decode(bs, null)
        # XXX This is strange. The spec promises that we shouldn't have to
        # trim trailing NULs, yet there's a bunch of trailing NULs!
        var i :Int := s.size() - 1
        while (s[i] == '\x00'):
            i -= 1
        return s.slice(0, i + 1)

def makeSchema(dataFields :Map[Str, Any],
               pointerFields :Map[Str, Pair[Int, Any]]) as DeepFrozen:
    def dataSize := {
        var lastByte :Int := 0
        for [_, stop] in (dataFields) {
            lastByte max= (((stop - 1) // 8) + 1)
        }
        ((lastByte - 1) // 8) + 1
    }
    def signature := ["struct", dataSize, pointerFields.size()]
    traceln(`made schema with signature $signature`)
    return object schema:
        to signature():
            return signature

        to interpret(pointer):
            traceln(`considering struct $pointer`)
            def ==signature := pointer.signature()
            return object interpretedStruct:
                match [via (dataFields.fetch) [start, stop], [], _]:
                    def i := start // 8
                    def word := pointer.getWord(i)
                    def offset := start - i
                    def width := stop - start
                    if (width == 1):
                        # Mercy conversion to Bool.
                        (word & (1 << offset)) != 0
                    else:
                        # Unsigned int.
                        shift(word, offset, width)
                match [via (pointerFields.fetch) [index, s], [], _]:
                    def p := pointer.getPointer(index)
                    s.interpret(p)

def makeListOfStructs(schema) as DeepFrozen:
    def [=="struct", dataSize, pointerSize] := schema.signature()
    def storage := makeCompositeStorage(dataSize, pointerSize)
    def signature := ["list", storage]
    return object listSchema:
        to signature():
            return signature

        to interpret(pointer):
            traceln(`considering list $pointer`)
            def ==signature := pointer.signature()
            return object interpretedList:
                to _conformTo(guard):
                    if (guard == List):
                        return _makeList.fromIterable(interpretedList)

                to _makeIterator():
                    var position :Int := 0
                    return object interpretedListIterator:
                        to next(ej):
                            if (position >= pointer.size()):
                                throw.eject(ej, "End of iteration")
                            def rv := [position, interpretedList[position]]
                            position += 1
                            return rv

                # Odd asymmetry here; the storage is also known to the
                # pointer, so we don't have to invoke it again here.
                match [=="get", [index :Int], _]:
                    schema.interpret(pointer[index])

def main(_argv, => makeFileResource) as DeepFrozen:
    def schema := makeSchema(
        [].asMap(),
        [
            "nodes" => [0, makeListOfStructs(makeSchema(
                [
                    "id" => [0, 64],
                    # XXX ...
                    "isGeneric" => [288, 289],
                ],
                [
                    "displayName" => [0, text],
                    "nestedNodes" => [1, makeListOfStructs(makeSchema(
                        ["id" => [0, 64]],
                        ["name" => [0, text]],
                    ))],
                    "annotations" => [2, null],
                    "fields" => [3, null],
                    "superclasses" => [4, null],
                    # "parameters" => [5, makeListOfStructs(makeSchema(
                    #     [].asMap(), ["name" => [0, text]],
                    # ))],
                    "parameters" => [5, null],
                ],
            ))],
            "requestedFiles" => [1, makeListOfStructs(makeSchema(
                ["id" => [0, 64]],
                [
                    "filename" => [0, text],
                    "imports" => [1, makeListOfStructs(makeSchema(
                        ["id" => [0, 64]],
                        ["name" => [0, text]],
                    ))],
                ],
            ))],
        ],
    )
    def handle := makeFileResource("meta.capn")
    return when (def bs := handle<-getContents()) ->
        traceln(`Read in ${bs.size()} bytes`)
        def message := makeMessage(bs)
        def root := message.getRoot()
        traceln(`root $root`)
        traceln(`pointers ${root.getPointers()}`)
        def request := schema.interpret(root)
        traceln(`struct $request`)
        def nodes := request.nodes()
        def node := nodes[0]
        traceln(`node $node`)
        traceln(`displayName ${node.displayName()}`)
        traceln(`isGeneric ${node.isGeneric()}`)
        traceln(`nestedNodes ${node.nestedNodes() :List}`)
        def [requestedFile] := request.requestedFiles() :List
        traceln(`requestedFile $requestedFile`)
        traceln(`id ${requestedFile.id()}`)
        traceln(`filename ${requestedFile.filename()}`)
        traceln(`imports ${[for i in (requestedFile.imports()) [i.id(), i.name()]]}`)
        0