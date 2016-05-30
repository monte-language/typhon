from typhon.nanopass import IR

MastIR = IR(
    ["Noun"],
    {
        "Expr": {
            "NullExpr": [],
            "CharExpr": [("c", None)],
            "DoubleExpr": [("d", None)],
            "IntExpr": [("i", None)],
            "StrExpr": [("s", None)],
            "AssignExpr": [("name", "Noun"), ("rvalue", "Expr")],
            "BindingExpr": [("name", "Noun")],
            "CallExpr": [("obj", "Expr"), ("verb", None), ("args", "Expr*"),
                         ("namedArgs", "NamedArg*")],
            "DefExpr": [("patt", "Patt"), ("ex", "Expr"), ("rvalue", "Expr")],
            "EscapeOnlyExpr": [("patt", "Patt"), ("body", "Expr")],
            "EscapeExpr": [("ejPatt", "Patt"), ("ejBody", "Expr"),
                           ("catchPatt", "Patt"), ("catchBody", "Expr")],
            "FinallyExpr": [("body", "Expr"), ("atLast", "Expr")],
            "HideExpr": [("body", "Expr")],
            "IfExpr": [("test", "Expr"), ("cons", "Expr"), ("alt", "Expr")],
            "MetaContextExpr": [],
            "MetaStateExpr": [],
            "NounExpr": [("name", "Noun")],
            "ObjectExpr": [("doc", None), ("patt", "Patt"),
                           ("auditors", "Expr*"), ("methods", "Method*"),
                           ("matchers", "Matcher*")],
            "SeqExpr": [("exprs", "Expr*")],
            "TryExpr": [("body", "Expr"), ("catchPatt", "Patt"),
                        ("catchBody", "Expr")],
        },
        "Patt": {
            "IgnorePatt": [("guard", "Expr")],
            "BindingPatt": [("name", "Noun")],
            "FinalPatt": [("name", "Noun"), ("guard", "Expr")],
            "VarPatt": [("name", "Noun"), ("guard", "Expr")],
            "ListPatt": [("patts", "Patt*")],
            "ViaPatt": [("trans", "Expr"), ("patt", "Patt")],
        },
        "NamedArg": {
            "NamedArg": [("key", "Expr"), ("value", "Expr")],
        },
        "NamedPatt": {
            "NamedPatt": [("key", "Expr"), ("patt", "Patt"), ("default", "Expr")],
        },
        "Matcher": {
            "MatcherExpr": [("patt", "Patt"), ("body", "Expr")],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("verb", None), ("patt", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr")],
        },
    }
)
