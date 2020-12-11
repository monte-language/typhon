import "unittest" =~ [=> unittest :Any]
exports ()

def refLoopStackOverflow(assert):
    def [p, r] := Ref.promise()
    return when (r<-resolve(p)) ->
        # Any method call or other examination should provoke the bug. It is
        # fine if the promise is unresolved and also fine if it is broken, so
        # we'll do one of the things that lets us get away with either. ~ C.
        `$p`
    catch problem:
        null

unittest([refLoopStackOverflow])
