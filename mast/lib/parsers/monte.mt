def scope := safeScope | [=> &&bench]
def [=> dump :DeepFrozen] | _ := ::"import".script("lib/monte/ast_dumper", scope)
def [=> makeMonteLexer :DeepFrozen] | _ := ::"import".script("lib/monte/monte_lexer",
                                                  scope)
def [=> parseExpression :DeepFrozen] | _ := ::"import".script("lib/monte/monte_parser",
                                                   scope)
def [=> expand :DeepFrozen] | _ := ::"import".script("lib/monte/monte_expander",
                                          scope)
def [=> optimize :DeepFrozen] | _ := ::"import".script("lib/monte/monte_optimizer",
                                            scope)

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
