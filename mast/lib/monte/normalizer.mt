exports (normalize)


def normalize(ast, builder) as DeepFrozen:
    def normalizeTransformer(node, _maker, args, span):
        return switch (node.getNodeName()):
            match =="LiteralExpr":
                switch (args[0]):
                    match ==null:
                        builder.NullExpr(span)
                    match i :Int:
                        builder.IntExpr(i, span)
                    match s :Str:
                        builder.StrExpr(s, span)
                    match c :Char:
                        builder.CharExpr(c, span)
                    match d :Double:
                        builder.DoubleExpr(d, span)
            match =="AssignExpr":
                def [_name, rvalue] := args
                builder.AssignExpr(node.getLvalue().getName(), rvalue, span)
            match =="BindingExpr":
                builder.BindingExpr(node.getNoun().getName(), span)
            match =="CatchExpr":
                def [body, patt, catchbody] := args
                builder.TryExpr(body, patt, catchbody, span)
            match =="MethodCallExpr":
                def [obj, verb, margs, namedArgs] := args
                builder.CallExpr(obj, verb, margs, namedArgs, span)
            match =="EscapeExpr":
                if (args =~ [patt, body, ==null, ==null]):
                    builder.EscapeOnlyExpr(patt, body, span)
                else:
                    def [ejPatt, ejBody, catchPatt, catchBody] := args
                    builder.EscapeExpr(ejPatt, ejBody, catchPatt, catchBody, span)
            match =="ObjectExpr":
                def [doc, name, asExpr, auditors, [methods, matchers]] := args
                builder.ObjectExpr(if (doc == null) {""} else {doc}, name,
                                   [asExpr] + auditors, methods, matchers,
                                   span)
            match =="Script":
                def [_, methods, matchers] := args
                [methods, matchers]
            match =="IgnorePattern":
                def [guard] := args
                builder.IgnorePatt(guard, span)
            match =="BindingPattern":
                builder.BindingPatt(node.getNoun().getName(), span)
            match =="FinalPattern":
                def [_, guard] := args
                builder.FinalPatt(node.getNoun().getName(), guard, span)
            match =="VarPattern":
                def [_, guard] := args
                builder.VarPatt(node.getNoun().getName(), guard, span)
            match =="ListPattern":
                def [patts, _] := args
                builder.ListPatt(patts, span)
            match =="ViaPattern":
                def [expr, patt] := args
                builder.ViaPatt(expr, patt, span)
            match =="NamedArg":
                def [key, value] := args
                builder.NamedArgExpr(key, value, span)
            match =="NamedParam":
                def [k, p, d] := args
                builder.NamedPattern(k, p, d, span)
            match =="Matcher":
                def [patt, body] := args
                builder.MatcherExpr(patt, body, span)
            match =="Method":
                def [doc, verb, patts, namedPatts, guard, body] := args
                builder.MethodExpr(if (doc == null) {""} else {doc}, verb,
                                   patts, namedPatts, guard, body, span)
            match nodeName:
                M.call(builder, nodeName, args + [span], [].asMap())

    return ast.transform(normalizeTransformer)
