import "lib/asdl" =~ [=> buildASDLModule]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
exports (makeFileLoader, makeLimo)

# Turn files into code objects. This kit includes a muffin maker, as well as a
# reasonable example loader which is used by our top-level compiler and REPL.

# First, our module loader. For each different file extension, we have a
# subloader that we'll attempt; given a petname, we'll try each file extension
# in a particular order.

# XXX factor with mast/montec all of these custom loaders.

def loadPlain(file :Bytes, petname, ej) as DeepFrozen:
    "Load standard Monte source files."
    def s :Str := UTF8.decode(file, ej)
    def lex := makeMonteLexer(s, petname)
    return [s, parseModule(lex, astBuilder, ej)]

def stripMarkdown(s :Str) :Str as DeepFrozen:
    "
    Emulate the Markdown-stripping hack
    https://gist.github.com/trauber/4955706 but in Monte instead of awk.
    "
    var skip :Bool := true
    def lines := [].diverge(Str)
    for line in (s.split("\n")):
        # If we are to skip a line, push a blank line in order to create 2D
        # space and keep the spans the same as they were.
        if (line == "```"):
            lines.push("")
            skip := !skip
        else:
            lines.push(skip.pick("", line))
    # Parser bug: We usually need to end with a newline.
    lines.push("")
    return "\n".join(lines)

def loadLiterate(file :Bytes, petname, ej) as DeepFrozen:
    "
    Load a Markdown file whose triple-backtick-escaped code blocks are Monte
    source code.

    This is the lit.sh technique, as popularized by
    https://github.com/vijithassar/lit/
    "
    def s := stripMarkdown(UTF8.decode(file, ej))
    def lex := makeMonteLexer(s, petname)
    return [s, parseModule(lex, astBuilder, ej)]

def loadASDL(file :Bytes, petname, ej) as DeepFrozen:
    def s := UTF8.decode(file, ej)
    return [s, buildASDLModule(s, petname)]

def loadMAST(file :Bytes, petname, ej) as DeepFrozen:
    "Load precompiled MAST."
    # NB: readMAST is currently in safeScope, but might be removed; if we need
    # to import it, it's currently in lib/monte/mast.
    def expr := readMAST(file, "filename" => petname, "FAIL" => ej)
    # We don't exactly have original source code. That's okay though; the only
    # feature that we're missing out on is the self-import technology in
    # lib/muffin, which we won't need because MAST has already been expanded.
    return [null, expr]

# Order matters.
def loaders :Map[Str, DeepFrozen] := [
    "asdl" => loadASDL,
    "mt.md" => loadLiterate,
    "mt" => loadPlain,
    # Always try MAST after Monte source code! Protect users from stale MAST.
    "mast" => loadMAST,
]

def makeFileLoader(rootedLoader) as DeepFrozen:
    "
    A limo-compatible module loader which loads from file-like paths.

    A caller with access to `makeFileResource` might pass
    `fn name { makeFileResource(`$basePath/$name`)<-getContents() }` for the
    rooted loader.
    "
    return def load(petname :Str):
        def it := loaders._makeIterator()
        def go():
            return escape noMoreLoaders:
                def [extension, loader] := it.next(noMoreLoaders)
                def bs := rootedLoader(`$petname.$extension`)
                when (bs) ->
                    escape ej:
                        def rv := loader(bs, petname, ej)
                        if (rv == null) { go() } else { rv }
                    catch parseProblem:
                        Ref.broken(parseProblem)
                catch _:
                    go()
            catch _:
                null
        return go()

# And now the muffin maker.

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
    def rv := [].diverge()
    var wantsMeta := false
    for dep in (module.dependencies()):
        if (dep == "meta"):
            wantsMeta := true
        else:
            rv.push(dep)
    return [rv, wantsMeta]

def makeLimo(load) as DeepFrozen:
    "
    Set up a module compiler.

    `load` is a module loader; it should take petnames as strings and return
    promises for pairs `[source :NullOk[Str], expression]` of source code and
    evaluatable Monte code objects.
    "

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
                    limo<-(pn, s, expr)
                }
                mods[pn] := p
            pending.push(mods[pn])
        return promiseAllFulfilled(pending)

    return bind limo(name, source :NullOk[Str], expr) :Vow[DeepFrozen]:
        "
        Compile a module into a muffin. Muffins are Monte expressions which
        represent modules but do not have any imports.

        `expr` is Monte code for a module with petname `name` and optional
        source code `source`.
        "

        def [deps, wantsMeta :Bool] := getDependencies(expr)
        return when (loadAll(deps)) ->
            def depExpr := astBuilder.MapExpr([for pn in (deps) {
                def key := astBuilder.LiteralExpr(pn, null)
                def value :DeepFrozen := mods[pn]
                astBuilder.MapExprAssoc(key, value, null)
            }], null)
            def ls := if (source != null) {
                astBuilder.LiteralExpr(source, null)
            } else { m`null` }
            def importBody := if (wantsMeta) {
                m`if (petname == "meta") {
                    def source :NullOk[Str] := $ls
                    object this as DeepFrozen {
                        method module() { mod }
                        method ast() :NullOk[DeepFrozen] {
                            if (source != null) { ::"m````".fromStr(source) }
                        }
                        method source() :NullOk[Str] { source }
                    }
                    [=> this]
                } else {
                    deps[petname](null)
                }`
            } else {
                m`deps[petname](null)`
            }
            def instance := mods[name] := m`{
                def deps :Map[Str, DeepFrozen] := { $depExpr }
                def makePackage(mod :DeepFrozen) as DeepFrozen {
                    return def package."import"(petname :Str) as DeepFrozen {
                        return $importBody
                    }
                }
                object _ as DeepFrozen {
                    to dependencies() { return [] }
                    to run(_package) {
                        def mod := { $expr }
                        return mod(makePackage(mod))
                    }
                }
            }`
            instance
