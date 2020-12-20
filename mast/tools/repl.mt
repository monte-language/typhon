import "lib/codec/utf8" =~ [=> UTF8]
import "lib/commandLine" =~ [=> makePrompt]
import "lib/console" =~ [=> consoleDraw]
import "lib/graphing" =~ [=> calculateGraph]
import "lib/help" =~ [=> help]
import "lib/iterators" =~ [=> async]
import "lib/json" =~ [=> JSON]
import "lib/muffin" =~ [=> makeFileLoader, => makeLimo]
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

        to obtainMuffin(basePath :Str, petname :Str) :Vow[DeepFrozen]:
            "
            Make a muffin from module `petname`, using `basePath` on the
            filesystem for the module library.
            "

            def loader := makeFileLoader(fn name {
                makeFileResource(`$basePath/$name`)<-getContents()
            })
            def limo := makeLimo(loader)
            return when (def p := loader(petname)) ->
                def [source :NullOk[Str], expr] := p
                limo(petname, source, expr)
            catch problem:
                traceln.exception(problem)
                log(`Couldn't instantiate $petname`)

        to instantiateModule(basePath :Str, petname :Str) :Vow[DeepFrozen]:
            "
            Get an instance of the module named `petname` from `basePath` on
            the filesystem.
            "

            def expr := repl.obtainMuffin(basePath, petname)
            return when (expr) -> { eval(expr, safeScope) }

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
                prompt<-writeLine(b`Couldn't load $petname`)

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

        to graph(f, => window :NullOk[List[Double]] := null) :Vow[Void]:
            "
            Draw a graph of a function from Doubles to Doubles to the screen.

            `=> window`, when provided, should be a list of four Doubles
            [x1, y1, x2, y2] which will override the automatic scaled window.
            Note that the terminal window size will still control the aspect ratio!
            "
            def [width, height] := stdio.stdout().getWindowSize()
            # Aspect ratio has to be manually done here.
            def [x1, y1, x2, y2] := if (window != null) { window } else {
                def ratio := width / height
                [-ratio, -1.0, ratio, 1.0]
            }
            def graphed := calculateGraph(f, height, width, x1, y1, x2, y2)
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
