def [=> astBuilder] | _ := import("lib/monte/monte_ast")
def [=> makeMonteLexer] | _ := import("lib/monte/monte_lexer")
def [=> parseExpression] | _ := import("lib/monte/monte_parser")
def [=> expand] := import("lib/monte/monte_expander")
def [=> optimize] := import("lib/monte/monte_optimizer")


def makeMonteParser():
    var failure :NullOk[Str] := null
    var results := null

    return object monteParser:
        to getFailure() :NullOk[Str]:
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
                def tree := parseExpression(makeMonteLexer(tokens),
                                            astBuilder, throw)
                results := [optimize(expand(tree, astBuilder, throw))]
            catch problem:
                failure := `$problem`

[=> makeMonteParser]
