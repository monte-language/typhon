exports (main)

def mask(width :Int) :Int as DeepFrozen:
    return (1 << width) - 1

def shift(i :Int, offset :Int, width :Int) :Int as DeepFrozen:
    return (i >> offset) & mask(width)

def makeCapn(bs :Bytes) as DeepFrozen:
    def get32LE(i :Int) :Int:
        var acc := 0
        for j in (0..!4):
            acc <<= 8
            acc |= bs[i * 4 + (3 - j)]
        return acc

    def getWord(i :Int) :Int:
        var acc := 0
        for j in (0..!8):
            acc <<= 8
            acc |= bs[i * 8 + (7 - j)]
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

    traceln(`segment sizes $segmentSizes`)
    traceln(`segment positions $segmentPositions`)

    def makePointer(segment :Int, offset :Int):
        def i := getWord(segmentPositions[segment] + offset)
        return switch (i & 0x3):
            match ==0x0:
                def structOffset :Int := offset + shift(i, 2, 30)
                def dataSize :Int := shift(i, 32, 16)
                def pointerCount :Int := shift(i, 48, 16)
                object structPointer:
                    to _printOn(out):
                        out.print(`<struct @@$structOffset d$dataSize p$pointerCount>`)
                    to type() :Str:
                        return "struct"
                    to offset() :Int:
                        return structOffset
                    to data() :Int:
                        return dataSize
                    to getPointers() :List:
                        def base :Int := structOffset + dataSize
                        return [for o in (base..!(base + pointerCount))
                                makePointer(segment, o)]
            match ==0x1:
                def listOffset :Int := offset + shift(i, 2, 30)
                def listSize :Int := shift(i, 35, 29)
                object listPointer:
                    to _printOn(out):
                        out.print(`<list @@$listOffset d$listSize>`)
                    to type() :Str:
                        return "list"
                    to offset() :Int:
                        return listOffset
                    to elementType() :Int:
                        return shift(i, 32, 3)
                    to size() :Int:
                        return listSize
            match ==0x2:
                object farPointer:
                    to _printOn(out):
                        out.print(`<far $i>`)
                    to type() :Str:
                        return "far"
                    to hasWideLandingPad() :Bool:
                        return 1 == shift(i, 2, 1)
                    to offset() :Int:
                        return shift(i, 3, 29)
                    to segment() :Int:
                        return shift(i, 32, 32)
            match ==0x3 ? (shift(i, 2, 30) == 0x0):
                object capPointer:
                    to _printOn(out):
                        out.print(`<cap $i>`)
                    to type() :Str:
                        return "cap"
                    to index() :Bool:
                        return shift(i, 32, 32)

    def root := makePointer(0, 0)

    return object capn:
        to root():
            return root

def main(_argv, => makeFileResource) as DeepFrozen:
    def handle := makeFileResource("meta.capn")
    return when (def bs := handle<-getContents()) ->
        traceln(`Read in ${bs.size()} bytes`)
        def capn := makeCapn(bs)
        def root := capn.root()
        traceln(`root $root`)
        traceln(`pointers ${root.getPointers()}`)
        def list := root.getPointers()[1]
        traceln(`list ${list.size()} ${list.elementType()}`)
        0
