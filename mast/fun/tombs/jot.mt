exports (jot)

# https://esolangs.org/wiki/Jot

def Jot :DeepFrozen := Int

def s :DeepFrozen := m`fn x { fn y { fn z { x(z)(y(z)) } } }`
def k :DeepFrozen := m`fn x { fn _ { x } }`
def i :DeepFrozen := m`fn x { x }`
def zero(F :DeepFrozen) as DeepFrozen { return m`$F($s)($k)` }
def one(F :DeepFrozen) as DeepFrozen { return m`fn x { fn y { $F(x(y)) } }` }

object jot as DeepFrozen:
    to id() :Jot:
        return 0

    to compile(j :Jot, _ej) :DeepFrozen:
        var rv := i
        for i in (0..!j.bitLength()):
            rv := ((j >> i) & 1).isZero().pick(zero, one)(rv)
        return rv

    to compileToSKI(j :Jot, _ej) :DeepFrozen:
        var rv := "i"
        for i in (0..!j.bitLength()):
            if (((j >> i) & 1) == 1):
                rv := ["s", ["k", rv]]
            else:
                rv := [[rv, "s"], "k"]
        return rv
