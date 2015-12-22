imports
exports (main)

def concatMap(it, f) :List as DeepFrozen:
    var result := [].diverge()
    for k => v in it:
        result.extend(f(k, v))
    return result.snapshot()

def makeTestDrain(stdout, unsealException, asserter) as DeepFrozen:
    var lastSource := null

    def formatError(err):
        return "\n".join(err[1].reverse()) + "\n\n" + err[0] + "\n"

    return object testDrain:
        to flowingFrom(fount):
            return testDrain

        to receive([k, test]):
            def st :Str := M.toString(test)
            return when (test<-(asserter(st))) ->
                if (lastSource != k):
                    stdout.receive(`$k$\n`)
                    lastSource := k
                stdout.receive(`    $st    OK$\n`)
            catch p:
                if (lastSource != k):
                    stdout.receive(`$k$\n`)
                    lastSource := k
                stdout.receive(`    $st    FAIL$\n`)
                def msg := formatError(unsealException(p, throw))
                stdout.receive(msg + "\n")

        to flowStopped(reason):
            traceln(`flow stopped $reason`)

        to flowAborted(reason):
            traceln(`flow aborted $reason`)

def runTests(collectTests, testDrain, makeIterFount) as DeepFrozen:
    def testInfo := concatMap(
            collectTests(),
            fn k, v { [for t in (v) [k, t]] })
    def fount := makeIterFount(testInfo)
    fount<-flowTo(testDrain)
    return fount.completion()

def makeAsserter() as DeepFrozen:
    var successes :Int := 0
    var fails :Int := 0

    def errors := [].asMap().diverge()

    def logIt(loc :Str, msg :Str):
        def errs := errors.fetch(loc, fn {[]})
        errors[loc] := errs.with(msg)
        return msg

    return object asserter:
        "Track assertions made during unit testing."

        to total() :Int:
            return successes + fails

        to successes() :Int:
            return successes

        to fails() :Int:
            return fails

        to errors() :Map[Str, List[Str]]:
            return errors.snapshot()

        to run(label :Str):
            "Make a new `assert` with the given logging label."

            var todo :Bool := false

            return object assert:
                "Assert stuff."

                to fail(message :Str):
                    "Indicate that an invariant failed, with a customizeable
                     message."

                    if (todo):
                        logIt(label, `SILENCED (todo): $message`)
                    else:
                        fails += 1
                        throw(logIt(label, message))

                to todo(reason :Str):
                    "Neuter this asserter.

                     Messages will still be logged, but failures will not be
                     counted."

                    logIt(label, `TODO: $reason`)
                    todo := true

                to doesNotEject(f):
                    escape e:
                        f(e)
                        successes += 1
                    catch _:
                        assert.fail("Ejector was fired")

                to ejects(f):
                    escape e:
                        f(e)
                        assert.fail("Ejector was not fired")
                    catch _:
                        successes += 1

                to equal(l, r):
                    def isEqual := _equalizer.sameYet(l, r)
                    if (isEqual == null):
                        assert.fail(`Equality not settled: $l ≟ $r`)
                    if (!isEqual):
                        assert.fail(`Not equal: $l != $r`)
                    successes += 1

                to notEqual(l, r):
                    def isEqual := _equalizer.sameYet(l, r)
                    if (isEqual == null):
                        assert.fail(`Equality not settled: $l ≟ $r`)
                    if (isEqual):
                        assert.fail(`Equal: $l == $r`)
                    successes += 1

                to throws(f):
                    try:
                        f()
                        assert.fail("No exception was thrown")
                    catch _:
                        successes += 1

def main(=> makeStdOut, => Timer, => currentProcess, => unsealException,
         => collectTests, => unittest) as DeepFrozen:
    def [=> makeIterFount :DeepFrozen,
         => makeUTF8EncodePump,
         => makePumpTube,
    ] | _ := import("lib/tubes", [=> unittest])

    def args := currentProcess.getArguments()
    for path in args.slice(2, args.size()):
        import.script(path, [=> &&unittest])

    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout<-flowTo(makeStdOut())

    def asserter := makeAsserter()
    def testDrain := makeTestDrain(stdout, unsealException, asserter)

    return when (runTests(collectTests, testDrain, makeIterFount)) ->
        def fails := asserter.fails()
        stdout.receive(`${asserter.total()} tests run, $fails failures$\n`)
        # Exit code: Only returns 0 if there were 0 failures.
        for loc => errors in asserter.errors():
            stdout.receive(`In $loc:$\n`)
            for error in errors:
                stdout.receive(`~ $error$\n`)
        fails.min(1)
