import "unittest" =~ [=> unittest]
exports ()
def testFlexMapPrinting(assert):
    assert.equal(M.toString([].asMap().diverge()), "[].asMap().diverge()")
    assert.equal(M.toString([5 => 42].diverge()), "[5 => 42].diverge()")

def testFlexMapRemoveKey(assert):
    def m := [1 => 2, 3 => 4].diverge()
    m.removeKey(1)
    assert.equal(m.contains(1), false)
    assert.equal(m.contains(3), true)

unittest([
    testFlexMapPrinting,
    testFlexMapRemoveKey,
])

