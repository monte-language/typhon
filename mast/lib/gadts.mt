import "lib/iterators" =~ [=> zip :DeepFrozen]
import "unittest" =~ [=> unittest :Any]
exports (makeGADT)

def transpose(l :List) as DeepFrozen:
    return _makeList.fromIterable(M.call(zip, "run", l, [].asMap()))

def makeController(cons :Map[Str, Int], lambdas :Map) as DeepFrozen:
    return object controller:
        to control(verb :Str, ==0, paramCount :Int, block):
            def arity := cons.fetch(verb, fn {
                throw(`No such constructor $verb`)
            })
            if (arity != paramCount):
                throw(`Constructor $verb has arity $arity, not $paramCount`)
            def [[], lambda] := block()
            return makeController(cons.without(verb),
                                  lambdas.with(verb, lambda))

        to controlRun():
            if (!cons.isEmpty()):
                throw(`Case analysis missed cases: ${cons.getKeys()}`)
            return def dispatcher(gadt):
                def f := lambdas.fetch(def k := gadt._constructor(), fn {
                    throw(`Case dispatch: $k not in ${lambdas.getKeys()}`)
                })
                def elts := gadt._elements()
                return if (elts.isEmpty()) { f() } else {
                    M.call(f, "run", elts.with(throw), [].asMap())
                }

def makeGADT(label :Str, constructors :Map[Str, Map[Str, DeepFrozen]]) as DeepFrozen:
    interface GADTStamp :DeepFrozen {}

    def labelNoun := astBuilder.NounExpr(label, null)

    # Build the constructors.
    def extraScope := [].asMap().diverge()
    def addGuard(g :DeepFrozen):
        return extraScope.fetch(g, fn {
            def k := `_gadt_guard_$g`
            extraScope[g] := [k, &&g]
        })[0]
    def [cons, controlPairs] := transpose([for con => gs in (constructors) {
        def [nps, nouns, getters, prints] := transpose([for name => g in (gs) {
            def guard := astBuilder.NounExpr(addGuard(g), null)
            def noun := astBuilder.NounExpr(name, null)
            def patt := astBuilder.FinalPattern(noun, guard, null)
            def np := astBuilder.NamedParamImport(patt, null, null)
            def getter := astBuilder."Method"(null, name, [], [], guard, noun,
                                              null)
            def print := m`{
                out.print(${astBuilder.LiteralExpr(M.toQuote(name) + " => ", null)})
                out.print($noun)
            }`
            [np, noun, getter, print]
        }])

        # Assemble the pretty-printer.
        def comma := m`out.print(", ")`
        def printOn := m`to _printOn(out) :Void {
            out.print(${astBuilder.LiteralExpr(`<$label.$con(`, null)})
            ${astBuilder.SeqExpr([comma].join(prints), null)}
            out.print(")>")
        }`

        def originalNames := astBuilder.MapExpr(
            [for noun in (nouns) astBuilder.MapExprExport(noun, null)], null)
        def conLit := astBuilder.LiteralExpr(con, null)
        def withBody := m`M.call($labelNoun, $conLit, [], updates | $originalNames)`
        def with := astBuilder.Matcher(mpatt`[=="with", [], updates]`,
                                       withBody, null)

        def _con := m`method _constructor() :Str { $conLit }`
        def _elts := m`method _elements() :List {
            ${astBuilder.ListExpr(nouns, null)}
        }`
        def meths := getters + [printOn, _con, _elts]
        def script := astBuilder.Script(null, meths, [with], null)
        def body := astBuilder.ObjectExpr(null, mpatt`_`, m`DeepFrozen`,
                                          [m`GADTStamp`], script, null)
        def meth := astBuilder."Method"(null, con, [], nps, null, body, null)

        def controlPair := astBuilder.MapExprAssoc(conLit,
            astBuilder.LiteralExpr(gs.size(), null), null)
        [meth, controlPair]
    }])

    def controlMap := astBuilder.MapExpr(controlPairs, null)
    def controlBody := m`{
        switch (argCount) {
            match ==0 {
                makeController($controlMap, [].asMap()).control(verb, 0,
                    paramCount, block)
            }
            match ==1 {
                var controller := makeController($controlMap, [].asMap())
                def [[value], lambda] := block()
                def fauxBlock() { return [[], lambda] }
                controller control= (verb, 0, paramCount, fauxBlock)
                object fauxController {
                    method control(verb, argCount, paramCount, block) {
                        controller control= (verb, argCount, paramCount,
                                             block)
                        fauxController
                    }
                    method controlRun() { controller.controlRun()(value) }
                }
            }
        }
    }`
    def control := m`method control(verb :Str, argCount :Int, paramCount :Int,
                                    block) { $controlBody }`

    def coerce := m`method coerce(specimen, ej) {
        def prize :GADTStamp exit ej := specimen
        prize
    }`

    # Assemble the final object.
    def namePatt := astBuilder.FinalPattern(labelNoun, null, null)
    def script := astBuilder.Script(null, cons + [control, coerce], [], null)
    def expr := astBuilder.ObjectExpr(null, namePatt, m`DeepFrozen`, [],
                                      script, null)
    def guardScope := [for [k, b] in (extraScope.getValues()) `&&$k` => b]
    def helperScope := [=> &&makeController, => &&GADTStamp]
    # traceln(`Building GADT expr`, expr)
    return eval(m`${expr}`.expand(), safeScope | guardScope | helperScope)

def testGADTAccessors(assert):
    def These := makeGADT("These", [
        "this" => ["x" => DeepFrozen],
        "that" => ["y" => DeepFrozen],
    ])
    def this := These.this("x" => 42)
    def that := These.that("y" => 7)
    assert.equal(this.x(), 42)
    assert.equal(that.y(), 7)

def testGADTWith(assert):
    def These := makeGADT("These", [
        "this" => ["x" => DeepFrozen],
        "that" => ["y" => DeepFrozen],
    ])
    var this := These.this("x" => 42)
    assert.equal(this.x(), 42)
    this := this.with("x" => 7)
    assert.equal(this.x(), 7)

def testGADTDispatch(assert):
    def These := makeGADT("These", [
        "this" => ["x" => DeepFrozen],
        "that" => ["y" => DeepFrozen],
    ])
    # Incomplete.
    assert.throws(fn {
        These () this x { x }
    })
    # Non-existent case.
    assert.throws(fn {
        These () this x { x } that y { y } testing { 42 }
    })
    # This one should be fine.
    These () this x { x } that y { y }

def testGADTDispatchImmediate(assert):
    def These := makeGADT("These", [
        "this" => ["x" => DeepFrozen],
        "that" => ["y" => DeepFrozen],
    ])
    def val := These.this("x" => 42)
    assert.equal(These (val) this x { x } that y { y }, 42)

unittest([
    testGADTAccessors,
    testGADTWith,
    testGADTDispatch,
    testGADTDispatchImmediate,
])
