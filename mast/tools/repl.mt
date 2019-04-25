import "lib/codec/utf8" =~ [=> UTF8]
import "lib/commandLine" =~ [=> makePrompt]
import "lib/help" =~ [=> help]
import "lib/json" =~ [=> JSON]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/muffin" =~ [=> makeLimo]
exports (main)

# The names throughout this section are historical.

def PS1 :Bytes := UTF8.encode("▲> ", null)
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

def readEvalPrintLoop(prompt, var locals, unsealException) as DeepFrozen:
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

def makeFileLoader(log, root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def path := `$root/$petname.mt`
        log(`Reading file: $path`)
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            log(`Parsing Monte code: $path`)
            def s := UTF8.decode(bs, null)
            def lex := makeMonteLexer(s, petname)
            [s, parseModule(lex, astBuilder, null)]

def main(_argv,
         => makeFileResource,
         => Timer,
         => stdio, => unsealException, => unsafeScope) :Vow[Int] as DeepFrozen:

    # Forward-declare the environment.
    var environment := null

    def [prompt, cleanup] := makePrompt(stdio)
    def log(s :Str):
        prompt.writeLine(b`Log: ` + UTF8.encode(s, null))

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
            log(`m $m`)
            return when (m) ->
                log(`Instantiated $petname: $m`)
                def ex := try { m(null) } catch e { traceln.exception(e); -1 }
                for k => v :DeepFrozen in (ex):
                    log(`Loading into environment: $k`)
                    environment with= (`&&$k`, &&v)

        to benchmark(callable) :Vow[Double]:
            "Run `callable` repeatedly, recording the time taken."
            def iterations :Int := 10_000
            def ps := [for _ in (0..!iterations) Timer.measureTimeTaken(callable)]
            return when (promiseAllFulfilled(ps)) ->
                var total := 0.0
                for [_, t] in (ps):
                    total += t
                total / iterations

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

    readEvalPrintLoop<-(prompt, environment, unsealException)
    return when (prompt<-whenDone()) -> { 0 }
