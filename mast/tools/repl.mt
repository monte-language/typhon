import "lib/asdl" =~ [=> buildASDLModule]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/commandLine" =~ [=> makePrompt]
import "lib/console" =~ [=> consoleDraw]
import "lib/graphing" =~ [=> calculateGraph]
import "lib/help" =~ [=> help]
import "lib/iterators" =~ [=> async]
import "lib/json" =~ [=> JSON]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/muffin" =~ [=> makeLimo]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
exports (main)

# The names throughout this section are historical.

def PS1 :Bytes := UTF8.encode("⛰  ", null)
def PS2 :Bytes := UTF8.encode(" … ", null)

def read(prompt, => previous := b``) as DeepFrozen:
    return when (def next := prompt<-ask(previous.isEmpty().pick(PS1, PS2))) ->
        def line := previous + next
        if (line.isEmpty()):
            read<-(prompt)
        else:
            escape parseError:
                escape ejPartial:
                    ::"m``".fromStr(UTF8.decode(line, ejPartial),
                                    "ej" => parseError, => ejPartial)
                catch _:
                    read<-(prompt, "previous" => line)
            catch problem:
                def complaint := UTF8.encode(`Parse error:$\n$problem`, null)
                when (prompt<-writeLine(complaint)) ->
                    read<-(prompt)

def readEvalPrintLoop(prompt, &locals, unsealException) as DeepFrozen:
    def go():
        when (def expr := read<-(prompt)) ->
            def repr := try {
                def [rv, env] := eval.evalToPair(expr, locals, "inRepl" => true)
                # Preserve side-effected new stuff from e.g. playWith.
                locals |= env
                `Result: ${M.toQuote(rv)}`
            } catch p {
                # Typhon's exception handling is kinda broken so we try to cope
                # by ignoring things that aren't sealed exceptions.
                if (p =~ via (unsealException) [problem, trail]) {
                    `Exception: $problem$\n` + "\n".join(trail.reverse())
                } else { `Unknown problem: $p` }
            }
            when (prompt<-writeLine(UTF8.encode(repr, null))) ->
                go<-()
    go()

def loadPlain(file :Bytes, petname, ej) as DeepFrozen:
    def s := UTF8.decode(file, ej)
    def lex := makeMonteLexer(s, petname)
    return [s, parseModule(lex, astBuilder, ej), "Monte source"]

# XXX factor with mast/montec all of these custom loaders.

def stripMarkdown(s :Str) :Str as DeepFrozen:
    var skip :Bool := true
    def lines := [].diverge()
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
    def s := stripMarkdown(UTF8.decode(file, ej))
    def lex := makeMonteLexer(s, petname)
    return [s, parseModule(lex, astBuilder, ej), "Monte literate source"]

def loadASDL(file :Bytes, petname, ej) as DeepFrozen:
    def s := UTF8.decode(file, ej)
    return [s, buildASDLModule(s, petname), "Zephyr ASDL specification"]

def loadMAST(file :Bytes, petname, ej) as DeepFrozen:
    # XXX readMAST is currently in safeScope, but might be removed; if we need
    # to import it, it's currently in lib/monte/mast.
    def expr := readMAST(file, "filename" => petname, "FAIL" => ej)
    # We don't exactly have original source code. That's okay though; the only
    # feature that we're missing out on is the self-import technology in
    # lib/muffin, which we won't need.
    return [null, expr, "Kernel-Monte packed source"]

def loaders :Map[Str, DeepFrozen] := [
    "asdl" => loadASDL,
    "mt.md" => loadLiterate,
    "mt" => loadPlain,
    # Always try MAST after Monte source code! Protect users from stale MAST.
    "mast" => loadMAST,
]

def makeFileLoader(log, root :Str, makeFileResource) as DeepFrozen:
    return def load(petname :Str):
        def it := loaders._makeIterator()
        def go():
            return escape noMoreLoaders:
                def [extension, loader] := it.next(noMoreLoaders)
                def path := `$root/$petname.$extension`
                def bs := makeFileResource(path)<-getContents()
                when (bs) ->
                    log(`Read file: $path`)
                    escape ej:
                        def rv := loader(bs, petname, ej)
                        if (rv == null) { go() } else {
                            def [source, expr, description] := rv
                            log(`Loaded $description: $path`)
                            [source, expr]
                        }
                    catch parseProblem:
                        log(`Problem parsing $path: $parseProblem`)
                        throw(parseProblem)
                catch _:
                    go()
            catch _:
                null
        return go()

