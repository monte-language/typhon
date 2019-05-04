import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/commandLine" =~ [=> makePrompt]
import "lib/iterators" =~ [=> zip :DeepFrozen]
exports (makeRunner)

def fancyNotEqual(l, r) :Str as DeepFrozen:
    def trail := [`Not equal, because ${M.toQuote(l)} != ${M.toQuote(r)}`].diverge()
    def stack := [[l, r]].diverge()
    while (!stack.isEmpty()):
        switch (stack.pop()):
            # Lists are transparent too, so do lists before transparency to
            # avoid infinite regress.
            match [lList :List, rList :List]:
                if (lList.size() != rList.size()):
                    trail.push(`because lists ${M.toQuote(lList)} and ${M.toQuote(rList)} have different lengths`)
                else:
                    for pair in (zip(lList, rList)):
                        stack.push(pair)
            match [lTrans :Transparent, rTrans :Transparent]:
                trail.push("even though both sides are transparent")
                def [lMaker, lVerb, lArgs, lNamedArgs] := lTrans._uncall()
                def [rMaker, rVerb, rArgs, rNamedArgs] := rTrans._uncall()
                if (lMaker != rMaker):
                    trail.push(`because maker ${M.toQuote(lMaker)} != ${M.toQuote(rMaker)}`)
                if (lVerb != rVerb):
                    trail.push(`because verb ${M.toQuote(lVerb)} != ${M.toQuote(rVerb)}`)
                if (lArgs != rArgs):
                    trail.push("in the arguments of the uncalls")
                    stack.push([lArgs, rArgs])
                if (lNamedArgs != rNamedArgs):
                    trail.push("in the named arguments of the uncalls")
                    stack.push([lNamedArgs, rNamedArgs])
            match [lThing, rThing]:
                if (lThing != rThing):
                    trail.push(`because ${M.toQuote(lThing)} != ${M.toQuote(rThing)}`)
    return ", ".join(trail)

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
                        assert.fail(fancyNotEqual(l, r))
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

def makeRunner(stdio, unsealException, Timer) as DeepFrozen:
    def [prompt, cleanup] := makePrompt(stdio)
    var lastSource := null
    var lastTest := null
    var total :Int := 0
    var running :Int := 0
    var completed :Int := 0
    var errors :Int := 0

    def formatError(err, source, test):
        def line := `
~~~
Error in source $source from test $test:
    ${err[0]}
~~~
`
        prompt.writeLine(UTF8.encode(line, null))

    def updateScreen():
        def counts := `completed/running/errors/total: $completed/$running/$errors/$total`
        def info := ` Last source: $lastSource Last test: $lastTest`
        return prompt.setLine(UTF8.encode(counts + info, null))

    def either(left, right):
        def [p, r] := Ref.promise()
        left <- _whenMoreResolved(r.resolveRace)
        right <- _whenMoreResolved(r.resolveRace)
        return p

    def startTest(asserter, k, test):
        total += 1
        running += 1

        def st :Str := M.toString(test)
        def timeout := Ref.whenResolved(
            Timer.fromNow(60.0),
            fn _ { Ref.broken(`Timeout running $st`) },
        )
        return when (either(timeout, test<-(asserter(st)))) ->
            lastSource := k
            lastTest := test
            running -= 1
            completed += 1
            updateScreen()
        catch problem:
            traceln.exception(problem)
            if (problem =~ via (unsealException) [_, err]):
                formatError(err, k, test)
            else:
                formatError(problem, k, test)

            # Update the screen after formatting and printing the error;
            # this way, we aren't left without a status update for a
            # period of time. ~ C.
            lastSource := k
            lastTest := test
            running -= 1
            errors += 1
            updateScreen()

    return def runner.runTests(tests):
        prompt.writeLine(b`Starting test runner.`)
        def asserter := makeAsserter()
        def testIterator := tests._makeIterator()
        def go():
            return escape ej {
                def [_, [k, test]] := testIterator.next(ej)
                when (startTest<-(asserter, k, test)) -> { go<-() }
            }
        # Do the initial screen update.
        updateScreen()
        # Start iterating through tests.
        return when (go<-()) ->
            def finalMessage := UTF8.encode(`Successfully ran all $total tests!`, null)
            when (prompt.writeLine(finalMessage)) ->
                cleanup<-()
                # Exit code: Only returns 0 if there were 0 failures.
                asserter.fails().min(1)
        catch problem:
            prompt.writeLine(b`Test suite failed: ${M.toString(unsealException(problem))}`)
            when (cleanup<-()) -> { 1 }
