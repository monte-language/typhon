import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/entropy/entropy" =~ [=> makeEntropy :DeepFrozen]
import "lib/entropy/pcg" =~ [=> makePCG :DeepFrozen]

import "saver" =~ [
    => makeSaver :DeepFrozen,
    => makeUnique :DeepFrozen,
    => makeReviver :DeepFrozen]
exports (main)

def makeFile(makeFileResource, path) as DeepFrozen:
    return object File:
        to approxDivide(other):
            return makeFile(makeFileResource, `$path/$other`)
        to getContents() :Vow[Bytes]:
            return makeFileResource(path).getContents()
        to getText() :Vow[Str]:
            return when (def input := File.getContents()) ->
                UTF8.decode(input, throw)


def main(argv :List[Str], =>makeFileResource, =>currentRuntime) :Vow[Int] as DeepFrozen:
    def [_, seed] := currentRuntime.getCrypt().makeSecureEntropy().getEntropy()
    def rng := makeEntropy(makePCG(seed, 0))
    def unique := makeUnique(rng.nextInt)
    def cwd := makeFile(makeFileResource, ".")
    def dbfile := cwd / "capper.db"
    def reviver := makeReviver(cwd)
    def saver := makeSaver(unique, dbfile, reviver.toMaker)

    def args := argv.slice(2)  # normally 1, but monte eval is a little goofy

    return if (args =~ [=="--make", appName] + _appArgs):
        # perhaps: cwd`apps/$appName/server.mt`
        #@@def obj := M.send(saver, "make", [appName] + appArgs, [].asMap())
        def obj := saver<-make(appName)
        when (obj) ->
            traceln(`$appName obj: $obj`)
            traceln(`$appName state: ${obj._unCall()}`)
            obj.setGreeting("bye bye!")
            traceln(`$appName state2: ${obj._unCall()}`)
            0
        catch oops:
            traceln(`???`)
            traceln.exception(oops)
            1
    else:
        traceln(`bad args: $argv`)
        1

    
