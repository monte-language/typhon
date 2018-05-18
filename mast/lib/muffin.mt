import "lib/codec/utf8" =~ [=> UTF8]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
exports (makeLimo, main)

def makeFileLoader(root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def path := `$root/$petname.mt`
        traceln(`loading module $path`)
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            def s := UTF8.decode(bs, null)
            def lex := makeMonteLexer(s, petname)
            parseModule(lex, astBuilder, null)

def bench :DeepFrozen := m`{
    object _ as DeepFrozen {
        to dependencies() { return [] }
        to run(_package) {
            def bench(_test, _label) as DeepFrozen { return null }
            return [=> bench]
        }
    }
}`

def unittest :DeepFrozen := m`{
    object _ as DeepFrozen {
        to dependencies() { return [] }
        to run(_package) {
            def unittest(_tests) as DeepFrozen { return null }
            return [=> unittest]
        }
    }
}`

def getDependencies(expr) as DeepFrozen:
    def module := eval(expr, safeScope)
    return module.dependencies()

def makeLimo(load) as DeepFrozen:
    def mods := [
        => bench,
        => unittest,
    ].diverge()

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
            def ln := astBuilder.LiteralExpr(name, null)
            def instance := mods[name] := m`{
                traceln(``first-time module $${$ln}``)
                def deps :Map[Str, DeepFrozen] := { $depExpr }
                def package."import"(petname) as DeepFrozen {
                    traceln(``giving dep $$petname to $${$ln}``)
                    return deps[petname](null)
                }
                object _ as DeepFrozen {
                    to dependencies() { return [] }
                    to run(_package) {
                        traceln(``initializing $${$ln}``)
                        return { $expr }(package)
                    }
                }
            }`
            instance

def main(_argv, => makeFileResource) as DeepFrozen:
    def loader := makeFileLoader("mast", makeFileResource)
    def limo := makeLimo(loader)
    def pn := "lib/json"
    return when (def expr := loader(pn)) ->
        when (def m := limo(pn, expr)) ->
            def instance := eval(m, safeScope)
            traceln("instance", instance, instance.dependencies(),
                    instance(null))
            0
