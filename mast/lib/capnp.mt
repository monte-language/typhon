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
            return message.getSegmentWord(segment, 1 + offset + i)

        to getPointers() :List:
            def base :Int := offset + dataSize
            return [for o in (base..!(base + pointerSize))
                    message.interpretPointer(segment, o)]

def storages :DeepFrozen := [null] * 7

def makeCompositeStorage(dataSize :Int, pointerSize :Int) as DeepFrozen:
    def stride :Int := dataSize + pointerSize
    return object compositeStorage:
        to _printOn(out):
            out.print(`structs (d$dataSize p$pointerSize)`)

        to stride() :Int:
            return stride

        to get(message, segment :Int, offset :Int):
            return makeStruct(message, segment, offset, dataSize, pointerSize)

def makeList(message :DeepFrozen, segment :Int, offset :Int, size :Int,
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
            return message.getWord(segmentPositions[segment] + i)

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
                        traceln(`struct size $structSize pointers $pointerCount`)
                        makeList(message, segment, listOffset, listSize,
                                 makeCompositeStorage(structSize, pointerCount))
                    else:
                        def listSize :Int := shift(i, 35, 29)
                        makeList(message, segment, listOffset, listSize,
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

def main(_argv, => makeFileResource) as DeepFrozen:
    def handle := makeFileResource("meta.capn")
    return when (def bs := handle<-getContents()) ->
        traceln(`Read in ${bs.size()} bytes`)
        def message := makeMessage(bs)
        def root := message.getRoot()
        traceln(`root $root`)
        for pointer in (root.getPointers()):
            traceln(`pointer $pointer`)
            for s in (pointer):
                traceln(`substruct $s`)
        0
