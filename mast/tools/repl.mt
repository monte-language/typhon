import "lib/codec/utf8" =~ [=> UTF8]
import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/streams" =~ [
    => alterSink :DeepFrozen,
    => alterSource :DeepFrozen,
]
import "lib/repl" =~ [=> runREPL :DeepFrozen]
import "lib/help" =~ [=> help :DeepFrozen]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/muffin" =~ [=> makeLimo]
exports (main)

def makeMonteParser(&environment, unsealException) as DeepFrozen:
    var failure :NullOk[Str] := null
    var result := null
    var line :Str := ""

    return object monteEvalParser:
        to getFailure() :NullOk[Str]:
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            return result != null

        to results() :List:
            return [result]

        to feedMany(s :Str):
            if (s.size() == 0):
                return

            line += s
            try:
                escape ejPartial:
                    def [val, newEnv] := eval.evalToPair(line, environment, => ejPartial, "inRepl" => true)
                    result := val
                    # Preserve side-effected new stuff from e.g. playWith.
                    environment := newEnv | environment
            catch p:
                # Typhon's exception handling is kinda broken so we try to cope
                # by ignoring things that aren't sealed exceptions.
                if (p =~ via (unsealException) [problem, trail]):
                    failure := `Exception: $problem$\n` + "\n".join(trail.reverse())

def makeFileLoader(root, makeFileResource) as DeepFrozen:
    return def load(petname):
        def path := `$root/$petname.mt`
        traceln(`Reading file: $path`)
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            traceln(`Parsing Monte code: $path`)
            def s := UTF8.decode(bs, null)
            def lex := makeMonteLexer(s, petname)
            [s, parseModule(lex, astBuilder, null)]

def main(_argv,
         => makeFileResource,
         => Timer,
         => stdio, => unsealException, => unsafeScope) :Vow[Int] as DeepFrozen:

    # Forward-declare the environment.
    var environment := null

    object repl:
        "Some useful REPL stuff."

        to instantiateModule(basePath :Str, petname :Str) :Vow[DeepFrozen]:
            "
            Get an instance of the  module named `petname` from `basePath` on
            the filesystem.
            "

            def loader := makeFileLoader(basePath, makeFileResource)
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
            traceln(`m $m`)
            return when (m) ->
                traceln(`Instantiated $petname: $m`)
                def ex := try { m(null) } catch e { traceln.exception(e); -1 }
                for k => v :DeepFrozen in (ex):
                    traceln(`Loading into environment: $k`)
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

    # Set up the full environment.
    environment := safeScope | unsafeScope | [
        # REPL-only fun.
        => &&JSON, => &&UTF8, => &&help, => &&repl,
    ]

    def stdin := alterSource.decodeWith(UTF8, stdio.stdin(),
                                        "withExtras" => true)
    def stdout := alterSink.encodeWith(UTF8, stdio.stdout())
    def p := runREPL(fn { makeMonteParser(&environment, unsealException) },
                     M.toQuote, "▲> ", "…> ", stdin, stdout)
    return when (p) -> { 0 }
