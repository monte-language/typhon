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
    return [for dep in (module.dependencies()) ? (dep != "meta") dep]

def makeLimo(load) as DeepFrozen:
    def mods := [
        => bench,
        => unittest,
    ].diverge()

    def limo

    def loadAll(pns):
        def pending := [].diverge()
        for pn in (pns):
            if (!mods.contains(pn)):
                def p := when (def loaded := load<-(pn)) -> {
                    def [s, expr] := loaded
                    traceln(`Loaded $pn`)
                    limo<-(pn, s, expr)
                }
                mods[pn] := p
            pending.push(mods[pn])
        return promiseAllFulfilled(pending)

    return bind limo(name, source, expr) :Vow[DeepFrozen]:
        def deps := getDependencies(expr)
        return when (loadAll(deps)) ->
            def depExpr := astBuilder.MapExpr([for pn in (deps) {
                def key := astBuilder.LiteralExpr(pn, null)
                def value :DeepFrozen := mods[pn]
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
                            def source :Str := $ls
                            object this as DeepFrozen {
                                method module() { mod }
                                method ast() { ::"m````".fromStr(source) }
                                method source() { source }
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
