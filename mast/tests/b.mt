import "unittest" =~ [=> unittest]

def testQuasiValues(assert):
    def v := b`value`
    assert.equal(b`such value`, b`such $v`)

def testQuasiPatterns(assert):
    def v := b`123`

    def b`@{head}23` := v
    assert.equal(head, b`1`)

    def b`1@{middle}3` := v
    assert.equal(middle, b`2`)

    def b`12@{tail}` := v
    assert.equal(tail, b`3`)

    def sep := b`\r\n`
    def b`@car$sep@cdr` := b`first\r\nsecond\r\nthird`
    assert.equal(car, b`first`)
    assert.equal(cdr, b`second\r\nthird`)

unittest([
    testQuasiValues,
    testQuasiPatterns,
])
