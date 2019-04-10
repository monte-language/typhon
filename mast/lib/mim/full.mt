import "lib/asdl" =~ [=> asdlParser]
exports (monteBuilder, rebuild, expand)

def monteBuilder :DeepFrozen := asdlParser(mpatt`monteBuilder`, `
    expr = LiteralExpr(df value)
         | NounExpr(str name)
         | SlotExpr(expr noun)
         | BindingExpr(expr noun)
         | MetaContextExpr
         | MetaStateExpr
         | SeqExpr(expr* exprs)
         | MethodCallExpr(expr receiver, str verb, expr* args, namedArg*
                          namedArgs)
         | FunCallExpr(expr receiver, expr* args, namedArg* namedArgs)
         | SendExpr(expr receiver, str verb, expr* args, namedArg* namedArgs)
         | FunSendExpr(expr receiver, expr* args, namedArg* namedArgs)
         | GetExpr(expr receiver, expr* indices)
         | AndExpr(expr left, expr right)
         | OrExpr(expr left, expr right)
         | BinaryExpr(expr left, str op, expr right)
         | CompareExpr(expr left, str op, expr right)
         | RangeExpr(expr left, str op, expr right)
         | SameExpr(expr left, expr right, bool direction)
         | MatchBindExpr(expr specimen, pattern pattern)
         | MismatchExpr(expr specimen, pattern pattern)
         | ControlExpr(expr target, str operator, expr* args, pattern* params,
                       expr body, bool isTop)
         | PrefixExpr(str op, expr receiver)
         | CoerceExpr(expr specimen, expr guard)
         | CurryExpr(expr receiver, str verb, bool isSend)
         | ExitExpr(str name, expr? value)
         | ForwardExpr(pattern pattern)
         | DefExpr(pattern pattern, expr? exit, expr expr)
         | AssignExpr(expr lvalue, expr rvalue)
         | VerbAssignExpr(str verb, expr lvalue, expr rvalue)
         | AugAssignExpr(str op, expr lvalue, expr rvalue)
         | FunctionExpr(pattern* params, namedParam* namedParams, expr body)
         | ListExpr(expr* items)
         | ListComprehensionExpr(expr iterable, expr? filter, pattern? key,
                                 pattern value, expr body)
         | MapExpr(mapItem* pairs)
         | MapComprehensionExpr(expr iterable, expr? filter, pattern? key,
                                pattern value, expr bodyKey, expr bodyValue)
         | ForExpr(expr iterable, pattern? key, pattern value, expr body,
                   pattern? catchPattern, expr? catchBody)
         | ObjectExpr(str? docstring, pattern name, expr? asExpr,
                      expr* auditors, script script)
         | InterfaceExpr(str? docstring, pattern name, pattern? stamp,
                         expr* parents, expr* auditors, messageDesc* messages)
         | FunctionInterfaceExpr(str? docstring, pattern name, pattern? stamp,
                                 expr* parents, expr* auditors,
                                 messageDesc messageDesc)
         | CatchExpr(expr body, pattern pattern, expr catcher)
         | FinallyExpr(expr body, expr unwinder)
         | EscapeExpr(pattern ejectorPattern, expr body,
                      pattern? catchPattern, expr? catchBody)
         | SwitchExpr(expr specimen, matcher* matchers)
         | WhenExpr(expr* args, expr body, catcher* catchers, expr? finally)
         | IfExpr(expr test, expr then, expr? else)
         | WhileExpr(expr test, expr body, catcher? catcher)
         | HideExpr(expr body)
         | QuasiParserExpr(str? name, quasiPiece* quasis)
         | ValueHoleExpr(int index)
         | PatternHoleExpr(int index)
         | Module(import* imports, expr* exports, expr body)
         attributes (df span)
    pattern = IgnorePattern(expr? guard)
            | FinalPattern(expr noun, expr? guard)
            | SlotPattern(expr noun, expr? guard)
            | VarPattern(expr noun, expr? guard)
            | BindPattern(expr noun, expr? guard)
            | BindingPattern(expr noun)
            | ListPattern(pattern* patterns, pattern? tail)
            | MapPattern(mapPatternItem* patterns, pattern? tail)
            | ViaPattern(expr expr, pattern pattern)
            | SuchThatPattern(pattern pattern, expr expr)
            | SamePattern(expr value, bool direction)
            | QuasiParserPattern(str? name, quasiPiece* quasis)
            | ValueHolePattern(int index)
            | PatternHolePattern(int index)
            attributes (df span)
    namedArg = NamedArg(expr key, expr value) | NamedArgExport(expr value)
             attributes (df span)
    mapItem = MapExprAssoc(expr key, expr value) | MapExprExport(expr value)
            attributes (df span)
    mapPatternItem = MapPatternAssoc(expr key, pattern value, expr? default)
                   | MapPatternImport(pattern value, expr? default)
                   attributes (df span)
    namedParam = NamedParam(expr key, pattern value, expr? default)
               | NamedParamImport(pattern value, expr? default)
               attributes (df span)
    method = Method(str? docstring, str verb, pattern* params,
                    namedParam* namedParams, expr? resultGuard, expr body)
           | To(str? docstring, str verb, pattern* params,
                namedParam* namedParams, expr? resultGuard, expr body)
           attributes (df span)
    matcher = (pattern pattern, expr body)
    catcher = (pattern pattern, expr body)
    script = Script(expr? extends, method* methods, matcher* matchers)
           | FunctionScript(str verb, pattern* params,
                            namedParam* namedParams, expr? resultGuard,
                            expr body)
           attributes (df span)
    paramDesc = (str name, expr? guard)
    messageDesc = (str? docstring, str verb, paramDesc* params,
                   paramDesc* namedParams, expr? resultGuard)
    quasiPiece = QuasiText(str text)
               | QuasiExprHole(expr expr)
               | QuasiPatternHole(pattern pattern)
               attributes (df span)
    import = (str name, pattern pattern)
`, null)

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

def mb :DeepFrozen := monteBuilder
def expand(ast :DeepFrozen) as DeepFrozen:
    def ex :DeepFrozen := expand
    object xp as DeepFrozen:
        to FunCallExpr(receiver, args, namedArgs, span):
            return mb.MethodCallExpr(receiver, "run", args, namedArgs, span)

        to SendExpr(receiver, verb, args, namedArgs, span):
            def nas := mb.MapExpr([for na in (namedArgs) {
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
                                     [receiver, mb.LiteralExpr(verb, null),
                                      mb.ListExpr(args, null), nas], [], span)

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

        to CoerceExpr(specimen, guard, span):
            return mb.MethodCallExpr(guard, "coerce",
                                     [specimen, ex(m`throw`)], [], span)

        to AugAssignExpr(op :Str, lvalue, rvalue, span):
            return mb.AssignExpr(lvalue,
                                 xp.BinaryExpr(lvalue, op, rvalue, span),
                                 span)

        to ListExpr(exprs, span):
            return mb.MethodCallExpr(ex(m`_makeList`), "run", exprs, [], span)

        # Kernel-Monte is handled here.
        match [verb, args, _]:
            M.call(monteBuilder, verb, args, [].asMap())
    return rebuild(ast)(xp)
