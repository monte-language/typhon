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

def main(argv, => makeFileResource) as DeepFrozen:
    def loader := makeFileLoader(basePath, makeFileResource)
    def limo := makeLimo(loader)
    def [pn, out] := argv
    traceln(`Making muffin out of $pn`)
    return when (def p := loader(pn)) ->
        def [source, expr] := p
        when (def m := limo(pn, source, expr)) ->
            def context := makeMASTContext()
            context(m.expand())
            when (makeFileResource(out)<-setContents(context.bytes())) ->
                traceln("all done")
                0
