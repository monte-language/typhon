import "unittest" =~ [=> unittest :Any]
exports ()

def testHarnessEventualSend(_assert):
    return 6<-multiply(7)

def testHarnessWhenNull(_assert):
    return when (null) -> { null }

def testHarnessWhenSend(_assert):
    return when (6<-multiply(7)) -> { null }

def testHarnessPromise(_assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return p

def testHarnessPromiseLater(_assert):
    def [p, r] := Ref.promise()
    r<-resolve(42)
    return p

def testHarnessWhenPromise(_assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return when (p) -> { null }

def testHarnessWhenPromiseLater(_assert):
    def [p, r] := Ref.promise()
    r<-resolve(42)
    return when (p) -> { null }

unittest([
    testHarnessEventualSend,
    testHarnessWhenNull,
    testHarnessWhenSend,
    testHarnessPromise,
    testHarnessPromiseLater,
    testHarnessWhenPromise,
    testHarnessWhenPromiseLater,
])

def vowInt(assert):
    def [p :Vow[Int], r] := Ref.promise()
    r.resolve(42)
    return when (p) -> { assert.equal(p, 42) }

def vowIntBroken(assert):
    def [p :Vow[Int], r] := Ref.promise()
    r.smash("test")
    return when (p) -> { assert.equal(p, 42) } catch _ {
        assert.equal(true, Ref.isBroken(p))
        assert.equal("test", Ref.optProblem(p))
    }

unittest([
    vowInt,
    vowIntBroken,
])

def whenSuccess(assert):
    "success / success / nothing -> value"
    def p
    var success := false
    var fail := false
    def result := Ref."when"(p, fn v { success := v }, fn e { fail := e })
    bind p := true
    return Ref.whenResolved(result, fn _ {
        assert.equal(result, true)
        assert.equal(success, true)
        assert.equal(fail, false)
    })

def whenBrokenRecovery(assert):
    "success / broken promise / value -> value"
    def p
    def b := Ref.broken("broken")
    var success := false
    var fail := false
    def result := Ref."when"(
        p,
        fn v { success := v; b },
        fn e { fail := e; true }
    )
    bind p := true
    return Ref.whenResolved(result, fn _ {
        assert.equal(result, true)
        assert.equal(success, true)
        assert.equal(Ref.optProblem(fail), Ref.optProblem(b))
    })

def whenExceptionRecovery(assert):
    "success / exception / value -> value"
    def p
    var success := false
    var fail := false
    def result := Ref."when"(
        p,
        fn v { success := v; throw("fail") },
        fn e { fail := e; true },
    )
    bind p := true
    return Ref.whenResolved(result, fn _ {
        assert.equal(result, true)
        assert.equal(success, true)
        assert.equal(M.toString(Ref.optProblem(fail)), "<sealed exception>")
    })

def whenBrokenBroken(assert):
    "success / broken promise1 / broken promise2 -> broken promise2"
    def p
    def b1 := Ref.broken("broken1")
    def b2 := Ref.broken("broken2")
    var success := false
    var fail := false
    def result := Ref."when"(
        p,
        fn v { success := v; b1 },
        fn e { fail := e; b2 }
    )
    bind p := true
    return Ref.whenResolved(result, fn _ {
        assert.equal(Ref.optProblem(result), Ref.optProblem(b2))
        assert.equal(success, true)
        assert.equal(Ref.optProblem(fail), Ref.optProblem(b1))
    })

def whenExceptionBroken(assert):
    "success / exception / broken promise -> broken promise"
    def p
    def b := Ref.broken("broken")
    var success := false
    var fail := false
    def result := Ref."when"(
        p,
        fn v { success := v; throw("failure") },
        fn e { fail := e; b }
    )
    bind p := true
    return Ref.whenResolved(result, fn _ {
        assert.equal(Ref.optProblem(result), Ref.optProblem(b))
        assert.equal(success, true)
        assert.equal(M.toString(Ref.optProblem(fail)), "<sealed exception>")
    })

def whenBroken(assert):
    "only fail arm is called with broken promise as input"
    def p
    def b := Ref.broken("broken")
    var success := false
    var fail := false
    def result := Ref."when"(
        p,
        fn v { success := v; true },
        fn e { fail := e; false }
    )
    bind p := b
    return Ref.whenResolved(result, fn _ {
        assert.equal(result, false)
        assert.equal(success, false)
        assert.equal(Ref.optProblem(fail), Ref.optProblem(b))
    })
unittest([
    whenSuccess,
    whenBrokenRecovery,
    whenExceptionRecovery,
    whenBrokenBroken,
    whenExceptionBroken,
    whenBroken,
])
