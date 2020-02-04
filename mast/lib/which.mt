import "lib/codec/utf8" =~ [=> UTF8]
exports (makePathSearcher, makeWhich)

# The guts of the classic UNIX `which` utility, more or less.
# The goal of this module is to attenuate two powerful tools into one focused
# tool. We want to combine subprocessing and filesystem access into searches
# of the filesystem for ambient binaries that we may then call.

def makePathSearcher(makeFileResource, PATH :Bytes) as DeepFrozen:
    def paths :List[Str] := [for p in (PATH.split(b`:`)) UTF8.decode(p, null)]
    def check(p :Str):
        # Borrowed from https://github.com/washort/buda/blob/master/buda.mt:
        # The path is valid when we can get its contents.
        # XXX we should probably check that it's executable?
        return when (makeFileResource(p).getContents()) ->
            true
        catch _:
            false

    def cache := [].asMap().diverge(Str, Str)

    return def pathSearch(bin :Str) :Vow[Str]:
        "
        A basic tool for finding executables on the filesystem.
        "

        if (cache.contains(bin)):
            return cache[bin]

        def it := paths._makeIterator()
        def go():
            return escape ej:
                def cand := `${it.next(ej)[1]}/$bin`
                when (def found := check(cand)) ->
                    if (found) { cache[bin] := cand } else { go() }
            catch _:
                null
        return go()

def makeWhich(makeProcess, pathSearch) as DeepFrozen:
    return def which(bin :Str) :Vow:
        "
        A subprocess starter for a named binary executable on the filesystem.
        "

        def path := pathSearch(bin)
        # XXX makeProcess expects bytes for its first three arguments; we
        # choose UTF8 here hoping that the OS does not whine at us.
        def encodedBin :Bytes := UTF8.encode(bin, null)
        return when (path) ->
            def encodedPath :Bytes := UTF8.encode(path, null)
            object makeSubProcess:
                "
                Spawn a single pre-chosen subprocess.

                All arguments, including named arguments, will be passed on to
                `makeProcess` as-is, but the executable path (and argv[0]) are
                fixed.
                "

                to _printOn(out):
                    out.print(`<makeProcess $path>`)

                match [=="run", [subArgs] + args, namedArgs]:
                    def newArgs := [encodedPath, [encodedBin] + subArgs] + args
                    M.call(makeProcess, "run", newArgs, namedArgs)