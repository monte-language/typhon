# Boot scope nonsense.
def parserScope := [
    => Any, => Bool, => Char, => DeepFrozen, => Double, => Empty, => Int,
    => List, => Map, => NullOk, => Same, => Set, => Str, => SubrangeGuard,
    => Void,
    => __mapEmpty, => __mapExtract,
    => __accumulateList, => __accumulateMap, => __booleanFlow, => __iterWhile,
    => __validateFor,
    => __switchFailed, => __makeVerbFacet, => __comparer,
    => __suchThat, => __matchSame, => __bind, => __quasiMatcher,
    => M, => import, => throw, => typhonEval,
    => simple__quasiParser, => term__quasiParser, => __makeOrderedSpace,
    => bench,
]

def [=> astBuilder] | _ := import("prelude/monte_ast", parserScope)
def [=> dump] | _ := import("lib/monte/ast_dumper", parserScope)
def [=> makeMonteLexer] | _ := import("lib/monte/monte_lexer", parserScope)
def [=> parseExpression] | _ := import("lib/monte/monte_parser", parserScope)
def [=> expand] | _ := import("lib/monte/monte_expander", parserScope)
def [=> optimize] | _ := import("lib/monte/monte_optimizer", parserScope)


def makeMonteParser(inputName):
    var failure := null
    var results := null

    return object monteParser:
        to getFailure():
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            return true

        to results() :List:
            return results

        to feed(token):
            monteParser.feedMany([token])
            if (failure != null):
                return

        to feedMany(tokens):
            try:
                def tree := parseExpression(makeMonteLexer(tokens, inputName),
                                            astBuilder, throw)
                # results := [optimize(expand(tree, astBuilder, throw))]
                results := [expand(tree, astBuilder, throw)]
            catch problem:
                failure := problem

        to dump():
            def result := monteParser.results()[0]
            def data := [].diverge()
            dump(result, data.extend)
            return data.snapshot()

[=> makeMonteParser]
