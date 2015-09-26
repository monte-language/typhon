imports
exports (main)

# We *could* use lib/parsers/monte, but it's got a flaw; it can't interoperate
# with eval() at the moment. Instead we just wrap eval() here. It's not like
# the current MiM parser can deal with secondary prompts, anyway.
def makeMonteParser(var environment) as DeepFrozen:
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
         => makeFileResource, => makeProcess,
         => makeStdErr, => makeStdIn, => makeStdOut,
         => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint,
         => unsealException) as DeepFrozen:

    def [=> makeREPLTube] | _ := import.script("fun/repl")
    def [
        => makeUTF8DecodePump,
        => makeUTF8EncodePump
    ] | _ := import.script("lib/tubes/utf8")
    def [=> makePumpTube] := import.script("lib/tubes/pumpTube")

    def baseEnvironment := [
        # Constants.
        => &&null, => &&true, => &&false, => &&Infinity, => &&NaN,
        # Constructors and core operator expansion.
        => &&_makeBytes, => &&__makeDouble, => &&__makeInt, => &&__makeList, => &&__makeMap,
        => &&__makeMessageDesc, => &&_makeOrderedSpace, => &&__makeParamDesc,
        => &&__makeProtocolDesc, => &&__makeString,
        => &&__equalizer, => &&_comparer,
        => &&_accumulateList, => &&_accumulateMap,
        # Guards.
        => &&Any, => &&Bool, => &&Char, => &&DeepFrozen, => &&Double, => &&Empty, => &&Int,
        => &&List, => &&Map, => &&Near, => &&NullOk, => &&Same, => &&Set, => &&Str,
        => &&SubrangeGuard,  => &&Transparent, => &&Void,
        => &&_mapEmpty, => &&_mapExtract,
        => &&_accumulateList, => &&__auditedBy, => &&_booleanFlow, => &&_iterWhile,
        => &&__loop, => &&_validateFor,
        => &&_switchFailed, => &&_makeVerbFacet,
        => &&_suchThat, => &&_matchSame, => &&_bind, => &&_quasiMatcher,
        => &&b__quasiParser, => &&simple__quasiParser,
        # Safe capabilities.
        => &&M, => &&Ref, => &&help, => &&m__quasiParser,
        # Unsafe capabilities.
        => &&import, => &&throw,
        # Monte-only fun.
        # Typhon safe scope.
        => &&__auditedBy, => &&__slotToBinding, => &&_makeFinalSlot, => &&_makeVarSlot,
        => &&makeBrandPair, => &&traceln, => &&unittest,
        # Typhon unsafe scope.
        => &&Timer, => &&bench, => &&currentProcess, => &&currentRuntime, => &&currentVat,
        => &&makeFileResource, => &&makeProcess, => &&makeStdErr, => &&makeStdIn,
        => &&makeStdOut, => &&makeTCP4ClientEndpoint, => &&makeTCP4ServerEndpoint,
        => &&unsealException,
    ]

    var environment := [for `&&@name` => binding in (baseEnvironment) name => binding]

    def stdin := makeStdIn()<-flowTo(makePumpTube(makeUTF8DecodePump()))
    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout<-flowTo(makeStdOut())
    def parser := makeMonteParser(environment)
    def replTube := makeREPLTube(fn {parser.reset()}, reduce,
                                 "▲> ", "…> ", stdout)
    stdin<-flowTo(replTube)

    return 0
