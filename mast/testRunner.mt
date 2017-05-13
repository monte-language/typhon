import "lib/iterators" =~ [=> zip :DeepFrozen]
exports (makeAsserter, makeTestDrain, runTests)

# This magic sequence clears the current line of stdout and moves the cursor
# to the beginning of the line. ~ C.
def clearLine :Str := "\x1b[2K\r"

def makeTestDrain(stdout, unsealException, asserter) as DeepFrozen:
    var lastSource := null
    var lastTest := null
    var total :Int := 0
    var running :Int := 0
    var completed :Int := 0
    var errors :Int := 0

    def formatError(err, source, test):
        def line := `Error in source $source from test $test:$\n`
        def l := [line] + err[1].reverse() + ["", err[0], ""]
        stdout.receive("\n".join(l))

    def updateScreen():
        def counts := `completed/running/errors/total: $completed/$running/$errors/$total`
        def info := ` Last source: $lastSource Last test: $lastTest`
        stdout.receive(clearLine + counts + info)

    def [p, r] := Ref.promise()

    var complete :Bool := false
    def maybeComplete():
        if (complete && running == 0):
            r.resolve(null)

    return object testDrain:
        to flowingFrom(_fount):
            return testDrain

        to receive([k, test]):
            total += 1
            running += 1
            updateScreen()
            def st :Str := M.toString(test)
            return when (test<-(asserter(st))) ->
                lastSource := k
                lastTest := test
                running -= 1
                completed += 1
                updateScreen()
                maybeComplete()
            catch p:
                formatError(unsealException(p, throw), k, test)

                # Update the screen after formatting and printing the error;
                # this way, we aren't left without a status update for a
                # period of time. ~ C.
                lastSource := k
                lastTest := test
                running -= 1
                errors += 1
                updateScreen()
                maybeComplete()

        to flowStopped(_reason):
            complete := true

        to flowAborted(_reason):
            complete := true

        to completion():
            return p

def runTests(testInfo, testDrain, makeIterFount) as DeepFrozen:
    def fount := makeIterFount(testInfo)
    fount<-flowTo(testDrain)
    return testDrain.completion()

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
                        throw(logIt(label, message))

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
                        assert.fail("No exception was thrown")
                    catch _:
                        successes += 1

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
                    catch problem:
                        if (Ref.isBroken(l)):
                            assert.fail(`Cannot be equal: Ref.isBroken($l)`)
                        else if (Ref.isBroken(r)):
                            assert.fail(`Cannot be equal: Ref.isBroken($r)`)
                        else:
                            throw(problem)
