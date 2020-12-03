object moduleGraphUnsatisfiedExit as DeepFrozen:
    "An unsatisfied exit point on a module configuration graph."

object moduleGraphLiveExit as DeepFrozen:
    "A live (non-`DeepFrozen`) exit point on a module configuration graph."

interface Config :DeepFrozen {}

def makeModuleConfiguration(name :Str, module :DeepFrozen) as DeepFrozen:
    # Known module inputs.
    def keys :List[Str] := module.dependencies()
    def dependencies := [for k in (keys)
                         k => moduleGraphUnsatisfiedExit].diverge()

    return object moduleConfiguration implements Config:
        "Information about the metadata and state of a module."

        to _printOn(out):
            out.print(`<configured module $name wants $keys>`)

        to dependencyNames() :List[Str]:
            return keys

        to dependencyMap() :Map[Str, Any]:
            return dependencies.snapshot()

        to setDependency(petname :Str, dep):
            dependencies[petname] := dep

        to run():
            def loader."import"(name):
                return dependencies[name]
            return module(loader)

def bytesToStr(bs :Bytes) :Str as DeepFrozen:
    return _makeStr.fromChars([for i in (bs) '\x00' + i])

def loaderMain(args :List[Str]) :Vow[Int]:
    "Run the thing and return the status code."

    # traceln(`Loader args: $args`)

    def collectedTests := [].diverge()
    def collectedBenches := [].diverge()
    def testCollector.get(locus):
        return def testBucket(tests):
            for t in (tests):
                collectedTests.push([locus, t])

    def benchCollector.get(locus):
        return def benchBucket(aBench, name :Str):
            collectedBenches.push([`$locus: $name`, aBench])

    # Set up a single namespace for modules.
    def configs := [].asMap().diverge()
    def loadConfig(modname :Str):
        return configs.fetch(modname, fn {
            def fname := _findTyphonFile(modname)
            if (fname == null) { throw(`Unable to locate $modname`) }
            def code := makeFileResource(fname).getContents()
            # Only load configs once.
            configs[modname] := when (code) -> {
                # traceln(`loadConfig($modname)`)
                try {
                    def modObj := astEval.evalToPair(code, safeScope,
                                                     "filename" => fname)[0]
                    # def modObj := typhonAstEval(normalize(readMAST(code),
                    #                                       typhonAstBuilder),
                    #                             safeScope, fname)
                    makeModuleConfiguration(modname, modObj)
                } catch problem {
                    traceln(`Unable to eval file ${M.toQuote(fname)}`)
                    traceln.exception(problem)
                    throw(problem)
                }
            }
        })

    def makeModuleAndConfiguration(modname,
                                   => collectTests := false,
                                   => collectBenchmarks := false):
        def modules := [].asMap().diverge()
        def subload(modname :Str):
            if (modname == "unittest"):
                if (collectTests):
                    return [["unittest" => testCollector[modname]], null]
                else:
                    return [["unittest" => fn _ {null}], null]
            if (modname == "bench"):
                if (collectBenchmarks):
                    return [["bench" => benchCollector[modname]], null]
                else:
                    return [["bench" => fn _, _ {null}], null]

            return modules.fetch(modname, fn {
                # traceln(`subload($modname)`)
                def config := loadConfig(modname)
                modules[modname] := when (config) -> {
                    def deps := [for d in (config.dependencyNames())
                                 d => subload(d)]
                    when (promiseAllFulfilled(deps.getValues())) -> {
                        # Fill in the module configuration.
                        for depName => [depMod, _] in (deps) {
                            config.setDependency(depName, depMod)
                        }
                        # Instantiate the module.
                        # traceln("instantiating", config)
                        def module := config()
                        [module, config]
                    }
                }
            })
        return subload(modname)

    def usage := "Usage: loader run <modname> <args> | loader test <modname> | loader dot <modname> | loader bench <modname>"
    if (args.size() < 1):
        throw(usage)

    return switch (args):
        match [=="run", modname] + subargs:
            def exps := makeModuleAndConfiguration(modname)
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
            def exps := makeModuleAndConfiguration(modname)
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
                                            "collectTests" => true)] +
                [def testRunner := makeModuleAndConfiguration("testRunner")])
            when (someMods) ->
                def [[=> makeRunner] | _, _] := testRunner
                def runner := makeRunner(stdio, unsealException, Timer)
                runner<-runTests(collectedTests)
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
                    0

        match _:
            throw(usage)
# These args come from Typhon's unsafe scope.
def exitStatus := loaderMain(typhonArgs)
Ref.whenBroken(exitStatus, fn x {traceln.exception(Ref.optProblem(x)); 1})
exitStatus
