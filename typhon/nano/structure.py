# -*- coding: utf-8 -*-

"""
Structural refactoring to improve the efficiency of the AST interpreter.
"""

from rpython.rlib.rbigint import BASE10

from typhon.atoms import getAtom
from typhon.nano.scopes import BoundNounsIR
from typhon.quoting import quoteChar, quoteStr

def refactorStructure(ast):
    ast = RemoveDefIgnore().visitExpr(ast)
    ast = SplitScript().visitExpr(ast)
    ast = MakeAtoms().visitExpr(ast)
    return ast

class RemoveDefIgnore(BoundNounsIR.selfPass()):
    """
    match m`def _ :@guard exit @ex := @rvalue`:
        if (guard == NullExpr):
            rvalue
        else:
            m`$guard.coerce($rvalue, $ex)`
    """

    def visitDefExpr(self, patt, ex, rvalue, span):
        if isinstance(patt, self.src.IgnorePatt):
            guard = patt.guard
            if isinstance(guard, self.src.NullExpr):
                return rvalue
            else:
                return self.dest.CallExpr(guard, u"coerce", [rvalue, ex], [],
                                          span)
        return self.super.visitDefExpr(self, patt, ex, rvalue, span)

SplitScriptIR = BoundNounsIR.extend("SplitScript", [],
    {
        "Expr": {
            "ObjectExpr": [("patt", "Patt"), ("auditors", "Expr*"),
                           ("script", "Script")],
        },
        "Script": {
            "ScriptExpr": [("name", None), ("doc", None), ("mast", None),
                           ("layout", None), ("methods", "Method*"),
                           ("matchers", "Matcher*")],
        },
    }
)

class SplitScript(BoundNounsIR.makePassTo(SplitScriptIR)):

    def nameForPatt(self, patt):
        if isinstance(patt, self.dest.IgnorePatt):
            return u"_"
        else:
            return patt.name

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers,
                        mast, layout, span):
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        methods = [self.visitMethod(method) for method in methods]
        matchers = [self.visitMatcher(matcher) for matcher in matchers]
        name = self.nameForPatt(patt)
        script = self.dest.ScriptExpr(name, doc, mast, layout, methods,
                                      matchers, span)
        return self.dest.ObjectExpr(patt, auditors, script, span)

AtomIR = SplitScriptIR.extend("Atom", [],
    {
        "Expr": {
            "CallExpr": [("obj", "Expr"), ("atom", None), ("args", "Expr*"),
                         ("namedArgs", "NamedArg*")],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("atom", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("localSize", None)],
        },
    }
)

class MakeAtoms(SplitScriptIR.makePassTo(AtomIR)):

    def visitCallExpr(self, obj, verb, args, namedArgs, span):
        obj = self.visitExpr(obj)
        atom = getAtom(verb, len(args))
        args = [self.visitExpr(arg) for arg in args]
        namedArgs = [self.visitNamedArg(namedArg) for namedArg in namedArgs]
        return self.dest.CallExpr(obj, atom, args, namedArgs, span)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        localSize, span):
        atom = getAtom(verb, len(patts))
        patts = [self.visitPatt(patt) for patt in patts]
        namedPatts = [self.visitNamedPatt(namedPatt) for namedPatt in
                namedPatts]
        guard = self.visitExpr(guard)
        body = self.visitExpr(body)
        return self.dest.MethodExpr(doc, atom, patts, namedPatts, guard, body,
                                    localSize, span)


# Pretty-printer for the final pass.

def prettifyStructure(ast):
    p = PrettySpecialNouns()
    p.visitExpr(ast)
    return p.asUnicode()

def asIndex(i):
    """
    Convert numbers to base-10 pretty subscript indices.
    """
    return u"".join([unichr(0x2050 + ord(c)) for c in str(i)])

class BraceContext(object):

    def __init__(self, printer):
        self.printer = printer

    def __enter__(self):
        self.printer.indentLevel += 1
        self.printer.writeLine(u" {")

    def __exit__(self, *args):
        self.printer.indentLevel -= 1
        self.printer.line()
        self.printer.write(u"}")

