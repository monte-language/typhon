import "lib/mim/syntax/kernel" =~ ["ASTBuilder" => monteBuilder]
exports (monteBuilder, rebuild, expand)

def rebuild(ast :DeepFrozen, expander) as DeepFrozen:
    def rebuilder(node, _maker, args, span):
        def verb := node.getNodeName()
        return M.call(expander, verb, args.with(span), [].asMap())
    return ast.transform(rebuilder)

def rangeOps :Map[Str, Str] := [
    ".." => "thru",
    "..!" => "till",
]

def binaryOps :Map[Str, Str] := [
    "+" => "add",
    "*" => "multiply",
    "-" => "subtract",
    "//" => "floorDivide",
    "/" => "approxDivide",
    "%" => "mod",
    "**" => "pow",
    "&" => "and",
    "|" => "or",
    "^" => "xor",
    "&!" => "butNot",
    "<<" => "shiftLeft",
    ">>" => "shiftRight",
]

def unaryOps :Map[Str, Str] := [
    "!" => "not",
    "-" => "negate",
    "~" => "complement",
]

def nounName.NounExpr(name :Str, _span) :Str as DeepFrozen:
    return name

def mb :DeepFrozen := monteBuilder
def expand(ast :DeepFrozen) as DeepFrozen:
    # Recursion patterns:
    # ex() takes m`` literals of Full-Monte and interpolates them
    # xp is an AST builder which does macro expansions
    # mb is an AST builder which only allows kernel expressions
    def ex :DeepFrozen := expand
    object xp extends mb as DeepFrozen:
        to FunCallExpr(receiver, args, namedArgs, span):
            return mb.MethodCallExpr(receiver, "run", args, namedArgs, span)

        to SendExpr(receiver, verb, args, namedArgs, span):
            # XXX refactor? This reuses .MapExpr() logic, but only by building
            # new intermediate monteBuilder nodes.
            def nas := xp.MapExpr([for na in (namedArgs) {
                na(object _ {
                    to NamedArg(k, v, span) {
                        return mb.MapExprAssoc(k, v, span)
                    }
                    to NamedArgExport(v, span) {
                        return mb.MapExprExport(v, span)
                    }
                })
            }])
            return mb.MethodCallExpr(ex(m`M`), "send",
                                     [receiver, mb.LiteralExpr(verb, span),
                                      xp.ListExpr(args, span), nas], [], span)

        to FunSendExpr(receiver, args, namedArgs, span):
            return mb.SendExpr(receiver, "run", args, namedArgs, span)

        to GetExpr(receiver, indices, span):
            return mb.MethodCallExpr(receiver, "get", indices, [], span)

        to BinaryExpr(left, op :Str, right, span):
            return mb.MethodCallExpr(left, binaryOps[op], [right], [], span)

        to RangeExpr(start, op :Str, stop, span):
            def verb := "op__" + rangeOps[op]
            return mb.MethodCallExpr(ex(m`_makeOrderedSpace`), verb,
                                     [start, stop], [], span)

        to SameExpr(lhs, rhs, isSame, span):
            def expr := mb.MethodCallExpr(ex(m`_equalizer`), "sameEver",
                                          [lhs, rhs], [], span)
            return if (isSame) { expr } else {
                mb.MethodCallExpr(expr, "not", [], [], span)
            }

        to PrefixExpr(op :Str, receiver, span):
            return mb.MethodCallExpr(receiver, unaryOps[op], [], [], span)

        to CoerceExpr(specimen, guard, span):
            return mb.MethodCallExpr(guard, "coerce",
                                     [specimen, ex(m`throw`)], [], span)

        to DefExpr(patt, ex, expr, span):
            # XXX expand circular definitions
            return mb.DefExpr(patt, ex, expr, span)

        to AssignExpr(lhs, rhs, span):
            # XXX expand LHS calls
            return mb.AssignExpr(lhs(nounName), rhs, span)

        to AugAssignExpr(op :Str, lvalue, rvalue, span):
            return mb.AssignExpr(lvalue,
                                 xp.BinaryExpr(lvalue, op, rvalue, span),
                                 span)

        to ExitExpr(branch :Str, arg, span):
            def noun := mb.NounExpr("__" + branch, span)
            def args := if (arg == null) { [] } else { [arg] }
            return mb.MethodCallExpr(noun, "run", args, [], span)

        to ListExpr(exprs, span):
            return mb.MethodCallExpr(ex(m`_makeList`), "run", exprs, [], span)

        to MapExpr(pairs, span):
            def ps := [for pair in (pairs) pair.walk(object mapExpr {
                to MapExprAssoc(key, value, span) {
                    return xp.ListExpr([key, value], span)
                }
                to MapExprExport(value, span) {
                    return xp.ListExpr([value.walk(object mapExprExport {
                        to NounExpr(name, span) {
                            return mb.LiteralExpr(name, span)
                        }
                        to SlotExpr(name, span) {
                            return mb.LiteralExpr("&" + name, span)
                        }
                        to BindingExpr(name, span) {
                            return mb.LiteralExpr("&&" + name, span)
                        }
                    }), value], span)
                }
            })]
            return mb.MethodCallExpr(ex(m`_makeMap`), "fromPairs", ps, [],
                                     span)

        to FunctionExpr(patts :List, namedPatts :List, block, span):
            def m := mb."Method"(null, "run", patts, namedPatts, null, block, span)
            return mb.ObjectExpr(null, mb.IgnorePattern(null, span), null, [],
                                 mb.Script(null, [m], [], span), span)

        # Patterns.

        to FinalPattern(expr, guard, span):
            return mb.FinalPattern(expr(nounName), guard, span)

        to VarPattern(expr, guard, span):
            return mb.VarPattern(expr(nounName), guard, span)

        to BindingPattern(expr, guard, span):
            return mb.BindingPattern(expr(nounName), guard, span)

        to SlotPattern(noun, guard, span):
            def slotToBinding := ex(m`_slotToBinding`)
            def trans := if (guard == null) { slotToBinding } else {
                mb.MethodCallExpr(slotToBinding, "run", [guard], [], span)
            }
            return mb.ViaPattern(trans, xp.BindingPattern(noun, span), span)

        to BindPattern(noun, guard, span):
            def g := if (guard == null) { ex(m`null`) } else { guard }
            def resolver := mb.NounExpr(noun(nounName) + "_Resolver", span)
            return mb.ViaPattern(mb.MethodCallExpr(ex(m`_bind`), "run",
                                                   [resolver, g], [], span),
                                 mb.IgnorePattern(null, span), span)

        to SuchThatPattern(patt, expr, span):
            def st := ex(m`_suchThat`)
            def innerPatt := mb.ViaPattern(mb.MethodCallExpr(st, "run",
                                                             [expr], [],
                                                             span),
                                           mb.IgnorePattern(null, span), span)
            return mb.ViaPattern(st, mb.ListPattern([patt, innerPatt], null,
                                                    span), span)

        to SamePattern(value, direction :Bool, span):
            def verb :Str := direction.pick("run", "different")
            return mb.ViaPattern(mb.MethodCallExpr(ex(m`_matchSame`), verb,
                                                   [value], [], span),
                                 mb.IgnorePattern(null, span), span)

        # Methods.

        to "To"(docstring, verb :Str, params :List, namedParams :List, guard,
                block, span):
            def body := mb.EscapeExpr(ex(mpatt`__return`),
                mb.SeqExpr([block, ex(m`null`)], span), null, null, span)
            return mb."Method"(docstring, verb, params, namedParams, guard,
                               body, span)

        # Scripts.

        to FunctionScript(verb :Str, params :List, namedParams :List, guard,
                          block, span):
            def m := xp."To"(null, verb, params, namedParams, guard, block, span)
            return mb.Script(null, [m], [], span)
    return rebuild(ast, xp)
