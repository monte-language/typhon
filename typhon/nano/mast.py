from rpython.rlib.rbigint import BASE10

from typhon import nodes
from typhon.nanopass import makeIR
from typhon.quoting import quoteChar, quoteStr

def saveScripts(ast):
    ast = SanityCheck().visitExpr(ast)
    ast = SaveScripts().visitExpr(ast)
    return ast

MastIR = makeIR("Mast",
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
            "ViaPatt": [("trans", "Expr"), ("patt", "Patt"), ("span", None)],
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

class SanityCheck(MastIR.selfPass()):

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers):
        if isinstance(patt, self.src.ViaPatt):
            self.errorWithSpan("via-patts not yet permitted in object-exprs",
                               patt.span)
        return self.super.visitObjectExpr(self, doc, patt, auditors,
                methods, matchers)


SaveScriptIR = MastIR.extend("SaveScript", [],
    {
        "Expr": {
            "ObjectExpr": [("doc", None), ("patt", "Patt"),
                           ("auditors", "Expr*"), ("methods", "Method*"),
                           ("matchers", "Matcher*"), ("mast", None)],
        },
    }
)

class SaveScripts(MastIR.makePassTo(SaveScriptIR)):

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers):
        mast = MastIR.ObjectExpr(doc, patt, auditors, methods, matchers)
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        methods = [self.visitMethod(method) for method in methods]
        matchers = [self.visitMatcher(matcher) for matcher in matchers]
        return self.dest.ObjectExpr(doc, patt, auditors, methods, matchers,
                                    mast)


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
            self.visitNamedArg(namedArgs[0])
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


class BuildKernelNodes(MastIR.makePassTo(None)):
    def visitNullExpr(self):
        return nodes.Null

    def visitCharExpr(self, c):
        return nodes.Char(c)

    def visitDoubleExpr(self, d):
        return nodes.Double(d)

    def visitIntExpr(self, i):
        return nodes.Int(i)

    def visitStrExpr(self, s):
        return nodes.Str(s)

    def visitAssignExpr(self, name, rvalue):
        return nodes.Assign(name, self.visitExpr(rvalue))

    def visitBindingExpr(self, name):
        return nodes.Binding(name)

    def visitCallExpr(self, obj, verb, args, namedArgs):
        return nodes.Call(self.visitExpr(obj), verb,
                          [self.visitExpr(a) for a in args],
                          [self.visitNamedArg(na) for na in namedArgs])

    def visitDefExpr(self, patt, ex, rvalue):
        return nodes.Def(self.visitPatt(patt), self.visitExpr(ex),
                         self.visitExpr(rvalue))

    def visitEscapeOnlyExpr(self, patt, body):
        return nodes.Escape(self.visitPatt(patt), self.visitExpr(body),
                            None, None)

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody):
        return nodes.Escape(self.visitPatt(patt), self.visitExpr(body),
                            self.visitPatt(catchPatt),
                            self.visitExpr(catchBody))

    def visitFinallyExpr(self, body, atLast):
        return nodes.Finally(self.visitExpr(body), self.visitExpr(atLast))

    def visitHideExpr(self, body):
        return nodes.Hide(self.visitExpr(body))

    def visitIfExpr(self, test, cons, alt):
        return nodes.If(self.visitExpr(test), self.visitExpr(cons),
                        self.visitExpr(alt))

    def visitMetaContextExpr(self):
        return nodes.MetaContextExpr()

    def visitMetaStateExpr(self):
        return nodes.MetaStateExpr()

    def visitNounExpr(self, name):
        return nodes.Noun(name)

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers):
        return nodes.Obj(doc, self.visitPatt(patt),
                         self.visitExpr(auditors[0]),
                         [self.visitExpr(a) for a in auditors[1:]],
                         nodes.Script(
                             None,
                             [self.visitMethod(m) for m in methods],
                             [self.visitMatcher(m) for m in matchers]))

    def visitSeqExpr(self, exprs):
        return nodes.Sequence([self.visitExpr(e) for e in exprs])

    def visitTryExpr(self, body, catchPatt, catchBody):
        return nodes.Try(self.visitExpr(body), self.visitPatt(catchPatt),
                         self.visitExpr(catchBody))

    def visitIgnorePatt(self, guard):
        return nodes.IgnorePattern(self.visitExpr(guard))

    def visitBindingPatt(self, name):
        return nodes.BindingPattern(nodes.Noun(name))

    def visitFinalPatt(self, name, guard):
        return nodes.FinalPattern(nodes.Noun(name),
                                  self.visitExpr(guard))

    def visitVarPatt(self, name, guard):
        return nodes.VarPattern(nodes.Noun(name), self.visitExpr(guard))

    def visitListPatt(self, patts):
        return nodes.ListPattern([self.visitPatt(p) for p in patts], nodes._Null)

    def visitViaPatt(self, trans, patt, span):
        return nodes.ViaPattern(self.visitExpr(trans), self.visitPatt(patt))

    def visitNamedArgExpr(self, key, value):
        return nodes.NamedArg(self.visitExpr(key), self.visitExpr(value))

    def visitNamedPattern(self, key, patt, default):
        return nodes.NamedParam(self.visitExpr(key), self.visitPatt(patt),
                                self.visitExpr(default))

    def visitMatcherExpr(self, patt, body):
        return nodes.Matcher(self.visitPatt(patt),
                             self.visitExpr(body))

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body):
        return nodes.Method(doc, verb, [self.visitPatt(p) for p in patts],
                            [self.visitNamedPatt(p) for p in namedPatts],
                            self.visitExpr(guard), self.visitExpr(body))
