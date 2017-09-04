import "unittest" =~ [=> unittest]
exports ()

def guardSupersetOfReflexive(assert):
    for g in ([Bool, Bytes, Char, Double, Int, Str]):
        assert.equal(g.supersetOf(g), true)

unittest([
    guardSupersetOfReflexive,
])
