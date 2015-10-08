imports
exports (main)

def main(=> makeStdOut, => Timer, => currentProcess, => unsealException, => collectTests) as DeepFrozen:
    def [=> makeUTF8EncodePump] | _ := import.script("lib/tubes/utf8")
    def [=> makePumpTube] := import.script("lib/tubes/pumpTube")

    def args := currentProcess.getArguments()
    for path in args.slice(2, args.size()):
        import.script(path)

    def errors := [].asMap().diverge()

    var successes := 0
    var fails := 0

    def logIt(loc, msg):
        def errs := errors.fetch(loc, fn {[]})
        errors[loc] := errs.with(msg)
        return msg

    def makeAsserter(label):
        return object assert:
            to doesNotEject(f):
                escape e:
                    f(e)
                catch _:
                    throw(logIt(label, "Ejector was fired"))

            to ejects(f):
                escape e:
                   f(e)
                   throw(logIt(label, "Ejector was not fired"))

            to equal(l, r):
                def isEqual := __equalizer.sameYet(l, r)
                if (isEqual == null):
                    throw(logIt(label, `Equality not settled: $l ?= $r`))
                if (!isEqual):
                    throw(logIt(label, `Not equal: $l != $r`))

            to notEqual(l, r):
                def isEqual := __equalizer.sameYet(l, r)
                if (isEqual == null):
                    throw(logIt(label, `Equality not settled: $l ?= $r`))
                if (isEqual):
                    throw(logIt(label, `Equal: $l == $r`))

            to throws(f):
                try:
                    f()
                    throw(logIt(label, "No exception was thrown"))
                catch _:
                    null

    def formatError(err):
        return "\n".join(err[1].reverse()) + "\n\n" + err[0] + "\n"

    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout<-flowTo(makeStdOut())

    def concatMap(it, f):
        var result := [].diverge()
        for k => v in it:
            result.extend(f(k, v))
        return result.snapshot()

    def runTests():
        def testInfo := concatMap(
                collectTests(),
                fn k, v { [for t in (v) [k, t]] })
        var lastSource := null
        for [k, t] in testInfo:
            if (lastSource != k):
                stdout.receive(`$k$\n`)
                lastSource := k
            def st := M.toString(t)
            stdout.receive(`    $st`)
            try:
                t(makeAsserter(st))
                stdout.receive("    OK\n")
                successes += 1
            catch p:
                stdout.receive("    FAIL\n")
                fails += 1
                def msg := formatError(unsealException(p, throw))
                logIt(st, msg)
                stdout.receive(msg + "\n")

    return when (def runTime := Timer.trial(runTests)) ->
        stdout.receive(`${successes + fails} tests run, ${fails} failures` +
                       ` in ${runTime} s$\n`)
        fails.min(1)

