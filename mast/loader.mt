object moduleGraphUnsatisfiedExit as DeepFrozen:
    "An unsatisfied exit point on a module configuration graph."

object moduleGraphLiveExit as DeepFrozen:
    "A live (non-`DeepFrozen`) exit point on a module configuration graph."

interface Config :DeepFrozen {}

def makeModuleConfiguration(module :DeepFrozen,
                            knownDependencies :Map[Str, DeepFrozen]) as DeepFrozen:
    return object moduleConfiguration as DeepFrozen implements Config:
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

def ModuleStructure :DeepFrozen := Pair[Map[Str, Map[Str, Any]], NullOk[Config]]

def loaderMain() :Vow[Int]:
    "Run the thing and return the status code."

    def collectedTests := [].diverge()
    def collectedBenches := [].diverge()
    def testCollector.get(locus):
        return def testBucket(tests):
            for t in (tests):
                collectedTests.push([locus, t])

    def benchCollector.get(locus):
        return def benchBucket(aBench, name :Str):
            collectedBenches.push([`$locus: $name`, aBench])

    def makeLoader(imports :Map):
        return def loader."import"(name):
            return imports[name]


    def makeModuleAndConfiguration(modname,
                                   newReader,
                                   => collectTests := false,
                                   => collectBenchmarks := false):
        def depMap := [].asMap().diverge()
        def subload(modname :Str):
            if (modname == "unittest"):
                if (collectTests):
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
                        def modObj := if (newReader) {
                            typhonAstEval(normalize(readMAST(code), typhonAstBuilder),
                                          safeScope, fname)
                        } else {
                            astEval.evalToPair(code, safeScope,
                                               "filename" => fname)[0]
                        }
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
                    for depName in (depNames):
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
                    var imports := [].asMap()
                    for [importable, _] in (deps :List[ModuleStructure]):
                        imports |= importable
                    def module := config(makeLoader(imports))
                    [[modname => module], config]
        def moduleAndConfig := subload(modname)
        return when (moduleAndConfig) ->
            def [[(modname) => module], config] := (moduleAndConfig :ModuleStructure)
            [module, config]

    var args := currentProcess.getArguments().slice(2)
    traceln(`Loader args: $args`)
    def usage := "Usage: loader run <modname> <args> | loader test <modname>"
    if (args.size() < 1):
        throw(usage)
    def newReader := args[0] == "-anf"
    if (newReader):
        args := args.slice(1)

    return switch (args):
        match [=="run", modname] + subargs:
            traceln(`Loading $modname`)
            def exps := makeModuleAndConfiguration(modname, newReader)
            when (exps) ->
                def [module, _] := exps
                def excludes := ["typhonEval", "_findTyphonFile", "bench"]
                # Leave out loader-only objects.
                def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope)
                                          ? (!excludes.contains(n))
                                          n => v]

                # We don't care about config or anything that isn't the
                # entrypoint named `main`.
                def [=> main] | _ := module
                M.call(main, "run", [subargs], unsafeScopeValues)
        match [=="dot", modname] + _subargs:
            def stdout := stdio.stdout()
            def exps := makeModuleAndConfiguration(modname, newReader)
            when (exps) ->
                # We only care about the config.
                def [_, topConfig] := exps
                stdout(b`digraph "$modname" {$\n`)
                # Iteration order doesn't really matter.
                def stack := [[modname, topConfig]].diverge()
                while (stack.size() != 0):
                    def [name, config] := stack.pop()
                    for depName => depConfig in (config.dependencyMap()):
                        stdout(b`  "$name" -> "$depName";$\n`)
                        if (depConfig != moduleGraphUnsatisfiedExit &&
                            depConfig != moduleGraphLiveExit):
                            stack.push([depName, depConfig])
                stdout(b`}$\n`)
                # Success!
                stdout.complete()
                0
        match [=="test"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 makeModuleAndConfiguration(modname,
                                            newReader,
                                            "collectTests" => true)] +
                [def testRunner := makeModuleAndConfiguration("testRunner", newReader)])
            when (someMods) ->
                def [[=> makeRunner] | _, _] := testRunner
                def stdout := stdio.stdout()
                def runner := makeRunner(stdout, unsealException, Timer)
                def results := runner<-runTests(collectedTests)
                when (results) ->
                    def fails :Int := results.fails()
                    stdout(b`${M.toString(results.total())} tests run, `)
                    stdout(b`${M.toString(fails)} failures$\n`)
                    # Exit code: Only returns 0 if there were 0 failures.
                    for loc => errors in (results.errors()):
                        stdout(b`In $loc:$\n`)
                        for error in (errors):
                            stdout(b`~ $error$\n`)
                    when (stdout.complete()) -> { fails.min(1) }
                catch problem:
                    stdout(b`Test suite failed: ${M.toString(unsealException(problem))}$\n`)
                    when (stdout.complete()) -> { 1 }
        match [=="bench"] + modnames:
            def someMods := promiseAllFulfilled(
                [for modname in (modnames)
                 makeModuleAndConfiguration(modname,
                                            newReader,
                                            "collectBenchmarks" => true)] +
                [(def benchRunner := makeModuleAndConfiguration("benchRunner"))])
            return when (someMods) ->
                def [[=> runBenchmarks] | _, _] := benchRunner
                when (runBenchmarks(collectedBenches, bench,
                                    makeFileResource("bench.html"))) ->
                    traceln(`Benchmark report written to bench.html.`)
                    0

        match _:
            throw(usage)
def exitStatus := loaderMain()
Ref.whenBroken(exitStatus, fn x {traceln.exception(Ref.optProblem(x)); 1})
exitStatus
