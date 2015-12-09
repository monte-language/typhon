imports
exports (main)

def [=> help :DeepFrozen] | _ := import("lib/help")

def [
    => makeUTF8DecodePump :DeepFrozen,
    => makeUTF8EncodePump :DeepFrozen,
] | _ := import("lib/tubes/utf8")
def [=> makePumpTube :DeepFrozen] := import("lib/tubes/pumpTube")

# We *could* use lib/parsers/monte, but it's got a flaw; it can't interoperate
# with eval() at the moment. Instead we just wrap eval() here. It's not like
# the current MiM parser can deal with secondary prompts, anyway.
def makeMonteParser(var environment, unsealException) as DeepFrozen:
    var failure :NullOk[Str] := null
    var result := null

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
                environment := newEnv
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

    def [=> makeREPLTube] | _ := import.script("fun/repl")

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
