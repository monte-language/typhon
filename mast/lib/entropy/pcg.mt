exports (makePCG)

# PCG: Permuted congruent generators, based on descriptions from
# http://www.pcg-random.org/ .

def PCGBits :Int := 0x5851f42d4c957f2d
def mask64 :Int := (2 ** 64) - 1
def mask32 :Int := 0xffffffff

def makePCG(initialState :Int, sequence :Int) as DeepFrozen:
    "
    Make a pseudorandom number generator.

    The `initialState` chooses a generator and is analogous to a seed. The
    `sequence` indexes the initial state space, enabling the production of
    multiple distinct generators from a single initial state.

    Use system entropy to choose the initial state. The sequence index may be
    as simple as a counter starting at 0 without compromising the randomness
    properties of the generator.
    "

    var state :Int := initialState & mask64
    # Fixup from the original design, which used `sequence | 1`. This version
    # doesn't accidentally coalesce adjacent sequences.
    def index :Int := (sequence << 1) | 1

    object PCG:
        "A pseudorandom number generator using permuted congruent generators."

        to getAlgorithm() :Str:
            return "PCG (Permuted Congruent Generator)"

        to getEntropy():
            def xorShifted :Int := mask32 & (((state >> 18) ^ state) >> 27)
            def rot :Int := (state >> 59) & 0x1f
            def otherRot :Int := 32 - rot
            def rv :Int := mask32 & ((xorShifted >> rot) |
                                     (xorShifted << otherRot))
            def newState :Int := mask64 & (state * PCGBits + index)
            state := newState
            return [32, rv]

    # For our version of the generator, we must take an initial step in order
    # to avoid the problem where the initial output of the generator can be
    # run in reverse to obtain the seed.
    PCG.getEntropy()
    return PCG
