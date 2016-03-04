exports (makeAsserter, makeTestDrain, runTests)

def makeTestDrain(stdout, unsealException, asserter, unsafeScope) as DeepFrozen:
    var lastSource := null

    def formatError(err):
        return "\n".join(err[1].reverse()) + "\n\n" + err[0] + "\n"

    return object testDrain:
        to flowingFrom(fount):
            return testDrain

        to receive([k, test]):
            def st :Str := M.toString(test)
            return when (M.call(test, "run", [asserter(st)], unsafeScope)) ->
                if (lastSource != k):
                    stdout.receive(`$k$\n`)
                    lastSource := k
                stdout.receive(`    $st    OK$\n`)
            catch p:
                asserter.addFail()
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

def runTests(testInfo, testDrain, makeIterFount) as DeepFrozen:
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

        to addFail():
            fails += 1

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
