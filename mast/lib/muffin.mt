exports (makeLimo)

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

    def need(pn):
        return (pn != "meta") && (!mods.contains(pn))

    def limo

    def loadAll(pns):
        return promiseAllFulfilled([for pn in (pns) ? (need(pn)) {
            when (def p := load<-(pn)) -> {
                def [s, expr] := p
                when (def m := limo<-(pn, s, expr)) -> { mods[pn] := m }
            }
        }])

    return bind limo(name, source, expr):
        def deps := getDependencies(expr)
        return when (loadAll(deps)) ->
            def depExpr := astBuilder.MapExpr([for pn in (deps) ? (pn != "meta") {
                def key := astBuilder.LiteralExpr(pn, null)
                def value := mods[pn]
                astBuilder.MapExprAssoc(key, value, null)
            }], null)
            def ln := astBuilder.LiteralExpr(name, null)
            def ls := astBuilder.LiteralExpr(source, null)
            def instance := mods[name] := m`{
                traceln(``Defining module $${$ln}…``)
                def deps :Map[Str, DeepFrozen] := { $depExpr }
                def makePackage(mod :DeepFrozen) as DeepFrozen {
                    return def package."import"(petname :Str) as DeepFrozen {
                        return if (petname == "meta") {
                            object this as DeepFrozen {
                                method module() { mod }
                                method source() { $ls }
                            }
                            [=> this]
                        } else {
                            deps[petname](null)
                        }
                    }
                }
                object _ as DeepFrozen {
                    to dependencies() { return [] }
                    to run(_package) {
                        traceln(``Running module $${$ln}…``)
                        def mod := { $expr }
                        return mod(makePackage(mod))
                    }
                }
            }`
            instance
