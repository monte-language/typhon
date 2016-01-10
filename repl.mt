exports (main)

def [=> help :DeepFrozen] | _ := ::"import"("lib/help")

# We *could* use lib/parsers/monte, but it's got a flaw; it can't interoperate
# with eval() at the moment. Instead we just wrap eval() here. It's not like
# the current MiM parser can deal with secondary prompts, anyway.
def makeMonteParser(var environment, unsealException) as DeepFrozen:
    var failure :NullOk[Str] := null
    var result := null

    def playWith(module :Str, scope :Map) :Void:
        "Import a module and bring it into the environment."
        def map := ::"import"(module, scope)
        for k :Str => v :DeepFrozen in map:
            environment with= (k, &&v)
            traceln(`Adding $k to environment`)
    environment with= ("playWith", &&playWith)

    return object monteEvalParser:
        to getFailure() :NullOk[Str]:
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            return true

        to results() :List:
            return [result]

        to feed(token):
            monteEvalParser.feedMany([token])

        to reset():
            failure := null
            result := null
            return monteEvalParser

        to feedMany(tokens):
            try:
                def [val, newEnv] := eval.evalToPair(tokens, environment)
                result := val
                # Preserve side-effected new stuff from e.g. playWith.
                environment := newEnv | environment
            catch via (unsealException) [problem, trail]:
                failure := `$problem`
                # Discard the first line from the trail since it's always the
                # eval() frame, which is noisy and useless. Also the second
                # line. And maybe more lines in the future?
                for line in trail.reverse().slice(2):
                    traceln(line)

def reduce(result) as DeepFrozen:
    return result

def main(=> Timer, => bench, => unittest,
         => currentProcess, => currentRuntime, => currentVat,
         => getAddrInfo,
         => makeFileResource, => makeProcess,
         => makeStdErr, => makeStdIn, => makeStdOut,
         => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint,
         => unsealException, => unsafeScope) as DeepFrozen:
    def [
        => makeUTF8DecodePump :DeepFrozen,
        => makeUTF8EncodePump :DeepFrozen,
        => makePumpTube :DeepFrozen,
    ] | _ := ::"import"("lib/tubes", [=> unittest])

    def [=> makeREPLTube] | _ := ::"import".script("fun/repl")

    def baseEnvironment := safeScope | [
        # Typhon unsafe scope.
        => &&Timer, => &&bench, => &&currentProcess, => &&currentRuntime, => &&currentVat,
        => &&getAddrInfo,
        => &&makeFileResource, => &&makeProcess, => &&makeStdErr, => &&makeStdIn,
        => &&makeStdOut, => &&makeTCP4ClientEndpoint, => &&makeTCP4ServerEndpoint,
        => &&unsealException,
        # REPL-only fun.
        => &&help, => &&unittest,
    ]

    var environment := [for `&&@name` => binding in (baseEnvironment) name => binding]

    def stdin := makeStdIn()<-flowTo(makePumpTube(makeUTF8DecodePump()))
    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout<-flowTo(makeStdOut())
    def parser := makeMonteParser(environment, unsealException)
    def replTube := makeREPLTube(fn {parser.reset()}, reduce,
                                 "▲> ", "…> ", stdout)
    stdin<-flowTo(replTube)

    return 0