class PrettySpecialNouns(AtomIR.makePassTo(None)):

    indentLevel = 0

    def __init__(self):
        self.buf = []

    def asUnicode(self):
        return u"".join(self.buf).strip(u' ')

    def write(self, s):
        self.buf.append(s)

    def line(self):
        self.buf.append(u"\n")
        self.buf.append(u"    " * self.indentLevel)

    def writeLine(self, s):
        self.write(s)
        self.line()

    def braces(self):
        return BraceContext(self)

    def visitNullExpr(self, span):
        self.write(u"null")

    def visitCharExpr(self, c, span):
        self.write(quoteChar(c[0]))

    def visitDoubleExpr(self, d, span):
        self.write(u"%f" % d)

    def visitIntExpr(self, i, span):
        self.write(i.format(BASE10).decode("utf-8"))

    def visitStrExpr(self, s, span):
        self.write(quoteStr(s))

    def visitCallExpr(self, obj, atom, args, namedArgs, span):
        self.visitExpr(obj)
        self.write(u".")
        self.write(atom.verb)
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

    def visitDefExpr(self, patt, ex, rvalue, span):
        if not (isinstance(patt, self.src.VarSlotPatt) or
                isinstance(patt, self.src.VarBindingPatt)):
            self.write(u"def ")
        self.visitPatt(patt)
        if not isinstance(ex, self.src.NullExpr):
            self.write(u" exit ")
            self.visitExpr(ex)
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitEscapeOnlyExpr(self, patt, body, span):
        self.write(u"escape ")
        self.visitPatt(patt)
        with self.braces():
            self.visitExpr(body)

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody, span):
        self.write(u"escape ")
        self.visitPatt(patt)
        with self.braces():
            self.visitExpr(body)
        self.write(u" catch ")
        self.visitPatt(catchPatt)
        with self.braces():
            self.visitExpr(catchBody)

    def visitFinallyExpr(self, body, atLast, span):
        self.write(u"try")
        with self.braces():
            self.visitExpr(body)
        self.write(u" finally")
        with self.braces():
            self.visitExpr(atLast)

    def visitIfExpr(self, test, cons, alt, span):
        self.write(u"if (")
        self.visitExpr(test)
        self.write(u")")
        with self.braces():
            self.visitExpr(cons)
        self.write(u" else")
        with self.braces():
            self.visitExpr(alt)

    def visitLocalExpr(self, name, index, span):
        self.write(name)
        self.write(u"⒧")
        self.write(asIndex(index))

    def visitFrameExpr(self, name, index, span):
        self.write(name)
        self.write(u"⒡")
        self.write(asIndex(index))

    def visitOuterExpr(self, name, index, span):
        self.write(name)
        self.write(asIndex(index))

    def visitClearObjectExpr(self, patt, script, span):
        self.write(u"object ")
        self.visitPatt(patt)
        with self.braces():
            self.visitScript(script)

    def visitObjectExpr(self, patt, auditors, script, span):
        self.write(u"object ")
        self.visitPatt(patt)
        if not auditors:
            self.errorWithSpan(u"Object is not clear but has no auditors",
                               None)
        if auditors and not isinstance(auditors[0], self.src.NullExpr):
            self.write(u" as ")
            self.visitExpr(auditors[0])
            auditors = auditors[1:]
            if auditors:
                self.write(u" implements ")
                self.visitExpr(auditors[0])
                for auditor in auditors[1:]:
                    self.write(u", ")
                    self.visitExpr(auditor)
        with self.braces():
            self.visitScript(script)

    def visitSeqExpr(self, exprs, span):
        if exprs:
            self.visitExpr(exprs[0])
            for expr in exprs[1:]:
                self.writeLine(u";")
                self.visitExpr(expr)

    def visitTryExpr(self, body, catchPatt, catchBody, span):
        self.write(u"try")
        with self.braces():
            self.visitExpr(body)
        self.write(u" catch ")
        self.visitPatt(catchPatt)
        with self.braces():
            self.visitExpr(catchBody)

    def visitIgnorePatt(self, guard, span):
        self.write(u"_")
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitBindingPatt(self, name, idx, span):
        self.write(u"&&")
        self.write(name)
        self.write(asIndex(idx))

    def visitNounPatt(self, name, guard, idx, span):
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitFinalSlotPatt(self, name, guard, idx, span):
        self.write(u"(&)")
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitVarSlotPatt(self, name, guard, idx, span):
        self.write(u"var (&)")
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitFinalBindingPatt(self, name, guard, idx, span):
        self.write(u"(&&)")
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitVarBindingPatt(self, name, guard, idx, span):
        self.write(u"var (&&)")
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitListPatt(self, patts, span):
        self.write(u"[")
        if patts:
            self.visitPatt(patts[0])
            for patt in patts[1:]:
                self.write(u", ")
                self.visitPatt(patt)
        self.write(u"]")

    def visitViaPatt(self, trans, patt, span):
        self.write(u"via (")
        self.visitExpr(trans)
        self.write(u") ")
        self.visitPatt(patt)

    def visitNamedArgExpr(self, key, value, span):
        self.visitExpr(key)
        self.write(u" => ")
        self.visitExpr(value)

    def visitNamedPattern(self, key, patt, default, span):
        self.visitExpr(key)
        self.write(u" => ")
        self.visitPatt(patt)
        self.write(u" := ")
        self.visitExpr(default)

    def visitMatcherExpr(self, patt, body, layout, span):
        self.write(u"match ")
        self.visitPatt(patt)
        with self.braces():
            self.visitExpr(body)

    def visitMethodExpr(self, doc, atom, patts, namedPatts, guard, body,
                        layout, span):
        self.write(u"method ")
        self.write(atom.verb)
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
        if not isinstance(guard, self.src.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)
        with self.braces():
            self.visitExpr(body)

    def visitScriptExpr(self, name, doc, mast, layout, methods,
                        matchers, span):
        self.write(u"closure ⎣")
        self.write(u" ".join(layout.frameNames.keys()))
        self.writeLine(u"⎤;")
        # Newlines after every method/matcher, except for the final one in the
        # script. Tricky.
        if methods:
            lastMethod = methods[-1]
            for method in methods[:-1]:
                self.visitMethod(method)
                self.line()
            self.visitMethod(lastMethod)
            if matchers:
                self.line()
        if matchers:
            lastMatcher = matchers[-1]
            for matcher in matchers[:-1]:
                self.visitMatcher(matcher)
                self.line()
            self.visitMatcher(lastMatcher)
