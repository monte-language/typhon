# Once this is all hooked up we can rip module support out of the runtime and
# the following line can go away.
exports (main)

def safeScopeBindings :DeepFrozen := [for `&&@n` => v in (safeScope) n => v]

def main(=> _findTyphonFile, => makeFileResource, => typhonEval, => currentProcess, => unsafeScope) as DeepFrozen:
    def depMap := [].asMap().diverge()
    def valMap := [].asMap().diverge()
    def subload(name, loader, depMap):
        def fname := _findTyphonFile(name)
        traceln(`name $name fname $fname`)
        def loadModuleFile():
            def f := makeFileResource(fname)
            def code := f <- getContents()
            def mod := when (code) -> {typhonEval(code, safeScopeBindings)}
            depMap[name] := mod
            return mod
        def mod := depMap.fetch(name, loadModuleFile)
        return when (mod) ->
            def deps := promiseAllFulfilled([for d in (mod.dependencies())
                                             subload(d, loader, depMap)])
            when (deps) ->
                valMap[name] := mod(loader)

    def args := currentProcess.getArguments().slice(2)
    traceln(`$args`)
    if (args.size() < 1):
        throw("A module name is required")
    def [modname] + subargs := args
    object loader:
        to "import"(name):
            if (name == "unittest"):
                return ["unittest" => fn _ {null}]
            return valMap[name]
    def exps := subload(modname, loader, depMap)
    def unsafeScopeValues := [for `&&@n` => &&v in (unsafeScope) n => v]
    return when (exps) ->
        def [=> main] | _ := exps
        M.call(main, "run", [subargs], unsafeScopeValues)
