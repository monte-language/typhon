import "lib/argv" =~ [=> flags]
import "lib/muffin" =~ [=> makeFileLoader, => loadTopLevelMuffin]
exports (main)

def addTyphonHarness(expr :DeepFrozen, name :Str) :DeepFrozen as DeepFrozen:
    def topname :DeepFrozen := astBuilder.LiteralExpr(name, null)
    traceln(`Packing module for Typhon harness…`)
    def context := makeMASTContext()
    context(expr.expand())
    # Module, ready-to-expand. This encoding is a little complex.
    def mre :Bytes := context.bytes()
    def l := astBuilder.ListExpr([for b in (mre) astBuilder.LiteralExpr(b, null)], null)
    def packed :DeepFrozen := m`_makeBytes.fromInts($l)`

    traceln(`Generating Typhon harness…`)
    # Adapted from Typhon's loader.mt.
    # To simplify quoting, this comment is outside the harness.
    # We don't need to do nearly as much as Typhon's loader, since we know
    # that we won't need to pass a valid package, just m`null`. We do want to
    # scoop a few specific names out of Typhon's unsafe scope, though, and
    # Typhon does need for the overall return value to be something like
    # Vow[Int]. The argv is obtained from m`currentProcess.getArguments()`,
    # but Typhon lies about its actual argv a little. This lie works in our
    # advantage, though, because the lie is that argv[0] is the Typhon
    # executable, argv[1] is what Typhon thinks our module is called, and the
    # rest are the "actual" argv that user-level code wants for main(). ~ C.
    return m`{
        traceln("starting Typhon harness…")
        def argv := currentProcess.getArguments().slice(2)

        def excludes := ["typhonEval", "_findTyphonFile", "bench"].asSet()
        def unsafeScopeValues := [for ``&&@@n`` => &&v in (unsafeScope)
                                  ? (!excludes.contains(n))
                                  n => v]

        traceln("instantiating…")
        def mod := typhonAstEval(normalize(readMAST($packed), typhonAstBuilder),
                                 safeScope, $topname)
        def [=> main] | _ := mod(null)

        def exitStatus := M.call(main, "run", [argv], unsafeScopeValues)
        Ref.whenBroken(exitStatus, fn problem {
            traceln.exception(Ref.optProblem(problem))
            1
        })
        exitStatus :Vow[Int]
    }`

def closeExpression(expr :DeepFrozen, _name :Str) :DeepFrozen as DeepFrozen:
    "Close an expression so that it has no free variables."

    # Our strategy is to take safeScope as a lone argument, and assign its
    # bindings to the scope surrounding our expression. We can leverage
    # _mapExtract, as a special case.
    def extractors := [for k => _ in (safeScope.without("&&_mapExtract")) {
        astBuilder.MapPatternImport(
            astBuilder.BindingPattern(
                astBuilder.NounExpr(k, null), null), null, null)
    }]
    def extraction := astBuilder.MapPattern(extractors, mpatt`_`, null)
    return m`fn safeScope {
        def &&_mapExtract := safeScope["&&_mapExtract"]
        def $extraction := safeScope
        { $expr }()
    }`.expand()

def harnesses :Map[Str, DeepFrozen] := [
    "typhon" => addTyphonHarness,
    "closed" => closeExpression,
]

def basePath :Str := "mast"

def main(argv, => makeFileResource) as DeepFrozen:
    def loader := makeFileLoader(fn name {
        makeFileResource(`$basePath/$name`)<-getContents()
    })
    var harness :Str := "closed"
    def parser := flags () typhon {
        harness := "typhon"
    } closed {
        harness := "closed"
    }
    def [_, _, pn, out] := parser(argv)
    traceln(`Making muffin out of $pn`)
    return when (var m := loadTopLevelMuffin(loader, pn)) ->
        m := harnesses[harness](m, pn)
        def context := makeMASTContext()
        traceln("Expanding…")
        def expanded := m.expand()
        traceln("Writing MAST…")
        context(expanded)
        when (makeFileResource(out)<-setContents(context.bytes())) ->
            traceln("all done")
            0
