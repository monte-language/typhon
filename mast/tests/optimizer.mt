# m`` has a flag which prevents mixing unexpanded ASTs. Humor it for now and
# pre-expand all specimens. ~ C.
def specimens := [for [this, that] in ([
    [m`42`, m`42`],
    [m`escape _ {x}`, m`x`],
    [m`escape ej {x}`, m`x`],
]) [this.expand(), that.expand()]]

for [this, that] in (specimens):
    def testOptimizer(assert):
        assert.equal(this.mix().canonical(), that.canonical())
    unittest([testOptimizer])
