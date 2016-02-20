def safeScopeBindings :DeepFrozen := [for `&&@n` => v in (safeScope) n => v]

object moduleGraphUnsatisfiedExit as DeepFrozen:
    "An unsatisfied exit point on a module configuration graph."

object moduleGraphLiveExit as DeepFrozen:
    "A live (non-`DeepFrozen`) exit point on a module configuration graph."

def makeModuleConfiguration(module :DeepFrozen,
                            knownDependencies :Map[Str, DeepFrozen]) as DeepFrozen:
    return object moduleConfiguration as DeepFrozen:
        "Information about the metadata and state of a module."

        to _printOn(out):
            out.print(`moduleConfiguration($knownDependencies)`)

        to getModule() :DeepFrozen:
            return module

        to dependencyNames() :List[Str]:
            return module.dependencies()

        to dependencyMap() :Map[Str, DeepFrozen]:
            return knownDependencies

        to withDependency(petname :Str, dep :DeepFrozen) :DeepFrozen:
            return makeModuleConfiguration(module,
                knownDependencies.with(petname, dep))

        to withLiveDependency(petname :Str) :DeepFrozen:
            return makeModuleConfiguration(module,
                knownDependencies.with(petname, moduleGraphLiveExit))

        to withMissingDependency(petname :Str) :DeepFrozen:
            return makeModuleConfiguration(module,
                knownDependencies.with(petname, moduleGraphUnsatisfiedExit))

        to run(loader):
            return module(loader)

def main():

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

    def makeLoader(imports):
        return object loader:
            to "import"(name):
                return imports[name]

    def makeModuleAndConfiguration(modname,
                                   => collectTests := false,
                                   => collectBenchmarks := false):
        def depMap := [].asMap().diverge()
        def subload(modname :Str):
            if (modname == "unittest"):
                if (collectTests):
                    trace(`test collector invoked`)
                    return [["unittest" => ["unittest" => testCollector[modname]]], null]
                else:
                    return [["unittest" => ["unittest" => fn _ {null}]], null]
            if (modname == "bench"):
                if (collectBenchmarks):
                    return [["bench" => ["bench" => benchCollector[modname]]], null]
                else:
                    return [["bench" => ["bench" => fn _, _ {null}]], null]

            def fname := _findTyphonFile(modname)
            if (fname == null):
                throw(`Unable to locate $modname`)
            def loadModuleFile():
                def code := makeFileResource(fname).getContents()
                return when (code) ->
                    try:
                        def modObj := typhonEval(code, safeScopeBindings)
                        depMap[modname] := makeModuleConfiguration(modObj, [].asMap())
                    catch problem:
                        traceln(`Unable to eval file ${M.toQuote(fname)}`)
                        traceln.exception(problem)
                        throw(problem)
            var config := depMap.fetch(modname, loadModuleFile)
            return when (config) ->
                def deps := promiseAllFulfilled([for d in (config.dependencyNames())
                                                 subload(d)])
                when (deps) ->
                    # Fill in the module configuration.
                    def depNames := config.dependencyNames()
                    for depName in depNames:
                        if (depMap.contains(depName)):
                            def dep := depMap[depName]
                            # If the dependency is DF, then add it to the map.
                            # Otherwise, put in the stub.
                            if (dep =~ frozenDep :DeepFrozen):
                                config withDependency= (depName, frozenDep)
                            else:
                                config withLiveDependency= (depName)
                        else:
                            config withMissingDependency= (depName)
                    # Update the dependency map with the latest config.
                    depMap[modname] := config
                    def pre := collectedTests.size()
                    var imports := [].asMap()
                    for [importable, _] in (deps):
                        imports |= importable
                    def module := config(makeLoader(imports.snapshot()))
                    if (collectTests):
                        traceln(`collected ${collectedTests.size() - pre} tests`)
                    [[modname => module], config]
        def moduleAndConfig := subload(modname)
        return when (moduleAndConfig) ->
            def [[(modname) => module], config] := moduleAndConfig
            [module, config]

    def args := currentProcess.getArguments().slice(2)
    def usage := "Usage: loader run <modname> <args> | loader test <modname>"
    if (args.size() < 1):
        throw(usage)
    switch (args):
        match [=="run", modname] + subargs:
            def exps := makeModuleAndConfiguration(modname)
            return when (exps) ->
                def [module, _] := exps
                def excludes := ["typhonEval", "_findTyphonFile", "bench"]
                def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope)
                                          if (!excludes.contains(n))
                                          n => v].with("packageLoader", makeLoader(module))

                # We don't care about config or anything that isn't the
                # entrypoint named `main`.
                def [=> main] | _ := module
                M.call(main, "run", [subargs], unsafeScopeValues)
        match [=="dot", modname] + subargs:
            def tubes := makeModuleAndConfiguration("lib/tubes")
            return when (tubes) ->
                # An unconventional import statement, to be sure.
                def [[=> makeUTF8EncodePump,
                      => makePumpTube,
                ] | _, _] := tubes

                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout<-flowTo(makeStdOut())

                def exps := makeModuleAndConfiguration(modname)
                when (exps) ->
                    # We only care about the config.
                    def [_, topConfig] := exps
                    stdout.receive(`digraph "$modname" {$\n`)
                    # Iteration order doesn't really matter.
                    def stack := [[modname, topConfig]].diverge()
                    while (stack.size() != 0):
                        def [name, config] := stack.pop()
                        for depName => depConfig in config.dependencyMap():
                            stdout.receive(`  "$name" -> "$depName";$\n`)
                            if (depConfig != moduleGraphUnsatisfiedExit &&
                                depConfig != moduleGraphLiveExit):
                                stack.push([depName, depConfig])
                    stdout.receive(`}$\n`)
                    # Success!
                    0
        match [=="test"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 makeModuleAndConfiguration(modname,
                                            "collectTests" => true)] +
                [(def testRunner := makeModuleAndConfiguration("testRunner")),
                 (def tubes := makeModuleAndConfiguration("lib/tubes"))])
            return when (someMods) ->
                def [[=> makeIterFount,
                      => makeUTF8EncodePump,
                      => makePumpTube
                ] | _, _] := tubes
                def [[=> makeAsserter,
                      => makeTestDrain,
                      => runTests
                ] | _, _] := testRunner

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
                 makeModuleAndConfiguration(modname,
                                            "collectBenchmarks" => true)] +
                [(def benchRunner := makeModuleAndConfiguration("benchRunner"))])
            return when (someMods) ->
                def [[=> runBenchmarks] | _, _] := benchRunner
                when (runBenchmarks(collectedBenches, bench,
                                    makeFileResource("bench.html"))) ->
                    traceln(`Benchmark report written to bench.html.`)

        match _:
            throw(usage)
main()
