import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
exports (Absent, absent, makeMessageReader, makeMessageWriter, loads, text, undefined)
"Components for reading the packing format used for capn messages."

object absent as DeepFrozen {}
def Absent :DeepFrozen := Same[absent]

def STRUCT :Int := 0
def LIST :Int := 1
def FAR :Int := 2

def LIST_SIZE_8 :Int := 2

def text(pointer) as DeepFrozen:
    return if (pointer == null):
        null
    else:
        def bs := _makeBytes.fromInts(_makeList.fromIterable(pointer))
        def s := UTF8.decode(bs, null)
        # Slice off the trailing NULL byte.
        s.slice(0, s.size() - 1)

def mask(width :Int) :Int as DeepFrozen:
    return (1 << width) - 1

def shift(i :Int, offset :(0..!64), width :(0..64)) :Int as DeepFrozen:
    return (i >> offset) & mask(width)

def makeStructPointer(message :DeepFrozen, segment :Int, offset :Int,
                      dataSize :Int, pointerSize :Int) as DeepFrozen:
    return object structPointer as DeepFrozen:
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
    object void as DeepFrozen {
        to _printOn(out) { out.print("void") }
        to signature() { return "void" }
        to get(_, _, _, _) { return null }
    },
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
    object pointerStorage as DeepFrozen {
        to _printOn(out) { out.print(`pointer`) }
        to signature() { return "pointer" }
        to get(message, segment :Int, offset :Int, index :Int) {
            return message.interpretPointer(segment, offset + index)
        }
    },
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
                    storage :DeepFrozen) as DeepFrozen:
    object listPointer as DeepFrozen:
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
    return listPointer
def formatWord(word :Int) as DeepFrozen:
    # LSB 0 1 ... 63 64 MSB
    def bits := [].diverge()
    for i in (0..!64):
        if (i % 8 == 0):
            bits.push("'")
        bits.push((((word >> i) & 0x1) == 0x1).pick("@", "."))
    return "b" + "".join(bits)

def makeMessageReader(bs :Bytes) as DeepFrozen:
    "Create a schema-independent object from serialized data.
     Provides methods for basic data traversal, used by the
     schema-driven layer."
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
            def i :Int := message.getSegmentWord(segment, offset)
            # traceln(`message.interpretPointer($segment, $offset)@@${segmentPositions[segment] + offset} ${formatWord(i)}`)
            if (i == 0x0):
                return null
            return switch (i & 0x3):
                match ==0x0:
                    var offsetVal := shift(i, 2, 30)
                    if (offsetVal > (2 ** 15 - 1)):
                        offsetVal := offsetVal - 2 ** 30
                    def structOffset :Int := 1 + offset + offsetVal
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
                    object capPointer implements DeepFrozen:
                        to _printOn(out):
                            out.print(`<cap $i>`)
                        to type() :Str:
                            return "cap"
                        to index() :Bool:
                            return shift(i, 32, 32)

object undefined as DeepFrozen {}

def bufStart :List[Int] := [0] * 16

def makeMessageWriter() as DeepFrozen:
    def buf := bufStart.diverge() # zone for segment/root pointers
    def roundToWord(pos):
        return (pos + (8 - 1)) & -8  # Round up to 8-byte boundary

    return object messageWriter:
        to checkTag(curtag, newtag):
            if (curtag != null):
                throw(`got multiple values for the union tag: ${curtag}, ${newtag}`)
            return newtag

        to allocate(n :Int):
            def pos := buf.size()
            buf.extend([0] * n)
            return pos

        to allocText(pos, s :NullOk[Str]):
            if (s == null):
                messageWriter.writeInt64(pos, 0)
                return -1
            def via (UTF8.encode) bs := s
            return messageWriter.allocData(pos, bs, "trailingZero" => true)

        to allocData(pos, bs :NullOk[Bytes], => trailingZero := false):
            if (bs == null):
                messageWriter.writeInt64(pos, 0)
                return -1
            def nn := bs.size() + trailingZero.pick(1, 0)
            def result := messageWriter.allocList(pos, LIST_SIZE_8, nn, nn)
            for i => b in (bs):
                buf[result + i] := b
            return result

        to allocList(pos, sizeTag, count, length):
            def result := messageWriter.allocate(roundToWord(length))
            def offset := (result - pos - 8) // 8
            def p := (count << 35 | (sizeTag << 32 & 0x700000000) |
                      (offset << 2 & 0xfffffffc) | LIST)
            messageWriter.writeInt64(pos, p)
            return result

        to writeUint64(i, n):
            for j in (0..!8):
                buf[i + j] := shift(n, j * 8, 8)

        to writeUint32(i, n):
            for j in (0..!4):
                buf[i + j] := shift(n, j * 8, 8)

        to writeUint16(i, n):
            buf[i] := shift(n, 0, 8)
            buf[i + 1] := shift(n, 8, 8)

        to writeUint8(i, n):
            buf[i] := shift(n, 0, 8)

        # XXX extremely lazy/wasteful way to implement signed packing
        to writeInt64(i, n):
            messageWriter.writeUint64(i, if (n < 0) { 2*64 + n - 1 } else { n })

        to writeInt32(i, n):
            messageWriter.writeUint32(i, if (n < 0) { 2*32 + n - 1 } else { n })

        to writeInt16(i, n):
            messageWriter.writeUint16(i, if (n < 0) { 2*16 + n - 1 } else { n })

        to writeInt8(i, n):
            messageWriter.writeUint8(i, if (n < 0) { 2*8 + n - 1 } else { n })

        to writeEnum(i, e):
            messageWriter.writeUint16(i, e.asInteger())

        to writeStructListTag(pos, listSize, dataSize, ptrSize):
            messageWriter.writeInt64(
                pos,
                (ptrSize << 48) |
                (dataSize << 32 & 0xffff00000000) |
                (listSize << 2 & 0xfffffffc))
            return pos + 8

        to makeStructPointer(pos ? (pos % 8 == 0), dataSize, ptrSize):
            return def structPointer.writePointer(offset):
                def totalOffset := (pos - offset - 8) // 8
                def p := ((ptrSize << 48) |
                          (dataSize << 32 & 0xffff00000000) |
                          (totalOffset << 2 & 0xfffffffc) |
                          STRUCT)
                messageWriter.writeInt64(offset, p)

        to writeUnionTag(pos, union):
            var selectedName := absent
            for name => [field, discriminant] in (union):
                if (field != absent):
                    if (selectedName != absent):
                        throw(`Can't provide both "$selectedName" and "$name" fields of union`)
                    selectedName := name
                    messageWriter.writeUint16(pos, discriminant)

        to dumps(obj) :Bytes:
            # segment count - 1
            messageWriter.writeUint32(0, 0)
            # segment size in words (i.e. not counting segment header)
            messageWriter.writeUint32(4, (buf.size() - 8) // 8)
            # XXX check that it's a struct pointer
            obj.writePointer(8)
            return _makeBytes.fromInts(buf)

def loads(bs :Bytes, reader, payloadType) as DeepFrozen:
    def root := makeMessageReader(bs).getRoot()
    return M.call(reader, payloadType, [root], [].asMap())


