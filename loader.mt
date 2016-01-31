def safeScopeBindings :DeepFrozen := [for `&&@n` => v in (safeScope) n => v]

def main():

    def valMap := [].asMap().diverge()
    def collectedTests := [].diverge()
    def collectedBenches := [].diverge()
    object testCollector:
        to get(locus):
            return def testBucket(tests):
                for t in tests:
                    collectedTests.push([locus, t])

    object benchCollector:
        to get(locus):
            return def benchBucket(aBench, name :Str):
                collectedBenches.push([`$locus: $name`, aBench])

    object loader:
            to "import"(name):
                return valMap[name]

    def subload(modname, depMap,
                => collectTests := false,
                => collectBenchmarks := false):
        if (modname == "unittest"):
            if (collectTests):
                trace(`test collector invoked`)
                return valMap["unittest"] := ["unittest" => testCollector[modname]]
            else:
                return valMap["unittest"] := ["unittest" => fn _ {null}]
        if (modname == "bench"):
            if (collectBenchmarks):
                return valMap["bench"] := ["bench" => benchCollector[modname]]
            else:
                return valMap["bench"] := ["bench" => fn _, _ {null}]

        def fname := _findTyphonFile(modname)
        if (fname == null):
            throw(`Unable to locate $modname`)
        def loadModuleFile():
            def code := makeFileResource(fname).getContents()
            def mod := when (code) -> {typhonEval(code, safeScopeBindings)}
            depMap[modname] := mod
            return mod
        def mod := depMap.fetch(modname, loadModuleFile)
        return when (mod) ->
            def deps := promiseAllFulfilled([for d in (mod.dependencies())
                                              subload(d, depMap, => collectTests,
                                                      => collectBenchmarks)])
            when (deps) ->
                def pre := collectedTests.size()
                valMap[modname] := mod(loader)
                if (collectTests):
                    traceln(`collected ${collectedTests.size() - pre} tests`)
                valMap[modname]
    def args := currentProcess.getArguments().slice(2)
    def usage := "Usage: loader run <modname> <args> | loader test <modname>"
    if (args.size() < 1):
        throw(usage)
    switch (args):
        match [=="run", modname] + subargs:
            def exps := subload(modname, [].asMap().diverge())
            def excludes := ["typhonEval", "_findTyphonFile", "bench"]
            def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope)
                                      if (!excludes.contains(n))
                                      n => v].with("packageLoader", loader)
            return when (exps) ->
                def [=> main] | _ := exps
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
                stdout <- flowTo(makeStdOut())

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
        match [=="bench"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 subload(modname, [].asMap().diverge(),
                         "collectBenchmarks" => true)] +
                [(def benchRunner := subload(
                    "benchRunner",
                    [].asMap().diverge()))])
            return when (someMods) ->
                def [=> runBenchmarks] := benchRunner
                when (runBenchmarks(collectedBenches, bench,
                                    makeFileResource("bench.html"))) ->
                    traceln(`Benchmark report written to bench.html.`)

        match _:
            throw(usage)
main()
