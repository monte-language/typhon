exports (makeRunner)

def makeAsserter() as DeepFrozen:
    var successes :Int := 0
    var fails :Int := 0

    def logIt(loc :Str, msg :Str):
        traceln("Tests:", loc, msg)

    return object asserter:
        "Track assertions made during unit testing."

        to total() :Int:
            return successes + fails

        to successes() :Int:
            return successes

        to fails() :Int:
            return fails

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
                        logIt(label, message)

                to todo(reason :Str):
                    "Neuter this asserter.

                     Messages will still be logged, but failures will not be
                     counted."

                    logIt(label, `TODO: $reason`)
                    todo := true

                to implies(p :Bool, q :Bool):
                    "Assert that p → q."

                    if (p &! q):
                        assert.fail(`Implication failed: $p ↛ $q`)

                to iff(p :Bool, q :Bool):
                    "Assert that p ↔ q."

                    if (p ^ q):
                        assert.fail(`Implication failed: $p ↮ $q`)

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
                    catch p:
                        successes += 1
                        return p
                    assert.fail("No exception was thrown")

                to contains(o, k):
                    if (o._respondsTo("contains", 1)):
                        if (o.contains(k)):
                            successes += 1
                        else:
                            assert.fail(`$o does not contain $k`)
                    else:
                        assert.fail(`$o does not respond to contains`)

                to doesNotContain(o, k):
                    if (o._respondsTo("contains", 1)):
                        if (o.contains(k)):
                            assert.fail(`$o contains $k`)
                        else:
                            successes += 1
                    else:
                        assert.fail(`$o does not respond to contains`)

                to true(f):
                    if (f()):
                        successes += 1
                    else:
                        assert.fail(`$f did not return true`)

                to false(f):
                    if (!f()):
                        successes += 1
                    else:
                        assert.fail(`$f did not return false`)


                # These variants wait for their arguments to resolve before
                # performing their work. As a result, they share the common
                # theme that they will not run unless included in the
                # dependency chains of promises returned from tests. ~ C.

                to willBreak(x):
                    return when (x) ->
                        assert.fail(`Unbroken: !Ref.isBroken($x)`)
                    catch _:
                        successes += 1

                to willEqual(l, r):
                    return when (l, r) ->
                        assert.equal(l, r)

def formatError(err, source, test) as DeepFrozen:
    traceln(`Error in source $source from test $test:`, err)

def either(left, right) as DeepFrozen:
    def [p, r] := Ref.promise()
    left <- _whenMoreResolved(r.resolveRace)
    right <- _whenMoreResolved(r.resolveRace)
    return p

def makeRunner(_stdio, unsealException, Timer) as DeepFrozen:
    "Make a bare-bones test runner."

    def startTest(asserter, k, test):
        def st :Str := M.toString(test)
        def timeout := Ref.whenResolved(
            Timer<-fromNow(1.0),
            fn _ { Ref.broken(`Timeout running $st`) },
        )
        return when (either(timeout, test<-(asserter(st)))) ->
            null
        catch problem:
            traceln.exception(problem)
            if (problem =~ via (unsealException) [_, err]):
                formatError(err, k, test)
                Ref.broken(err)
            else:
                formatError(problem, k, test)
                Ref.broken(problem)

    return def runner.runTests(tests) :Vow[Int]:
        "Run some `tests`. Return the number of failing tests."

        # Do the initial screen update.
        traceln(`Starting test run; will try ${tests.size()} tests.`)
        def asserter := makeAsserter()
        def testIterator := tests._makeIterator()
        def go():
            return escape ej {
                def [_, [k, test]] := testIterator.next(ej)
                when (startTest<-(asserter, k, test)) -> { go<-() }
            }
        # Start iterating through tests.
        return when (go<-()) ->
            def fails :Int := asserter.fails()
            traceln(`All tests successfully ran! There were $fails failures.`)
            # Exit code: Only returns 0 if there were 0 failures.
            fails.min(1)
        catch problem:
            traceln(`Test suite had fatal error:`)
            traceln.exception(problem)
            1
