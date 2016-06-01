from rpython.rlib.rbigint import BASE10

from typhon.nanopass import IR
from typhon.quoting import quoteChar, quoteStr

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
            "NamedArgExpr": [("key", "Expr"), ("value", "Expr")],
        },
        "NamedPatt": {
            "NamedPattern": [("key", "Expr"), ("patt", "Patt"),
                             ("default", "Expr")],
        },
        "Matcher": {
            "MatcherExpr": [("patt", "Patt"), ("body", "Expr")],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("verb", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr")],
        },
    }
)

class PrettyMAST(MastIR.makePassTo(None)):

    def __init__(self):
        self.buf = []

    def asUnicode(self):
        return u"".join(self.buf)

    def write(self, s):
        self.buf.append(s)

    def visitNullExpr(self):
        self.write(u"null")

    def visitCharExpr(self, c):
        self.write(quoteChar(c[0]))

    def visitDoubleExpr(self, d):
        self.write(u"%f" % d)

    def visitIntExpr(self, i):
        self.write(i.format(BASE10).decode("utf-8"))

    def visitStrExpr(self, s):
        self.write(quoteStr(s))

    def visitAssignExpr(self, name, rvalue):
        self.write(name)
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitBindingExpr(self, name):
        self.write(u"&&")
        self.write(name)

    def visitCallExpr(self, obj, verb, args, namedArgs):
        self.visitExpr(obj)
        self.write(u".")
        self.write(verb)
        self.write(u"(")
        if args:
            self.visitExpr(args[0])
            for arg in args[1:]:
                self.write(u", ")
                self.visitExpr(arg)
        if namedArgs:
            self.visitNamedArg(args[0])
            for namedArg in namedArgs[1:]:
                self.write(u", ")
                self.visitNamedArg(namedArg)
        self.write(u")")

    def visitDefExpr(self, patt, ex, rvalue):
        if isinstance(patt, MastIR.VarPatt):
            self.write(u"def ")
        self.visitPatt(patt)
        if not isinstance(ex, MastIR.NullExpr):
            self.write(u" exit ")
            self.visitExpr(ex)
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitEscapeOnlyExpr(self, patt, body):
        self.write(u"escape ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody):
        self.write(u"escape ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"} catch ")
        self.visitPatt(catchPatt)
        self.write(u" {")
        self.visitExpr(catchBody)
        self.write(u"}")

    def visitFinallyExpr(self, body, atLast):
        self.write(u"try {")
        self.visitExpr(body)
        self.write(u"} finally {")
        self.visitExpr(atLast)
        self.write(u"}")

    def visitHideExpr(self, body):
        self.write(u"{")
        self.visitExpr(body)
        self.write(u"}")

    def visitIfExpr(self, test, cons, alt):
        self.write(u"if (")
        self.visitExpr(test)
        self.write(u") {")
        self.visitExpr(cons)
        self.write(u"} else {")
        self.visitExpr(alt)
        self.write(u"}")

    def visitMetaContextExpr(self):
        self.write(u"meta.context()")

    def visitMetaStateExpr(self):
        self.write(u"meta.state()")

    def visitNounExpr(self, name):
        self.write(name)

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers):
        self.write(u"object ")
        self.visitPatt(patt)
        if auditors:
            self.write(u" as ")
            self.visitExpr(auditors[0])
            auditors = auditors[1:]
            if auditors:
                self.write(u" implements ")
                self.visitExpr(auditors[0])
                for auditor in auditors[1:]:
                    self.write(u", ")
                    self.visitExpr(auditor)
        self.write(u" {")
        for method in methods:
            self.visitMethod(method)
        for matcher in matchers:
            self.visitMatcher(matcher)
        self.write(u"}")

    def visitSeqExpr(self, exprs):
        if exprs:
            self.visitExpr(exprs[0])
            for expr in exprs[1:]:
                self.write(u"; ")
                self.visitExpr(expr)

    def visitTryExpr(self, body, catchPatt, catchBody):
        self.write(u"try {")
        self.visitExpr(body)
        self.write(u"} catch ")
        self.visitPatt(catchPatt)
        self.write(u" {")
        self.visitExpr(catchBody)
        self.write(u"}")

    def visitIgnorePatt(self, guard):
        self.write(u"_")
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitBindingPatt(self, name):
        self.write(u"&&")
        self.write(name)

    def visitFinalPatt(self, name, guard):
        self.write(name)
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitVarPatt(self, name, guard):
        self.write(u"var ")
        self.write(name)
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitListPatt(self, patts):
        self.write(u"[")
        if patts:
            self.visitPatt(patts[0])
            for patt in patts[1:]:
                self.write(u", ")
                self.visitPatt(patt)
        self.write(u"]")

    def visitViaPatt(self, trans, patt):
        self.write(u"via (")
        self.visitExpr(trans)
        self.write(u") ")
        self.visitPatt(patt)

    def visitNamedArgExpr(self, key, value):
        self.visitExpr(key)
        self.write(u" => ")
        self.visitExpr(value)

    def visitNamedPattern(self, key, patt, default):
        self.visitExpr(key)
        self.write(u" => ")
        self.visitPatt(patt)
        self.write(u" := ")
        self.visitExpr(default)

    def visitMatcherExpr(self, patt, body):
        self.write(u"match ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body):
        self.write(u"method ")
        self.write(verb)
        self.write(u"(")
        if patts:
            self.visitPatt(patts[0])
            for patt in patts[1:]:
                self.write(u", ")
                self.visitPatt(patt)
        if patts and namedPatts:
            self.write(u", ")
        if namedPatts:
            self.visitNamedPatt(namedPatts[0])
            for namedPatt in namedPatts[1:]:
                self.write(u", ")
                self.visitNamedPatt(namedPatt)
        self.write(u")")
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")
