import "lib/argv" =~ [=> flags]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/muffin" =~ [=> makeLimo]
exports (main)

def makeFileLoader(root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def path := `$root/$petname.mt`
        traceln(`loading module $path`)
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            def s := UTF8.decode(bs, null)
            def lex := makeMonteLexer(s, petname)
            [s, parseModule(lex, astBuilder, null)]

def basePath :Str := "mast"

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
        def argv := currentProcess.getArguments().slice(2)

        def excludes := ["typhonEval", "_findTyphonFile", "bench"].asSet()
        def unsafeScopeValues := [for ``&&@@n`` => &&v in (unsafeScope)
                                  ? (!excludes.contains(n))
                                  n => v]

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

def main(argv, => makeFileResource) as DeepFrozen:
    def loader := makeFileLoader(basePath, makeFileResource)
    def limo := makeLimo(loader)
    var addTyphon :Bool := false
    def parser := flags () typhon {
        addTyphon := true
    }
    def [pn, out] := parser(argv)
    traceln(`Making muffin out of $pn`)
    return when (def p := loader(pn)) ->
        def [source, expr] := p
        when (var m := limo(pn, source, expr)) ->
            if (addTyphon):
                m := addTyphonHarness(m, pn)
            def context := makeMASTContext()
            context(m.expand())
            when (makeFileResource(out)<-setContents(context.bytes())) ->
                traceln("all done")
                0
