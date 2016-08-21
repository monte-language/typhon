import "unittest" =~ [=> unittest]
exports ()

def testHarnessEventualSend(assert):
    return 6<-multiply(7)

def testHarnessWhenNull(assert):
    return when (null) -> { null }

def testHarnessWhenSend(assert):
    return when (6<-multiply(7)) -> { null }

def testHarnessPromise(assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return p

def testHarnessPromiseLater(assert):
    def [p, r] := Ref.promise()
    r<-resolve(42)
    return p

def testHarnessWhenPromise(assert):
    def [p, r] := Ref.promise()
    r.resolve(42)
    return when (p) -> { null }

def testHarnessWhenPromiseLater(assert):
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
