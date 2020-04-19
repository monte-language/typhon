import "lib/vectors" =~ [=> V, => glsl]
exports (makeSimplexNoise)

# http://staffwww.itn.liu.se/~stegu/simplexnoise/simplexnoise.pdf
# https://github.com/bravoserver/bravo/blob/master/bravo/simplex.py

# These are the 12 3D unit bivectors.
def edges2 :List[DeepFrozen] := [
    V(-1, -1, 0), V(-1, 0, -1), V(-1, 0, 1), V(-1, 1, 0),
    V(0, -1, -1), V(0, -1, 1), V(0, 1, -1), V(0, 1, 1),
    V(1, -1, 0), V(1, 0, -1), V(1, 0, 1), V(1, 1, 0),
]

# The size of the permutation used to configure simplex noise. 2 ** 8 is
# traditional; Bravo used this bigger field because it empirically gave better
# results.
def noiseSeedSize :Int := 2 ** 10

# https://catlikecoding.com/unity/tutorials/simplex-noise/
# Magic number for scaling up 3D noise. Bravo and other sources incorrectly
# use 32; this is actually about 37.837227.
def noiseScale :Double := 3.0.squareRoot() * 8192 / 375

# Vector essentials.
def zero :DeepFrozen := V(0.0, 0.0, 0.0)
def one :DeepFrozen := V(1.0, 1.0, 1.0)
def sumPlus(x, y) as DeepFrozen { return x + y }
def sumDouble :DeepFrozen := V.makeFold(0.0, sumPlus)

def makeSimplexNoise(entropy) as DeepFrozen:
    # Make the list wrap around, and we will need fewer mod operations on the
    # indices when we do lookups.
    def p := entropy.shuffle(_makeList.fromIterable(0..!noiseSeedSize)) * 3
    def edgesSize := edges2.size()
    def gi(ijk):
        def [i, j, k] := V.un(ijk.floor() % noiseSeedSize, null)
        return edges2[p[i + p[j + p[k]]] % edgesSize]
    return object noiseMaker:
        to noise(p):
            # Skew into ijk space. Magic number 1/3=F(3).
            def s := sumDouble(p) / 3
            def ijk := (p + s).floor()
            # Unskew back into xyz space. Magic number 1/6=G(3).
            def t := sumDouble(ijk) / 6
            def xyz0 := p - (ijk - t)
            def [x, y, z] := V.un(xyz0, null)
            # xyz0 determines the cube. Choose the tetrahedron.
            def [ijk1, ijk2] := if (x >= y) {
                if (y >= z) {
                    [V(1.0, 0.0, 0.0), V(1.0, 1.0, 0.0)]
                } else if (x >= z) {
                    [V(1.0, 0.0, 0.0), V(1.0, 0.0, 1.0)]
                } else { [V(0.0, 0.0, 1.0), V(1.0, 0.0, 1.0)] }
            } else {
                if (y < z) {
                    [V(0.0, 0.0, 1.0), V(0.0, 1.0, 1.0)]
                } else if (x < z) {
                    [V(0.0, 1.0, 0.0), V(0.0, 1.0, 1.0)]
                } else { [V(0.0, 1.0, 0.0), V(1.0, 1.0, 0.0)] }
            }
            def corners := [
                zero => xyz0,
                ijk1 => xyz0 - ijk1 + 1/6,
                ijk2 => xyz0 - ijk2 + 2/6,
                # one => xyz0 - 1.0 + 3/6,
                one  => xyz0 - 0.5,
            ]
            var n := 0.0
            for offset => corner in (corners):
                # NB: Bravo and others incorrectly have 0.6, not 0.5, here.
                def t := 0.5 - glsl.dot(corner, corner)
                if (t.aboveZero()):
                    n += t ** 4 * glsl.dot(gi(ijk + offset), corner)
            return n * noiseScale

        to turbulence(p, depth):
            # Depth can be at little as 3; 6 or 7 is quite good.
            var rv := 0.0
            var k := 1
            # NB: I have a doubt. By basic interval analysis, the octaves have
            # intervals [-1,1], [-1/2,1/2], [-1/4,1/4], ... which should sum
            # up to [-2.2]. But apparently this isn't a problem in practice?
            for _ in (0..!depth):
                rv += noiseMaker.noise(p * k) / k
                k *= 2
            return rv
