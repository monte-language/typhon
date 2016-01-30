import "lib/monte/ast_dumper" =~ [=> dump :DeepFrozen]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [=> parseExpression :DeepFrozen]
import "lib/monte/monte_expander" =~ [=> expand :DeepFrozen]
import "lib/monte/monte_optimizer" =~ [=> optimize :DeepFrozen]
exports (makeMonteParser)

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


