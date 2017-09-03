import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [=> parseModule :DeepFrozen]
import "lib/monte/monte_expander" =~ [=> expand :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
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

def load(code :Str, name: Str, ej) as DeepFrozen:
    traceln(`loading $name`)
    # traceln(code)
    def tokens := makeMonteLexer(code, name)
    def ast := expand(parseModule(tokens, astBuilder, ej),
                      astBuilder, ej)
    # traceln(`app $name AST: $ast`)
    def moduleBody := eval(ast, safeScope)
    def package := null  # umm...
    def moduleExports := moduleBody(package)
    # traceln(`app $name module: $module`)
    return moduleExports


def main(argv :List[Str], =>makeFileResource) :Vow[Int] as DeepFrozen:
    def cwd := makeFile(makeFileResource, ".")
    def args := argv.slice(2)  # normally 1, but monte eval is a little goofy

    return if (args =~ [=="--make", appName]):
        # perhaps: cwd`apps/$appName/main.mt`
        when (def appCode := (cwd / "apps" / appName / "main.mt").getText()) ->
            def [=> make :DeepFrozen] | _ := load(appCode, appName, throw)
            def thing := make()
            def state := thing._unCall()
            traceln(`$appName state: $state`)
            0
        catch oops:
            traceln(`???`)
            traceln.exception(oops)
            1
    else:
        traceln(`bad args: $argv`)
        1

    