def main(_argv,
         => currentProcess,
         => makeFileResource,
         => makeProcess,
         => Timer,
         => stdio,
         => unsealException,
         => unsafeScope) :Vow[Int] as DeepFrozen:

    # Forward-declare the environment.
    var environment := null

    def [prompt, cleanup] := makePrompt(stdio)
    def log(s :Str):
        prompt.writeLine(b`Log: ` + UTF8.encode(s, null))

    object repl:
        "
        Some useful REPL stuff.

        .complete/0: Exit.
        .load/2: Load a module from a directory.
        .benchmark/1: Estimate the runtime of a fn.
        .draw/1: Draw a drawable using ASCII art.
        .graph/1: Draw a fn from Doubles to Doubles like a graphing calculator.
        "

        to complete():
            "Cleanly exit the REPL."
            cleanup()

        to instantiateModule(basePath :Str, petname :Str) :Vow[DeepFrozen]:
            "
            Get an instance of the  module named `petname` from `basePath` on
            the filesystem.
            "

            def loader := makeFileLoader(log, basePath, makeFileResource)
            def limo := makeLimo(loader)
            return when (def p := loader(petname)) ->
                def [source :NullOk[Str], expr] := p
                when (def m := limo(petname, source, expr)) ->
                    eval(m, safeScope)
            catch problem:
                log(`Couldn't instantiate $petname: $problem`)

        to load(basePath :Str, petname :Str) :Vow[Void]:
            "
            Load the module named `petname` from `basePath` into the REPL
            scope.
            "
            def m := repl.instantiateModule(basePath, petname)
            prompt<-writeLine(b`Loading module $petname from $basePath`)
            return when (m) ->
                prompt<-writeLine(b`Instantiated $petname`)
                when (async."for"(m(null), fn k :Str, v :DeepFrozen {
                    prompt<-writeLine(b`Loading into environment: $k`)
                    environment with= (`&&$k`, &&v)
                })) -> { prompt<-writeLine(b`Loaded module: $petname`) }
            catch problem:
                traceln.exception(problem)
                prompt<-writeLine(b`Couldn't instantiate $petname`)

        to benchmark(callable) :Vow[Double]:
            "Run `callable` repeatedly, recording the time taken."
            def iterations :Int := 10_000
            var total := 0.0
            def ps := [for i in (0..!iterations) {
                def t := Timer<-measureTimeTaken(callable)
                when (t) -> {
                    total += t[1]
                    log(M.toString(total / i) + "=" * (72 * i // iterations))
                }
            }]
            return when (promiseAllFulfilled(ps)) ->
                total / iterations

        to draw(drawable) :Vow[Void]:
            "Draw `drawable` to the screen."
            def draw := consoleDraw.drawingFrom(drawable)
            def [width, height] := stdio.stdout().getWindowSize()
            return async."for"(draw(height, width), fn _, line { prompt<-writeLine(line) })

        to graph(f) :Vow[Void]:
            "
            Draw a graph of a function from Doubles to Doubles to the screen.
            "
            def [width, height] := stdio.stdout().getWindowSize()
            # Aspect ratio has to be manually done here.
            def ratio := width / height
            def graphed := calculateGraph(f, height, width, -ratio, -1.0,
                                          ratio, 1.0)
            def rows := [for row in (graphed) UTF8.encode(row, null)]
            return async."for"(rows, fn _, line { prompt<-writeLine(line) })

    object REPLHelp extends help:
        match message:
            prompt.writeLine(UTF8.encode(M.callWithMessage(super, message), null))
            null

    def which := makeWhich(makeProcess,
                           makePathSearcher(makeFileResource,
                                            currentProcess.getEnvironment()[b`PATH`]))

    # Set up the full environment.
    environment := safeScope | unsafeScope | [
        # REPL-only fun.
        => &&JSON, => &&UTF8, => &&repl,
        "&&help" => &&REPLHelp,
        => &&which,
    ]

    readEvalPrintLoop<-(prompt, &environment, unsealException)
    return when (prompt<-whenDone()) -> { 0 }
