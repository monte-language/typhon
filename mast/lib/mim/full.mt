import "lib/mim/syntax/full" =~ ["ASTBuilder" => monteBuilder]
exports (monteBuilder, rebuild, expand)

def rebuild(ast :DeepFrozen) as DeepFrozen:
    def rebuilder(node, _maker, args, span):
        def verb := node.getNodeName()
        return M.call(monteBuilder, verb, args.with(span), [].asMap())
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
    def ex :DeepFrozen := expand
    object xp as DeepFrozen:
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

        to AugAssignExpr(op :Str, lvalue, rvalue, span):
            return mb.AssignExpr(lvalue,
                                 xp.BinaryExpr(lvalue, op, rvalue, span),
                                 span)

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

        # Patterns.

        to SlotPattern(noun, guard, span):
            def slotToBinding := ex(m`_slotToBinding`)
            def trans := if (guard == null) { slotToBinding } else {
                mb.MethodCallExpr(slotToBinding, "run", [guard], [], span)
            }
            return mb.ViaPattern(trans, mb.BindingPattern(noun, span), span)

        to BindPattern(noun, guard, span):
            def g := if (guard == null) { ex(m`null`) } else { guard }
            def resolver := mb.NounExpr(noun(nounName) + "_Resolver", span)
            return mb.ViaPattern(mb.MethodCallExpr(ex(m`_bind`), "run",
                                                   [resolver, g], [], span),
                                 mb.IgnorePattern(null, span))

        to SuchThatPattern(patt, expr, span):
            def st := ex(m`_suchThat`)
            def innerPatt := mb.ViaPattern(mb.MethodCallExpr(st, "run",
                                                             [expr], [],
                                                             span),
                                           mb.IgnorePattern(null, span))
            return mb.ViaPattern(st, mb.ListPattern([patt, innerPatt], null,
                                                    span), span)

        to SamePattern(value, direction :Bool, span):
            def verb :Str := direction.pick("run", "different")
            return mb.ViaPattern(mb.MethodCallExpr(ex(m`_matchSame`), verb,
                                                   [value], [], span),
                                 mb.IgnorePattern(null, span))

        # Kernel-Monte is handled here; kernel nodes generally only need to be
        # recursed through, not changed.
        match [verb, args, _]:
            M.call(monteBuilder, verb, args, [].asMap())
    return rebuild(ast)(xp)
