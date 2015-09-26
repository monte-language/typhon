
def test_transparent_success(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    def z :DeepFrozen := 1
    def makeFoo(x, y, => baz, (z) => boz) as DeepFrozen implements makerAuditor:
        def doIt(a, b):
            return [a, b]
        return object foo implements Selfless, valueAuditor:
            to baz():
                return doIt(x, y)
            to _uncall():
                return serializer(makeFoo, [x, y], [=> baz, z => boz])
            to blee():
                return doIt(z, null)
    def val :DeepFrozen := makeFoo(1, 2, "baz" => 3, 1 => "blee")
    assert.equal(val, makeFoo(1, 2, "baz" => 3, 1 => "blee"))


def test_makerauditor_reuse(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    def makeFoo() implements makerAuditor:
        return object foo implements valueAuditor:
            to _uncall():
                return serializer(makeFoo, [])

    assert.throws(fn {object makeFoo2 implements makerAuditor {}})

def test_require_deepfrozen_bindings(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    def z := 1
    assert.throws(fn {
        def makeFoo(x, y) implements makerAuditor {
            return object foo implements valueAuditor {
                to _uncall() {
                    return serializer(makeFoo, [x, y])
                }
                to blee() {
                    return z
                }
            }
        }
    })

def test_require_valueauditor(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    assert.throws(fn {
        def makeFoo(x, y) implements makerAuditor {
            return object foo {
                to _uncall() {
                    return serializer(makeFoo, [x, y])
                }
            }
        }
    })

def test_require_serializer(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    assert.throws(fn {
        def makeFoo(x, y) implements makerAuditor {
            return object foo implements valueAuditor {
                to _uncall() {
                    return [makeFoo, "run", [x, y], [].asMap()]
                }
            }
        }
    })

def test_require_finalpatts(assert):
    def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
    assert.throws(fn {
        def makeFoo(x, var y) implements makerAuditor {
            return object foo implements valueAuditor {
                to _uncall() {
                    return serializer(makeFoo, [x, y])
                }
            }
        }
    })

unittest([test_transparent_success, test_makerauditor_reuse, test_require_deepfrozen_bindings,
          test_require_valueauditor, test_require_serializer, test_require_finalpatts,])
