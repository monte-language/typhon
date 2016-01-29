import "unittest" =~ [=> unittest]
exports ()
def noFail(x):
    return x + 1

def doIt(x, => FAIL):
    return FAIL("message")

def sync_nofail(assert):
    escape e:
        noFail(1, "FAIL" => e)
    catch p:
        throw("Ejector should not be invoked")

def async_nofail(assert):
    def nope(p):
        throw("Failure arg should not be invoked")
    return noFail <- (1, "FAIL" => nope)

def sync_fail_implicit(assert):
    assert.throws(fn {doIt(1)})

def async_fail_implicit(assert):
    return when (doIt <- (1)) ->
        throw("FAIL arg not invoked")
    catch p:
        assert.equal(p, "message")


unittest([sync_nofail, async_nofail, sync_fail_implicit, async_fail_implicit])
