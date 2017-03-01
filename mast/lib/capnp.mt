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

def storages :DeepFrozen := [null] * 7

def makeCompositeStorage :DeepFrozen := {
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    def makeCompositeStorage(dataSize, pointerSize) as DeepFrozen implements makerAuditor {
        def stride :Int := dataSize + pointerSize
        return object compositeStorage implements Selfless, valueAuditor {
            to _printOn(out) { out.print(`structs (d$dataSize p$pointerSize)`) }
            to _uncall() {
                return serializer(makeCompositeStorage, [dataSize, pointerSize])
            }

            to stride() :Int { return stride }

            to get(message, segment :Int, offset :Int) {
                return makeStruct(message, segment, offset, dataSize, pointerSize)
            }
        }
    }
}

def makeListPointer(message :DeepFrozen, segment :Int, offset :Int, size :Int,
                    storage) as DeepFrozen:
    def stride := storage.stride()

    return object listPointer:
        to _printOn(out):
            out.print(`<list of $storage @@$segment+$offset x$size>`)

        to _makeIterator():
            var position :Int := 0
            return object listIterator:
                to next(ej):
                    if (position >= size):
                        throw.eject(ej, "End of iteration")
                    def structOffset :Int := offset + stride * position
                    def element := storage.get(message, segment, structOffset)
                    def rv := [position, element]
                    position += 1
                    return rv

        to get(index :Int):
            def structOffset :Int := offset + stride * index
            return storage.get(message, segment, structOffset)

        to signature():
            return ["list", storage]

        to size() :Int:
            return size

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

    traceln(`segments $segmentPositions`)

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
            traceln(`getSegmentWord($segment, $i) -> $rv`)
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
                        def tag :Int := message.getWord(listOffset)
                        def listSize :Int := shift(tag, 2, 30)
                        def structSize :Int := shift(tag, 32, 16)
                        def pointerCount :Int := shift(tag, 48, 16)
                        def wordSize :Int := shift(i, 35, 29)
                        traceln(`size in words $wordSize`)
                        traceln(`expected size in words ${listSize * (structSize + pointerCount)}`)
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

# XXX dataFields.size() isn't always going to be the number of words. I think
# instead that we need a <= relation based on the extent to which the schema
# accesses data.
def makeSchema(dataFields :Map[Str, Any],
               pointerFields :Map[Str, Pair[Int, Any]]) as DeepFrozen:
    def signature := ["struct", dataFields.size(), pointerFields.size()]
    return object schema:
        to signature():
            return signature

        to interpret(pointer):
            traceln(`considering struct $pointer`)
            def ==signature := pointer.signature()
            return object interpretedStruct:
                match [via (pointerFields.fetch) [index, s], [], _]:
                    def p := pointer.getPointer(index)
                    s.interpret(p)

def makeListOf(schema) as DeepFrozen:
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
            "nodes" => [0, makeListOf(makeSchema(
                [].asMap(),
                [].asMap(),
            ))],
            "requestedFiles" => [1, makeListOf(makeSchema(
                [].asMap(),
                [].asMap(),
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
        traceln(`nodes $nodes`)
        traceln(`nodes ${nodes :List}`)
        def requestedFiles := request.requestedFiles()
        traceln(`requestedFiles $requestedFiles`)
        traceln(`requestedFiles ${requestedFiles :List}`)
        0
