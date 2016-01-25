# Once this is all hooked up we can rip module support out of the runtime and
# the following line can go away.
exports (main)

def safeScopeBindings :DeepFrozen := [for `&&@n` => v in (safeScope) n => v]

def main(=> _findTyphonFile, => makeFileResource, => typhonEval,
         => currentProcess, => unsafeScope, => bench,
         => unsealException, => Timer, => makeStdOut) as DeepFrozen:

    def valMap := [].asMap().diverge()
    def collectedTests := [].diverge()
    object testCollector:
        to get(locus):
            return def testBucket(tests):
                for t in tests:
                    traceln(`TEST $locus $t`)
                    collectedTests.push([locus, t])


    def subload(modname, depMap, => collectTests := false):
        traceln(`Entering $modname`)
        if (modname == "unittest"):
            traceln(`unittest caught`)
            if (collectTests):
                trace(`test collector invoked`)
                return valMap["unittest"] := ["unittest" => testCollector[modname]]
            else:
                return valMap["unittest"] := ["unittest" => fn _ {null}]
        if (modname == "bench"):
            return valMap["bench"] := ["bench" => bench]

        object loader:
            to "import"(name):
                traceln(`import requested: $name`)
                return valMap[name]
        def fname := _findTyphonFile(modname)
        def loadModuleFile():
            traceln(`reading file $fname`)
            def f := makeFileResource(fname)
            def code := f <- getContents()
            def mod := when (code) -> {typhonEval(code, safeScopeBindings)}
            depMap[modname] := mod
            return mod
        def mod := depMap.fetch(modname, loadModuleFile)
        return when (mod) ->
            def deps := promiseAllFulfilled([for d in (mod.dependencies())
                                             {traceln(`load $d`); subload(d, depMap, => collectTests)}])
            when (deps) ->
                valMap[modname] := mod(loader)

    def args := currentProcess.getArguments().slice(2)
    def usage := "Usage: loader run <modname> <args> | loader test <modname>"
    if (args.size() < 1):
        throw(usage)
    switch (args):
        match [=="run", modname] + subargs:
            traceln(`starting load $modname $subargs`)
            def exps := subload(modname, [].asMap().diverge())
            traceln(`loaded $exps`)
            def excludes := ["typhonEval", "_findTyphonFile"]
            def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope)
                                      if (!excludes.contains(n))
                                      n => v]
            return when (exps) ->
                def [=> main] | _ := exps
                traceln(`loaded, running`)
                M.call(main, "run", [subargs], unsafeScopeValues)
        match [=="test"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 subload(modname, [].asMap().diverge(),
                         "collectTests" => true)] +
                [(def testRunner := subload(
                    "testRunner",
                    [].asMap().diverge())),
                 (def tubes := subload(
                     "lib/tubes",
                     [].asMap().diverge()))])
            return when (someMods) ->
                def [=> makeIterFount,
                     => makeUTF8EncodePump,
                     => makePumpTube
                ] | _ := tubes
                def [=> makeAsserter,
                     => makeTestDrain,
                     => runTests] | _ := testRunner

                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout<-flowTo(makeStdOut())

                def asserter := makeAsserter()
                def testDrain := makeTestDrain(stdout, unsealException, asserter)

                when (runTests(collectedTests, testDrain, makeIterFount)) ->
                    def fails := asserter.fails()
                    stdout.receive(`${asserter.total()} tests run, $fails failures$\n`)
                    # Exit code: Only returns 0 if there were 0 failures.
                    for loc => errors in asserter.errors():
                        stdout.receive(`In $loc:$\n`)
                        for error in errors:
                            stdout.receive(`~ $error$\n`)
                    fails.min(1)
        match _:
            throw(usage)
