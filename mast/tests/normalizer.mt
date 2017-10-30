#import "lib/monte/normalizer" =~ [=> normalize0]
import "unittest" =~ [=> unittest]
exports ()

def TEST_SCOPE :List[Str] := ["f", "g", "throw", "Int", "DeepFrozen"]
def testANF(assert):

    def tst(ast, s):
        assert.equal(M.toString(anfTransform(ast.expand(), TEST_SCOPE, nastBuilder)[0]), s)

    tst(m`1`, "1")
    tst(m`1 + f(6)`, "let
    _t5 = _makeTempSlot(f0.run(6))
    in 1.add(_t5)")

    tst(m`def a := 1; {f(a, def a := 2, a)}`, "let
    a5 = _makeFinalSlot(1, null)
    _t6 = _makeTempSlot(1)
    in let
    a7 = _makeFinalSlot(2, null)
    _t8 = _makeTempSlot(2)
    in f0.run(a5, _t8, a7)")

    tst(m`def &&foo := f(g); foo.baz()`, "let
    _t5 = _makeTempSlot(f0.run(g1))
    foo6 = _t5
    _t7 = _makeTempSlot(_t5)
    in foo6.baz()")

    tst(m`def via (f) n :Int := g(1)`, "let
    _t5 = _makeTempSlot(g1.run(1))
    _t6 = _makeTempSlot(f0.run(_t5, null))
    _t7 = _makeTempSlot(_guardCoerce(_t6, Int3, null))
    n8 = _makeFinalSlot(_t7, Int3)
    in _t5")

    tst(m`def ej := 0; def [n :Int, m :DeepFrozen] exit ej := g(f)`, "let
    ej5 = _makeFinalSlot(0, null)
    _t6 = _makeTempSlot(0)
    _t7 = _makeTempSlot(g1.run(f0))
    _t8 = _makeTempSlot(_listCoerce(_t7, 2, ej5))
    _t9 = _makeTempSlot(_t8.get(0))
    _t10 = _makeTempSlot(_guardCoerce(_t9, Int3, ej5))
    n11 = _makeFinalSlot(_t10, Int3)
    _t12 = _makeTempSlot(_t8.get(1))
    _t13 = _makeTempSlot(_guardCoerce(_t12, DeepFrozen4, ej5))
    m14 = _makeFinalSlot(_t13, DeepFrozen4)
    in _t7")

    tst (m`def _ :Int exit g := f`, "let
    _t5 = _makeTempSlot(_guardCoerce(f0, Int3, g1))
    in f0")

    tst(m`var a := 0; f(a := g(7))`, "let
    a5 = _makeVarSlot(0, null)
    _t6 = _makeTempSlot(0)
    _t7 = _makeTempSlot(&&a5.get())
    _t8 = _makeTempSlot(g1.run(7))
    _t9 = _makeTempSlot(_t7.put(_t8))
    in f0.run(_t9)")

    tst(m`escape e { f(e); g(e) }`, "escape _t5 {
    let
        e6 = _makeFinalSlot(_t5, null)
        _t7 = _makeTempSlot(f0.run(e6))
        in g1.run(e6)
}")

    tst(m`escape e { f(e); g(e) } catch v { v + 1 }`, "escape _t5 {
    let
        e6 = _makeFinalSlot(_t5, null)
        _t7 = _makeTempSlot(f0.run(e6))
        in g1.run(e6)
} catch _t8 {let
        v9 = _makeFinalSlot(_t8, null)
        in v9.add(1)
}")

    tst(m`try { var x :Int := 3 } finally { f(4) }`, "try {
    let
        _t5 = _makeTempSlot(_guardCoerce(3, Int3, null))
        x6 = _makeVarSlot(_t5, Int3)
        in 3
} finally {
    f0.run(4)
}")

    tst(m`def y := 7; def z := 8; f.baz((g(17)) => y, => z)`, "let
    y5 = _makeFinalSlot(7, null)
    _t6 = _makeTempSlot(7)
    z7 = _makeFinalSlot(8, null)
    _t8 = _makeTempSlot(8)
    _t9 = _makeTempSlot(g1.run(17))
    in f0.baz(_t9 => y5, \"z\" => z7)")

    tst(m`if (f(9)) { g(10) }`, "let
    _t5 = _makeTempSlot(f0.run(9))
    in if (_t5) {
    g1.run(10)
}")

    tst(m`try { f() } catch v { v + 1 }`, "try {
    f0.run()
} catch _t6 {let
        v7 = _makeFinalSlot(_t6, null)
        in v7.add(1)
}")

    tst(m`def foo(x :Int) as DeepFrozen { return foo(x + 1)}`, "let
    _t5 = _makeTempSlot(object implements DeepFrozen4 {
    method run (_t7, _t8) {
            let
                _t9 = _makeTempSlot(_guardCoerce(_t7, Int3, null))
                x10 = _makeFinalSlot(_t9, Int3)
                in escape _t11 {
                let
                    __return12 = _makeFinalSlot(_t11, null)
                    _t13 = _makeTempSlot(x10.add(1))
                    _t14 = _makeTempSlot(foo6.run(_t13))
                    _t15 = _makeTempSlot(__return12.run(_t14))
                    in null
            }
        }
    })
    foo6 = _makeFinalSlot(_t5, DeepFrozen4)
    in _t5")

    tst(m`object foo { match [verb, args, namedArgs] { 3 } }`, "let
    _t5 = _makeTempSlot(object {
    match _t7 {
            let
                _t8 = _makeTempSlot(_listCoerce(_t7, 3, null))
                _t9 = _makeTempSlot(_t8.get(0))
                verb10 = _makeFinalSlot(_t9, null)
                _t11 = _makeTempSlot(_t8.get(1))
                args12 = _makeFinalSlot(_t11, null)
                _t13 = _makeTempSlot(_t8.get(2))
                namedArgs14 = _makeFinalSlot(_t13, null)
                in 3
        }
    })
    foo6 = _makeFinalSlot(_t5, null)
    in _t5")

    tst(m`object foo { method x() :Int { 3 } }`, "let
    _t5 = _makeTempSlot(object {
    method x (_t7) {
            _guardCoerce(3, Int3, null)
        }
    })
    foo6 = _makeFinalSlot(_t5, null)
    in _t5")

def testNormalize(assert):

    def tst(ast, s):
        assert.equal(M.toString(normalize0(ast.expand(), TEST_SCOPE, false)), s)

    tst(m`1`, "1")
    tst(m`1 + f(6)`, "let
    _t5 = _makeTempSlot(f0.run(6))
    in 1.add(_t5)")

    tst(m`def a := 1; {f(a, def a := 2, a)}`, "let
    a⒧ꜰ₀5 = _makeFinalSlot(1, null)
    _t6 = _makeTempSlot(1)
    in let
    a⒧ꜰ₁7 = _makeFinalSlot(2, null)
    _t8 = _makeTempSlot(2)
    in f0.run(a5, _t8, a7)")

    tst(m`def &&foo := f(g); foo.baz()`, "let
    _t5 = _makeTempSlot(f0.run(g1))
    foo⒧ʙ⅋₀6 = _t5
    _t7 = _makeTempSlot(_t5)
    _t8 = _makeTempSlot(&&foo6.get())
    _t9 = _makeTempSlot(_t8.get())
    in _t9.baz()")

    tst(m`def via (f) n :Int := g(1)`,  "let
    _t5 = _makeTempSlot(g1.run(1))
    _t6 = _makeTempSlot(f0.run(_t5, null))
    _t7 = _makeTempSlot(_guardCoerce(_t6, Int3, null))
    n∅8 = _makeFinalSlot(_t7, Int3)
    in _t5")

    tst(m`def ej := 0; def [n :Int, m :DeepFrozen] exit ej := g(f)`, "let
    ej⒧ꜰ₀5 = _makeFinalSlot(0, null)
    _t6 = _makeTempSlot(0)
    _t7 = _makeTempSlot(g1.run(f0))
    _t8 = _makeTempSlot(_listCoerce(_t7, 2, ej5))
    _t9 = _makeTempSlot(_t8.get(0))
    _t10 = _makeTempSlot(_guardCoerce(_t9, Int3, ej5))
    n∅11 = _makeFinalSlot(_t10, Int3)
    _t12 = _makeTempSlot(_t8.get(1))
    _t13 = _makeTempSlot(_guardCoerce(_t12, DeepFrozen4, ej5))
    m∅14 = _makeFinalSlot(_t13, DeepFrozen4)
    in _t7")

    tst (m`def _ :Int exit g := f`, "let
    _t5 = _makeTempSlot(_guardCoerce(f0, Int3, g1))
    in f0")

    tst(m`var a := 0; f(a := g(7))`,  "let
    a⒧ᴠ⅋₀5 = _makeVarSlot(0, null)
    _t6 = _makeTempSlot(0)
    _t7 = _makeTempSlot(&&a5.get())
    _t8 = _makeTempSlot(g1.run(7))
    _t9 = _makeTempSlot(_t7.put(_t8))
    in f0.run(_t9)")

    tst(m`escape e { f(e); g(e) }`, "escape _t5 {
    let
        e⒧ꜰ₀6 = _makeFinalSlot(_t5, null)
        _t7 = _makeTempSlot(f0.run(e6))
        in g1.run(e6)
}")

    # XXX should e and v occupy the same local index?
    tst(m`escape e { f(e); g(e) } catch v { v + 1 }`, "escape _t5 {
    let
        e⒧ꜰ₀6 = _makeFinalSlot(_t5, null)
        _t7 = _makeTempSlot(f0.run(e6))
        in g1.run(e6)
} catch _t8 {let
        v⒧ꜰ₁9 = _makeFinalSlot(_t8, null)
        in v9.add(1)
}")

    tst(m`try { var x :Int := 3 } finally { f(4) }`, "try {
    let
        _t5 = _makeTempSlot(_guardCoerce(3, Int3, null))
        x∅6 = _makeVarSlot(_t5, Int3)
        in 3
} finally {
    f0.run(4)
}")

    tst(m`def y := 7; def z := 8; f.baz((g(17)) => y, => z)`, "let
    y⒧ꜰ₀5 = _makeFinalSlot(7, null)
    _t6 = _makeTempSlot(7)
    z⒧ꜰ₁7 = _makeFinalSlot(8, null)
    _t8 = _makeTempSlot(8)
    _t9 = _makeTempSlot(g1.run(17))
    in f0.baz(_t9 => y5, \"z\" => z7)")

    tst(m`if (f(9)) { g(10) }`, "let
    _t5 = _makeTempSlot(f0.run(9))
    in if (_t5) {
    g1.run(10)
}")

    tst(m`try { f() } catch v { v + 1 }`, "try {
    f0.run()
} catch _t6 {let
        v⒧ꜰ₀7 = _makeFinalSlot(_t6, null)
        in v7.add(1)
}")

    tst(m`def foo(x :Int) as DeepFrozen { return foo(x + 1)}`, "let
    _t5 = _makeTempSlot(object implements DeepFrozen4 {
    method run (_t7, _t8) {
            let
                _t9 = _makeTempSlot(_guardCoerce(_t7, Int3, null))
                x⒧ꜰ₀10 = _makeFinalSlot(_t9, Int3)
                in escape _t11 {
                let
                    __return⒧ꜰ₂12 = _makeFinalSlot(_t11, null)
                    _t13 = _makeTempSlot(x10.add(1))
                    _t14 = _makeTempSlot(foo6.run(_t13))
                    _t15 = _makeTempSlot(__return12.run(_t14))
                    in null
            }
        }
    })
    foo⒧ꜰ₁6 = _makeFinalSlot(_t5, DeepFrozen4)
    in _t5")

    tst(m`object foo { match [verb, args, namedArgs] { 3 } }`, "let
    _t5 = _makeTempSlot(object {
    match _t7 {
            let
                _t8 = _makeTempSlot(_listCoerce(_t7, 3, null))
                _t9 = _makeTempSlot(_t8.get(0))
                verb∅10 = _makeFinalSlot(_t9, null)
                _t11 = _makeTempSlot(_t8.get(1))
                args∅12 = _makeFinalSlot(_t11, null)
                _t13 = _makeTempSlot(_t8.get(2))
                namedArgs∅14 = _makeFinalSlot(_t13, null)
                in 3
        }
    })
    foo∅6 = _makeFinalSlot(_t5, null)
    in _t5")

    tst(m`object foo { method x() :Int { 3 } }`, "let
    _t5 = _makeTempSlot(object {
    method x (_t7) {
            _guardCoerce(3, Int3, null)
        }
    })
    foo∅6 = _makeFinalSlot(_t5, null)
    in _t5")

    tst(m`def foo(var x) {
              def z := 4
              var w :Int := 1
              def baz(y, a) {
                  def z := 0
                  return x(w, y, z, a)
              }
              return baz(x, z)
           }`,"let
    _t5 = _makeTempSlot(object {
    method run (_t7, _t8) {
            let
                x⒧ᴠ₀9 = _makeVarSlot(_t7, null)
                in escape _t10 {
                let
                    __return⒧ꜰ₂11 = _makeFinalSlot(_t10, null)
                    z⒧ꜰ₁12 = _makeFinalSlot(4, null)
                    _t13 = _makeTempSlot(4)
                    _t14 = _makeTempSlot(_guardCoerce(1, Int3, null))
                    w∅15 = _makeVarSlot(_t14, Int3)
                    _t16 = _makeTempSlot(1)
                    _t17 = _makeTempSlot(object {
                    method run (_t19, _t20, _t21) {
                            let
                                y⒧ꜰ₀22 = _makeFinalSlot(_t19, null)
                                a⒧ꜰ₂23 = _makeFinalSlot(_t20, null)
                                in escape _t24 {
                                let
                                    __return⒧ꜰ₃25 = _makeFinalSlot(_t24, null)
                                    z⒧ꜰ₁26 = _makeFinalSlot(0, null)
                                    _t27 = _makeTempSlot(0)
                                    _t28 = _makeTempSlot(x9.run(w15, y22, z26, a23))
                                    _t29 = _makeTempSlot(__return25.run(_t28))
                                    in null
                            }
                        }
                    })
                    baz⒧ꜰ₀18 = _makeFinalSlot(_t17, null)
                    _t30 = _makeTempSlot(_t17)
                    _t31 = _makeTempSlot(baz18.run(x9, z12))
                    _t32 = _makeTempSlot(__return11.run(_t31))
                    in null
            }
        }
    })
    foo∅6 = _makeFinalSlot(_t5, null)
    in _t5")

    def tst2(ast, s):
        assert.equal(
            M.toString(normalize0(
                ast.expand(),
                TEST_SCOPE + ["_makeList", "_makeMap"],
                false)), s)
    tst2(m`def x := 1; def y := 2; def z := 3; object o { method run() { f(x, z, meta.getState()) } }`,  "let
    x∅7 = _makeFinalSlot(1, null)
    _t8 = _makeTempSlot(1)
    y∅9 = _makeFinalSlot(2, null)
    _t10 = _makeTempSlot(2)
    z∅11 = _makeFinalSlot(3, null)
    _t12 = _makeTempSlot(3)
    _t16 = _makeTempSlot(&&x7.get())
    _t17 = _makeTempSlot(_t16.get())
    _t18 = _makeTempSlot(&&z11.get())
    _t19 = _makeTempSlot(_t18.get())
    _t20 = _makeTempSlot(_makeList5.run(\"&&x\", &&x7))
    _t21 = _makeTempSlot(_makeList5.run(\"&&z\", &&z11))
    _t22 = _makeTempSlot(_makeList5.run(_t20, _t21))
    _t23 = _makeTempSlot(_makeMap6.fromPairs(_t22))
    _t13 = _makeTempSlot(object {
    method run (_t15) {
            f0.run(_t17, _t19, _t23)
        }
    })
    o∅14 = _makeFinalSlot(_t13, null)
    in _t13")
unittest([testANF, testNormalize])

