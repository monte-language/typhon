# m`` has a flag which prevents mixing unexpanded ASTs. Humor it for now and
# pre-expand all specimens. ~ C.
def specimens := [for [this, that] in ([
    [m`42`, m`42`],
    [m`def _ := x`, m`x`],
    [m`def _ :Int exit ej := x`, m`Int.coerce(x, ej)`],
    [m`def [a, b] := [x, y]`, m`def a := x; def b := y`],
    [m`def x exit ej := 42`, m`def x := 42`],
    [m`escape _ {x}`, m`x`],
    [m`escape ej {x}`, m`x`],
    [m`escape outer { escape inner {x}}`, m`x`],
    [m`escape ej {ej.run(x)}`, m`x`],
    [m`escape ej {ej.run(x); y}`, m`x`],
]) [this.expand(), that.expand()]]

for [this, that] in (specimens):
    def testOptimizer(assert):
        assert.equal(this.mix().canonical(), that.canonical())
    unittest([testOptimizer])
