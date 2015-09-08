# Boot scope nonsense.
def parserScope := [
    => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
    => Int, => List, => Map, => NullOk, => Same, => Set, => Str,
    => SubrangeGuard, => Void,
    => _mapEmpty, => _mapExtract,
    => _accumulateList, => _accumulateMap, => _booleanFlow, => _iterWhile,
    => _validateFor,
    => _switchFailed, => _makeVerbFacet, => _comparer,
    => _suchThat, => _matchSame, => _bind, => _quasiMatcher,
    => M, => import, => throw, => typhonEval,
    => b__quasiParser, => simple__quasiParser,
    => _makeOrderedSpace, => bench, => astBuilder,
]

def [=> dump :DeepFrozen] | _ := import("lib/monte/ast_dumper", parserScope)
def [=> makeMonteLexer :DeepFrozen] | _ := import("lib/monte/monte_lexer",
                                                  parserScope)
def [=> parseExpression :DeepFrozen] | _ := import("lib/monte/monte_parser",
                                                   parserScope)
def [=> expand :DeepFrozen] | _ := import("lib/monte/monte_expander",
                                          parserScope)
def [=> optimize :DeepFrozen] | _ := import("lib/monte/monte_optimizer",
                                            parserScope)

def makeMonteParser(inputName) as DeepFrozen:
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
            var data := b``
            dump(result, fn bs {data += bs})
            return data

[=> makeMonteParser]
