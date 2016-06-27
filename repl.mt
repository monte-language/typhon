import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/tubes" =~ [
    => makeUTF8DecodePump :DeepFrozen,
    => makeUTF8EncodePump :DeepFrozen,
    => makePumpTube :DeepFrozen,
]
import "fun/repl" =~ [=> makeREPLTube :DeepFrozen]
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
                    failure := `$problem`
                    for line in (trail.reverse()):
                        traceln(line)
                    buf := []

def reduce(result) as DeepFrozen:
    return result

def main(argv, => Timer, => currentProcess, => currentRuntime, => currentVat,
         => getAddrInfo, # => packageLoader,
         => makeFileResource, => makeProcess,
         => makeStdErr, => makeStdIn, => makeStdOut,
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
        => &&makeFileResource, => &&makeProcess, => &&makeStdErr, => &&makeStdIn,
        => &&makeStdOut, => &&makeTCP4ClientEndpoint, => &&makeTCP4ServerEndpoint,
        => &&unsealException,
        # REPL-only fun.
        => &&JSON, => &&help, # => &&playWith,
    ]

    def stdin := makeStdIn() <- flowTo(makePumpTube(makeUTF8DecodePump()))
    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout <- flowTo(makeStdOut())
    def parser := makeMonteParser(&environment, unsealException)
    def replTube := makeREPLTube(fn {parser.reset()}, reduce,
                                 "▲> ", "…> ", stdout)
    stdin <- flowTo(replTube)

    return 0
