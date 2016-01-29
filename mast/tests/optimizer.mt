import "unittest" =~ [=> unittest]
exports ()

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
    [m`escape ej {ej.run(x(ej))}`, m`escape ej {x(ej)}`],
    [m`object o {to m() {return x}}`, m`object o {method m() {x}}`],
    [m`f(); x; y`, m`f(); y`],
    [m`def x := 42; y; x`, m`42`],
    [m`if (test) {r.v(x)} else {r.v(y)}`, m`r.v(if (test) {x} else {y})`],
    [m`if (test) {n := x} else {n := y}`, m`n := if (test) {x} else {y}`],
    [m`if (x) {2 + 2}`, m`if (x) {4}`],
    [m`2 + 2`, m`4`],
    [m`r.v(2 + 2)`, m`r.v(4)`],
    [m`if (false | true) {x} else {y}`, m`x`],
]) [this.expand(), that.expand()]]

for [this, that] in (specimens):
    def testOptimizer(assert):
        assert.equal(this.mix().canonical(), that.canonical())
    unittest([testOptimizer])
