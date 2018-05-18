import "lib/codec/utf8" =~ [=> UTF8]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
exports (makeLimo, main)

def makeFileLoader(root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def path := `$root/$petname.mt`
        traceln(`trying to open $path`)
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            def s := UTF8.decode(bs, null)
            def lex := makeMonteLexer(s, petname)
            parseModule(lex, astBuilder, null)

def getDependencies(expr) as DeepFrozen:
    def module := eval(expr, safeScope)
    return module.dependencies()

def makeLimo(load) as DeepFrozen:
    def mods := [].asMap().diverge()

    def limo

    def loadAll(pns):
        return promiseAllFulfilled([for pn in (pns) ? (!mods.contains(pn)) {
            when (def expr := load<-(pn)) -> { mods[pn] := limo<-(pn, expr) }
        }])

    return bind limo(name, expr):
        def deps := getDependencies(expr)
        return when (loadAll(deps)) ->
            def depExpr := astBuilder.MapExpr([for pn in (deps) {
                def key := astBuilder.LiteralExpr(pn, null)
                def value := mods[pn]
                astBuilder.MapExprAssoc(key, value, null)
            }], null)
            def instance := mods[name] := m`{
                def deps := $depExpr
                def package."import"(petname) { return deps[petname] }
                { $expr }(package)
            }`
            return instance

def main(_argv, => makeFileResource) as DeepFrozen:
    def loader := makeFileLoader("mast", makeFileResource)
    def limo := makeLimo(loader)
    traceln("sure", loader, limo)
    return when (def expr := loader("lib/words")) ->
        when (def m := limo("lib/words", expr)) ->
            traceln("derp", m)
            0
