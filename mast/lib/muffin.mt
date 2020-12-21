import "lib/asdl" =~ [=> buildASDLModule]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/freezer" =~ [=> freeze]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
exports (makeFileLoader, loadTopLevelMuffin)

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
                        loader(bs, petname, ej)
                    catch parseProblem:
                        Ref.broken(parseProblem)
                catch _:
                    go()
            catch _:
                Ref.broken("No loaders succeeded")
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

def loadTopLevelMuffin(load, topName :Str) as DeepFrozen:
    "
    Using `load` as a module loader, load module with petname `topName` and
    compile it into a module with no dependencies; compile `topName` into a
    muffin. Muffins are Monte expressions which represent modules but do not
    have any imports.

    `load` is a module loader; it should take petnames as strings and return
    promises for pairs `[source :NullOk[Str], expression]` of source code and
    Monte code objects.
    "

    # Map of petnames to eventual [source, expr, dependencies].
    def modules := [].asMap().diverge()
    # Note that registration produces a topological order in the map.
    def register(petname :Str):
        if (petname == "bench" || petname == "unittest") { return }
        return modules.fetch(petname, fn {
            def r := def loaded
            when (def p := load(petname)) -> {
                def [source, expr] := p
                def dependencies := eval(expr, safeScope).dependencies()
                def depsFulfilled := promiseAllFulfilled([for pn in (dependencies) {
                    register(pn)
                }])
                when (depsFulfilled) -> {
                    r.resolve([source, expr, dependencies])
                } catch problem { r.smash(problem) }
            } catch problem { r.smash(problem) }
            modules[petname] := loaded
        })

    return when (def p := register(topName)) ->
        def [_source, expr, dependencies] := p
        # It could well happen that the module already is a muffin. In
        # that case, nothing special needs to be done.
        if (dependencies.isEmpty()) { expr } else {
            # Get the modules in the right order. This is a basic topological
            # sort, ala Tarjan.
            def sorted := [].diverge()
            var seen := ["unittest", "bench"].asSet()
            while (!modules.isEmpty()) {
                # Find a module who has no dependencies left and use it next.
                sorted.push(escape ej {
                    for n => [s, e, ds] in (modules) {
                        if (!(seen >= ds.asSet())) { continue }
                        seen with= (n)
                        modules.removeKey(n)
                        ej([n, s, e, ds])
                    }
                    throw(`Cycle in remaining modules: ${modules.getKeys()}`)
                })
            }
            # Boot each module in order. We give each module a package with
            # exactly the already-booted modules that it wants, and also all
            # of the module parameters.
            # XXX use source to implement meta imports
            def boots := [for [n, _s, e, ds] in (sorted) {
                m`{
                    def mods := [for k in (${freeze(ds)}) k => loaded[k]]
                    def package."import"(k) { return mods[k] }
                    loaded[${freeze(n)}] := M.call({ $e }, "run",
                                                   [package], moduleParams)
                }`
            }]
            # Because of the way that the modules are registered, the final
            # module to be booted is always the desired top-level module.
            m`object _ as DeepFrozen {
                to dependencies() { return [] }
                match [=="run", [_package], moduleParams] {
                    def loaded := [
                        "bench" => ["bench" => $bench],
                        "unittest" => ["unittest" => $unittest],
                    ].diverge(Str, DeepFrozen)
                    ${astBuilder.SeqExpr(boots, null)}
                }
            }`
        }

        # XXX use these remains to implement meta imports
        #         def importBody := if (wantsMeta) {
        #             m`if (petname == "meta") {
        #                 def source :NullOk[Str] := $ls
        #                 object this as DeepFrozen {
        #                     method module() { mod }
        #                     method ast() :NullOk[DeepFrozen] {
        #                         if (source != null) { ::"m````".fromStr(source) }
        #                     }
        #                     method source() :NullOk[Str] { source }
        #                 }
        #                 [=> this]
        #             } else {
        #                 deps[petname](null)
        #             }`
        #         } else {
        #             m`deps[petname](null)`
        #         }
