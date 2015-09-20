# PCG: Permuted congruent generators, based on descriptions at
# http://www.pcg-random.org/ .

def [=> Word] | _ := import.script("lib/words")

def PCGBits :Int := 0x5851f42d4c957f2d
def mask64 :Int := (2 ** 64) - 1
def mask32 :Int := 0xffffffff

def makePCG(initialState :Int, sequence :Int):
    var state :Int := initialState & mask64

    object PCG:
        "A pseudorandom number generator using permuted congruent generators."

        to getAlgorithm() :Str:
            return "PCG"

        to getEntropy():
            def xorShifted :Int := mask32 & (((state >> 18) ^ state) >> 27)
            def rot :Int := (state >> 59) & 0x1f
            def otherRot :Int := 32 - rot
            def rv :Int := mask32 & ((xorShifted >> rot) |
                                     (xorShifted << otherRot))
            def newState :Int := mask64 & (state * PCGBits + (sequence | 1))
            state := newState
            return [32, rv]

    PCG.getEntropy()
    return PCG

[=> makePCG]
