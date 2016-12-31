import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/streams" =~ [
    => alterSink :DeepFrozen,
    => alterSource :DeepFrozen,
    => flow :DeepFrozen,
]
import "fun/repl" =~ [=> runREPL :DeepFrozen]
import "lib/help" =~ [=> help :DeepFrozen]
exports (main)

def makeMonteParser(&environment, unsealException) as DeepFrozen:
    var failure :NullOk[Str] := null
    var result := null
    var buf := []

    return object monteEvalParser:
        to getFailure() :NullOk[Str]:
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            return buf == []

        to results() :List:
            return [result]

        to feed(token):
            monteEvalParser.feedMany([token])

        to reset():
            failure := null
            result := null
            return monteEvalParser

        to feedMany(tokens):
            if (buf.size() == 0):
                # Buffer the first line.
                buf with= (tokens)
            else:
                 if (tokens != ""):
                     # If we know we need to buffer more, don't invoke the parser.
                     buf with= (tokens)
                     return
                 # ... If there's data in the buffer and a blank line is
                 # received, go ahead and parse.
            try:
                escape ejPartial:
                    def [val, newEnv] := eval.evalToPair("\n".join(buf) + "\n", environment, => ejPartial, "inRepl" => true)
                    result := val
                    # Preserve side-effected new stuff from e.g. playWith.
                    environment := newEnv | environment
                    buf := []
            catch p:
                # Typhon's exception handling is kinda broken so we try to cope
                # by ignoring things that aren't sealed exceptions.
                if (p =~ via (unsealException) [problem, trail]):
                    failure := `Exception: $problem`
                    for line in (trail.reverse()):
                        failure += "\n" + line
                    buf := []

def main(argv, => Timer, => currentProcess, => currentRuntime, => currentVat,
         => getAddrInfo, # => packageLoader,
         => makeFileResource, => makeProcess,
         => stdio,
         => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint,
         => unsealException, => unsafeScope) as DeepFrozen:

    # def playWith(module :Str, scope :Map) :Void:
    #     "Import a module and bring it into the environment."
    #     def map := packageLoader."import"(module)
    #     for k :Str => v :DeepFrozen in map:
    #         environment with= (k, &&v)
    #         traceln(`Adding $k to environment`)
    var environment := safeScope | [
        # Typhon unsafe scope.
        => &&Timer, => &&currentProcess, => &&currentRuntime, => &&currentVat,
        => &&getAddrInfo,
        => &&makeFileResource, => &&makeProcess, => &&stdio,
        => &&makeTCP4ClientEndpoint, => &&makeTCP4ServerEndpoint,
        => &&unsealException,
        # REPL-only fun.
        => &&JSON, => &&UTF8, => &&help, # => &&playWith,
    ]

    def stdin := alterSource.decodeWith(UTF8, stdio.stdin(),
                                        "withExtras" => true)
    def stdout := alterSink.encodeWith(UTF8, stdio.stdout())
    def parser := makeMonteParser(&environment, unsealException)
    def p := runREPL(parser.reset, fn x {x}, "▲> ", "…> ", stdin, stdout)
    return when (p) -> { 0 }
