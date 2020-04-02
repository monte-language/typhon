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

def loadPlain(log, root, makeFileResource, petname) as DeepFrozen:
    def path := `$root/$petname.mt`
    log(`Reading file: $path`)
    def bs := makeFileResource(path)<-getContents()
    return when (bs) ->
        log(`Parsing Monte code: $path`)
        def s := UTF8.decode(bs, null)
        def lex := makeMonteLexer(s, petname)
        [s, parseModule(lex, astBuilder, null)]

# XXX factor with mast/montec
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

def loadLiterate(log, root, makeFileResource, petname) as DeepFrozen:
    def path := `$root/$petname.mt.md`
    log(`Reading file: $path`)
    def bs := makeFileResource(path)<-getContents()
    return when (bs) ->
        log(`Parsing Monte code: $path`)
        def s := stripMarkdown(UTF8.decode(bs, null))
        def lex := makeMonteLexer(s, petname)
        [s, parseModule(lex, astBuilder, null)]

def makeFileLoader(log, root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def lit := loadLiterate(log, root, makeFileResource, petname)
        return when (lit) -> { lit } catch _ {
            loadPlain(log, root, makeFileResource, petname)
        }

def main(_argv,
         => makeFileResource,
         => Timer,
         => stdio, => unsealException, => unsafeScope) :Vow[Int] as DeepFrozen:

    # Forward-declare the environment.
    var environment := null

    def [prompt, cleanup] := makePrompt(stdio)
    def log(s :Str):
        prompt.setLine(b`Log: ` + UTF8.encode(s, null))

    object repl:
        "Some useful REPL stuff."

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
                def [source, expr] := p
                when (def m := limo(petname, source, expr)) ->
                    eval(m, safeScope)

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

    # Set up the full environment.
    environment := safeScope | unsafeScope | [
        # REPL-only fun.
        => &&JSON, => &&UTF8, => &&repl,
        "&&help" => &&REPLHelp,
    ]

    readEvalPrintLoop<-(prompt, &environment, unsealException)
    return when (prompt<-whenDone()) -> { 0 }
