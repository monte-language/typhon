import "lib/doubles" =~ [=> dragon4]
exports (makeUnitSlot)

def tiny :Str := "⁰¹²³⁴⁵⁶⁷⁸⁹"
def offset :Int := '0'.asInteger()

def tinyInt(i :(Int > 0)) :Str as DeepFrozen:
    return _makeStr.fromChars([for c in (`$i`) tiny[c.asInteger() - offset] ])

def formatDims(ds) as DeepFrozen:
    def tops := [].diverge()
    def bottoms := [].diverge()
    for d => i in (ds):
        if (i > 1):
            tops.push(d + tinyInt(i))
        else if (i == 1):
            tops.push(d)
        else if (i < -1):
            bottoms.push(d + tinyInt(-i))
        else if (i == -1):
            bottoms.push(d)
        else:
            throw("implementation error")
    def ts := if (tops.isEmpty()) { "1" } else { " ".join(tops) }
    return if (bottoms.isEmpty()) { ts } else { ts + "/" + " ".join(bottoms) }

def makeUnitSlot(magnitude :Double, dimensions :Map[Str, Int]) as DeepFrozen:
    return object unitSlot:
        to _printOn(out):
            out.print(`${dragon4(magnitude)} ${formatDims(dimensions)}`)

        to get():
            return magnitude

        to getGuard():
            return Double

        to getDimensions() :Map[Str, Int]:
            return dimensions

        to add(other):
            def dims := other.getDimensions()
            if (dimensions != dims):
                throw(`Dimensional mismatch: ${formatDims(dimensions)} != ${formatDims(dims)}`)
            return makeUnitSlot(magnitude + other.get(), dimensions)

        to multiply(other):
            if (other =~ d :Double):
                return makeUnitSlot(magnitude * d, dimensions)

            def dims := other.getDimensions()
            def ks := (dimensions.getKeys() + dims.getKeys()).sort()
            def z() { return 0 }
            def ds := [].diverge()
            for d in (ks):
                def i := dimensions.fetch(d, z) + dims.fetch(d, z)
                if (i != 0) { ds.push([d, i]) }
            return makeUnitSlot(magnitude * other.get(),
                                _makeMap.fromPairs(ds))

        to approxDivide(other):
            return unitSlot * other.reciprocal()

        to reciprocal():
            return makeUnitSlot(magnitude.reciprocal(),
                                [for d => i in (dimensions) d => -i])

        to pow(exponent :Int):
            return makeUnitSlot(magnitude ** exponent,
                                [for d => i in (dimensions) d => i * exponent])

# https://frinklang.org/frinkdata/units.txt

# Fine structure constant, computed two ways.

# 1: elementarycharge^2 / (2 epsilon0 h c)

def &c := makeUnitSlot(299792458.0, ["m" => 1, "s" => -1])
def &elementarycharge := makeUnitSlot(1.602176634e-19, ["C" => 1])
def &epsilon0 := makeUnitSlot(8.8541878128e-12, ["F" => 1, "m" => -1])
def &h := makeUnitSlot(6.62607015e-34, ["J" => 1, "s" => 1])

def &alpha1 := (&elementarycharge ** 2) / (&epsilon0 * &h * &c * 2.0)
traceln(`alpha1 ${&alpha1}`)

# 2: mu0 c elementarycharge^2 / (2 h)

def &mu0 := makeUnitSlot(1.25663706212e-6, ["N" => 1, "A" => -2])

def &alpha2 := &mu0 * &c * (&elementarycharge ** 2) / (&h * 2.0)
traceln(`alpha2 ${&alpha2}`)

# Bohr radius, computed two ways.
# 1: hbar / (alpha electronmass c)

def &pi := makeUnitSlot(0.0.arcCosine() * 2.0, [].asMap())
def &electronmass := makeUnitSlot(9.1093837015e-31, ["kg" => 1])

def &hbar := &h / (&pi * 2.0)
def &bohrradius11 := &hbar / (&alpha1 * &electronmass * &c)
traceln(`bohrradius11 ${&bohrradius11}`)

def &bohrradius12 := &hbar / (&alpha2 * &electronmass * &c)
traceln(`bohrradius12 ${&bohrradius12}`)

# 2: alpha / (4 pi Rinfinity)

def &Rinfinity := &electronmass * &elementarycharge ** 4 / (
    (&epsilon0 ** 2) * (&h ** 3) * &c * 8.0)

def &bohrradius21 := &alpha1 / (&pi * &Rinfinity * 4.0)
traceln(`bohrradius21 ${&bohrradius21}`)

def &bohrradius22 := &alpha2 / (&pi * &Rinfinity * 4.0)
traceln(`bohrradius22 ${&bohrradius22}`)
