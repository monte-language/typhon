exports (jot, jotToMonte, jotToSKI)

# https://esolangs.org/wiki/Jot

object jot as DeepFrozen:
    to signature():
        return "jot"

    to guard():
        return Int

    to id() :Int:
        return 0

    to compose(left :Int, right :Int) :Int:
        def w := left.bitWidth()
        (right << (w + 1)) | (1 << w) | left

def s :DeepFrozen := m`fn x { fn y { fn z { x(z)(y(z)) } } }`
def k :DeepFrozen := m`fn x { fn _ { x } }`
def i :DeepFrozen := m`fn x { x }`
def zero(F :DeepFrozen) as DeepFrozen { return m`$F($s)($k)` }
def one(F :DeepFrozen) as DeepFrozen { return m`fn x { fn y { $F(x(y)) } }` }

object jotToMonte as DeepFrozen:
    to signature():
        return ["jot", "monte"]

    to run(j :Int) :DeepFrozen:
        var rv := i
        for i in (0..!j.bitLength()):
            rv := ((j >> i) & 1).isZero().pick(zero, one)(rv)
        return rv

object jotToSKI as DeepFrozen:
    to signature():
        return ["jot", "ski"]

    to run(j :Int) :DeepFrozen:
        var rv := "i"
        for i in (0..!j.bitLength()):
            if (((j >> i) & 1) == 1):
                rv := ["s", ["k", rv]]
            else:
                rv := [[rv, "s"], "k"]
        return rv
