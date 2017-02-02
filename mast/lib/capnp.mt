exports (main)

def mask(width :Int) :Int as DeepFrozen:
    return (1 << width) - 1

def shift(i :Int, offset :Int, width :Int) :Int as DeepFrozen:
    return (i >> offset) & mask(width)

def makePointer(i :Int) as DeepFrozen:
    return switch (i & 0x3):
        match ==0x0:
            object structPointer:
                to type() :Str:
                    return "struct"
                to offset() :Int:
                    return shift(i, 2, 30)
                to data() :Int:
                    return shift(i, 32, 16)
                to pointers() :Int:
                    return shift(i, 48, 16)
        match ==0x1:
            object listPointer:
                to type() :Str:
                    return "list"
                to offset() :Int:
                    return shift(i, 2, 30)
                to elementType() :Int:
                    return shift(i, 32, 3)
                to size() :Int:
                    return shift(i, 35, 29)
        match ==0x2:
            object farPointer:
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
                to type() :Str:
                    return "cap"
                to index() :Bool:
                    return shift(i, 32, 32)

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
            acc |= bs[i * 8 + j]
        return acc

    def segmentSizes :List[Int] := {
        def count := get32LE(0) + 1
        [for i in (0..!count) get32LE(i + 1)]
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

    return object capn:
        to root():
            return makePointer(getWord(segmentPositions[0]))

def main(_argv, => makeFileResource) as DeepFrozen:
    def handle := makeFileResource("meta.capn")
    return when (def bs := handle<-getContents()) ->
        traceln(`Read in ${bs.size()} bytes`)
        def capn := makeCapn(bs)
        def root := capn.root()
        traceln(`root $root`)
        traceln(`pointer ${root.offset()} ${root.data()} ${root.pointers()}`)
        0
