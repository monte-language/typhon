import "lib/mim/syntax/gradual" =~ ["ASTBuilder" => types]
exports (typeCheck)

def inferTypeFor(expr, errors) as DeepFrozen:
    return expr(object typer {
        # Atoms: Return just a type.
        to LiteralExpr(val, span) {
            return switch (val) {
                match _ :Int { types.IntTy() }
                match _ {
                    errors.push([span,
                                 `Didn't know you could put $val in literals`])
                    types.AnyTy()
                }
            }
        }
        to NounExpr(_name, _span) {
            return types.AnyTy()
        }
        # Complex expressions: Return a type and an environment.
        to Atom(a, _span) {
            return [a, [].asMap()]
        }
    })

def typeCheck(expr) :List as DeepFrozen:
    "
    Make a list of [span, message] pairs describing type problems in `expr`.
    "

    def rv := [].diverge()
    inferTypeFor(expr, rv)
    return rv.snapshot()
