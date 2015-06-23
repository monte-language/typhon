def [=> makeREPLTube] | _ := import("fun/repl")
def [
    => makeUTF8DecodePump,
    => makeUTF8EncodePump
] | _ := import("lib/tubes/utf8")
def [=> makePumpTube] := import("lib/tubes/pumpTube")

var environment := [
    # Constants.
    => null, => true, => false, => Infinity, => NaN,
    # Constructors and core operator expansion.
    => __makeDouble, => __makeInt, => __makeList, => __makeMap,
    => __makeOrderedSpace, => __makeString,
    => __equalizer, => __comparer,
    => __accumulateList, => __accumulateMap,
    # Guards.
    => Any, => Bool, => Char, => DeepFrozen, => Double, => Empty, => Int,
    => List, => Map, => NullOk, => Same, => Set, => Str, => SubrangeGuard,
    => Void,
    => __mapEmpty, => __mapExtract,
    => __accumulateList, => __booleanFlow, => __iterWhile, => __loop,
    => __validateFor,
    => __switchFailed, => __makeVerbFacet, => __comparer,
    => __suchThat, => __matchSame, => __bind, => __quasiMatcher,
    => simple__quasiParser,
    # Safe capabilities.
    => M, => Ref, => m__quasiParser,
    # Unsafe capabilities.
    => import, => throw,
    # Monte-only fun.
    # Typhon safe scope.
    => __auditedBy, => __slotToBinding, => _makeFinalSlot, => _makeVarSlot,
    => traceln, => unittest,
    # Typhon unsafe scope.
    => Timer, => bench, => currentProcess, => currentVat, => makeFileResource,
    => makeProcess, => makeStdErr, => makeStdIn, => makeStdOut,
    => makeTCP4ClientEndpoint, => makeTCP4ServerEndpoint,
    => unsealException,
]

# We *could* use lib/parsers/monte, but it's got a flaw; it can't interoperate
# with eval() at the moment. Instead we just wrap eval() here. It's not like
# the current MiM parser can deal with secondary prompts, anyway.
def makeMonteParser():
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

        to feedMany(tokens):
            try:
                result := eval(tokens, environment)
            catch via (unsealException) problem:
                traceln(problem)
                failure := `$problem`

def reduce(result):
    return result

def stdin := makeStdIn().flowTo(makePumpTube(makeUTF8DecodePump()))
def stdout := makePumpTube(makeUTF8EncodePump())
stdout.flowTo(makeStdOut())

def replTube := makeREPLTube(makeMonteParser, reduce, "▲> ", "…> ", stdout)
stdin.flowTo(replTube)
