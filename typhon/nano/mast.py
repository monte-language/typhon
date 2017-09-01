import sys
import linecache
from types import ModuleType
import py

from rpython.rlib.rbigint import BASE10, rbigint

from typhon import nodes
from typhon.atoms import getAtom
from typhon.autohelp import autoguard, autohelp, method
from typhon.errors import userError
from typhon.nanopass import makeIR
from typhon.objects.constants import NullObject
from typhon.objects.data import SourceSpan
from typhon.objects.root import Object, audited
from typhon.quoting import quoteChar, quoteStr
from typhon.objects.collections.lists import ConstList

GETSTARTLINE_0 = getAtom(u"getStartLine", 0)

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
    },
)

class SanityCheck(MastIR.selfPass()):

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, span):
        if isinstance(patt, self.src.ViaPatt):
            self.errorWithSpan(u"via-patts not yet permitted in object-exprs",
                               patt.span)
        return self.super.visitObjectExpr(self, doc, patt, auditors,
                                          methods, matchers, span)


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

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, span):
        mast = MastIR.ObjectExpr(doc, patt, auditors, methods, matchers, span)
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        methods = [self.visitMethod(method) for method in methods]
        matchers = [self.visitMatcher(matcher) for matcher in matchers]
        return self.dest.ObjectExpr(doc, patt, auditors, methods, matchers,
                                    mast, span)


class PrettyMAST(MastIR.makePassTo(None)):

    def __init__(self):
        self.buf = []

    def asUnicode(self):
        return u"".join(self.buf)

    def write(self, s):
        self.buf.append(s)

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

    def visitAssignExpr(self, name, rvalue, span):
        self.write(name)
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitBindingExpr(self, name, span):
        self.write(u"&&")
        self.write(name)

    def visitCallExpr(self, obj, verb, args, namedArgs, span):
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

    def visitDefExpr(self, patt, ex, rvalue, span):
        if isinstance(patt, MastIR.VarPatt):
            self.write(u"def ")
        self.visitPatt(patt)
        if not isinstance(ex, MastIR.NullExpr):
            self.write(u" exit ")
            self.visitExpr(ex)
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitEscapeOnlyExpr(self, patt, body, span):
        self.write(u"escape ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody, span):
        self.write(u"escape ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"} catch ")
        self.visitPatt(catchPatt)
        self.write(u" {")
        self.visitExpr(catchBody)
        self.write(u"}")

    def visitFinallyExpr(self, body, atLast, span):
        self.write(u"try {")
        self.visitExpr(body)
        self.write(u"} finally {")
        self.visitExpr(atLast)
        self.write(u"}")

    def visitHideExpr(self, body, span):
        self.write(u"{")
        self.visitExpr(body)
        self.write(u"}")

    def visitIfExpr(self, test, cons, alt, span):
        self.write(u"if (")
        self.visitExpr(test)
        self.write(u") {")
        self.visitExpr(cons)
        self.write(u"} else {")
        self.visitExpr(alt)
        self.write(u"}")

    def visitMetaContextExpr(self, span):
        self.write(u"meta.context()")

    def visitMetaStateExpr(self, span):
        self.write(u"meta.state()")

    def visitNounExpr(self, name, span):
        self.write(name)

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, span):
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

    def visitSeqExpr(self, exprs, span):
        if exprs:
            self.visitExpr(exprs[0])
            for expr in exprs[1:]:
                self.write(u"; ")
                self.visitExpr(expr)

    def visitTryExpr(self, body, catchPatt, catchBody, span):
        self.write(u"try {")
        self.visitExpr(body)
        self.write(u"} catch ")
        self.visitPatt(catchPatt)
        self.write(u" {")
        self.visitExpr(catchBody)
        self.write(u"}")

    def visitIgnorePatt(self, guard, span):
        self.write(u"_")
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitBindingPatt(self, name, span):
        self.write(u"&&")
        self.write(name)

    def visitFinalPatt(self, name, guard, span):
        self.write(name)
        if not isinstance(guard, MastIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitVarPatt(self, name, guard, span):
        self.write(u"var ")
        self.write(name)
        if not isinstance(guard, MastIR.NullExpr):
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

    def visitMatcherExpr(self, patt, body, span):
        self.write(u"match ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body, span):
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
    def visitNullExpr(self, span):
        return nodes.Null

    def visitCharExpr(self, c, span):
        return nodes.Char(c)

    def visitDoubleExpr(self, d, span):
        return nodes.Double(d)

    def visitIntExpr(self, i, span):
        return nodes.Int(i)

    def visitStrExpr(self, s, span):
        return nodes.Str(s)

    def visitAssignExpr(self, name, rvalue, span):
        return nodes.Assign(name, self.visitExpr(rvalue))

    def visitBindingExpr(self, name, span):
        return nodes.Binding(name)

    def visitCallExpr(self, obj, verb, args, namedArgs, span):
        return nodes.Call(self.visitExpr(obj), verb,
                          [self.visitExpr(a) for a in args],
                          [self.visitNamedArg(na) for na in namedArgs])

    def visitDefExpr(self, patt, ex, rvalue, span):
        return nodes.Def(self.visitPatt(patt), self.visitExpr(ex),
                         self.visitExpr(rvalue))

    def visitEscapeOnlyExpr(self, patt, body, span):
        return nodes.Escape(self.visitPatt(patt), self.visitExpr(body),
                            None, None)

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody, span):
        return nodes.Escape(self.visitPatt(patt), self.visitExpr(body),
                            self.visitPatt(catchPatt),
                            self.visitExpr(catchBody))

    def visitFinallyExpr(self, body, atLast, span):
        return nodes.Finally(self.visitExpr(body), self.visitExpr(atLast))

    def visitHideExpr(self, body, span):
        return nodes.Hide(self.visitExpr(body))

    def visitIfExpr(self, test, cons, alt, span):
        return nodes.If(self.visitExpr(test), self.visitExpr(cons),
                        self.visitExpr(alt))

    def visitMetaContextExpr(self, span):
        return nodes.MetaContextExpr()

    def visitMetaStateExpr(self, span):
        return nodes.MetaStateExpr()

    def visitNounExpr(self, name, span):
        return nodes.Noun(name)

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, span):
        return nodes.Obj(doc, self.visitPatt(patt),
                         self.visitExpr(auditors[0]),
                         [self.visitExpr(a) for a in auditors[1:]],
                         nodes.Script(
                             None,
                             [self.visitMethod(m) for m in methods],
                             [self.visitMatcher(m) for m in matchers]))

    def visitSeqExpr(self, exprs, span):
        return nodes.Sequence([self.visitExpr(e) for e in exprs])

    def visitTryExpr(self, body, catchPatt, catchBody, span):
        return nodes.Try(self.visitExpr(body), self.visitPatt(catchPatt),
                         self.visitExpr(catchBody))

    def visitIgnorePatt(self, guard, span):
        return nodes.IgnorePattern(self.visitExpr(guard))

    def visitBindingPatt(self, name, span):
        return nodes.BindingPattern(nodes.Noun(name))

    def visitFinalPatt(self, name, guard, span):
        return nodes.FinalPattern(nodes.Noun(name),
                                  self.visitExpr(guard))

    def visitVarPatt(self, name, guard, span):
        return nodes.VarPattern(nodes.Noun(name), self.visitExpr(guard))

    def visitListPatt(self, patts, span):
        return nodes.ListPattern([self.visitPatt(p) for p in patts], nodes._Null)

    def visitViaPatt(self, trans, patt, span):
        return nodes.ViaPattern(self.visitExpr(trans), self.visitPatt(patt))

    def visitNamedArgExpr(self, key, value, span):
        return nodes.NamedArg(self.visitExpr(key), self.visitExpr(value))

    def visitNamedPattern(self, key, patt, default, span):
        return nodes.NamedParam(self.visitExpr(key), self.visitPatt(patt),
                                self.visitExpr(default))

    def visitMatcherExpr(self, patt, body, span):
        return nodes.Matcher(self.visitPatt(patt),
                             self.visitExpr(body))

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body, span):
        return nodes.Method(doc, verb, [self.visitPatt(p) for p in patts],
                            [self.visitNamedPatt(p) for p in namedPatts],
                            self.visitExpr(guard), self.visitExpr(body))

class GeneratedCodeLoader(object):
    """
    Object for use as a module's __loader__, to display generated
    source.
    """
    def __init__(self, source):
        self.source = source
    def get_source(self, name):
        return self.source


def wrapperCls(name, superName, paramInfo):
    accessors = []
  #   if paramInfo:
  #       for pname, typ in paramInfo:
  #           g = paramGuards.get(name, {}).get(pname, "Any")
  #           accessors.append("""
  # @method("%s")
  # def get%s(self):
  #  return self._ast.%s
  #           """ % (g, pname.title(), pname))
    return """
 @autohelp
 class %s(%s):
  __module__ = 'typhon.nano.mast_generatedwrapper'
  def __init__(self, ast):
   assert isinstance(ast, MastIR.%s)
   self._ast = ast
%s
""" % (name, superName, name, '\n'.join(accessors))

def paramCheck(pname, typ, name):
    if typ is None or typ in MastIR.terminals:

        ptype = paramGuards.get(name, {}).get(pname, None)
        if ptype == "Int":
            return "\n  %s_0 = rbigint.fromint(%s)\n" % (pname, pname)
        else:
            return "\n  %s_0 = %s\n" % (pname, pname)
    elif typ[-1] == '*':
        typ = typ[:-1]
        return """
  if not isinstance (%s, ConstList):
   raise userError(u'Expected "%s" to be a list of %s')
  for item in %s.objs:
   if not (isinstance(item, ASTWrapper.%s) or item is NullObject):
    raise userError(u'Expected "%s" a list of %s')
  %s_0 = [MastIR.NullExpr(None) if it is NullObject else it._ast for it in %s.objs]
""" % (pname, pname, typ, pname, typ, pname, typ, pname, pname)
    else:
        return """
  if %s is NullObject:
   %s_0 = MastIR.NullExpr(None)
  else:
   if not isinstance(%s, ASTWrapper.%s):
    raise userError(u'Expected \"%s\" to be %s')
   %s_0 = %s._ast
""" % (pname, pname, pname, typ, pname, typ, pname, pname)

paramGuards = {
    'CharExpr': {'c': 'Char'},
    'DoubleExpr': {'d': 'Double'},
    'IntExpr': {'i': 'Int'},
    'StrExpr': {'s': 'Str'},
    'CallExpr': {'verb': 'Str'},
    'ObjectExpr': {'doc': 'Str'},
    'MethodExpr': {'doc': 'Str', 'verb': 'Str'},
    'Noun': 'Str',
}

def guardNames(name, paramInfo):
    names = ["Any"]
    for pname, typ in paramInfo:
        if typ is None:
            names.append(paramGuards[name][pname])
        elif typ in MastIR.terminals:
            names.append(paramGuards[typ])
        else:
            names.append("Any")

    names.append("Any")
    return names
def checkSpan():
    return """
  if span is NullObject:
   span_0 = None
  elif isinstance(span, SourceSpan):
   span_0 = span.toSpan()
  else:
   raise userError(u'Expected "span" to be a SourceSpan')
"""

def makeMastBuilder():
    "NOT_RPYTHON"
    import itertools
    methods = []
    wrapperClasses = []
    for groupName, group in MastIR.nonterms.items():
        wrapperClasses.append(wrapperCls(groupName, "Object", None))
        for name, paramInfo in group.items():
            wrapperClasses.append(wrapperCls(name, groupName, paramInfo))
            params = [n[0] for n in paramInfo] + ['span']
            checks = [paramCheck(pname, typ, name)
                      for pname, typ in paramInfo]
            checks.append(checkSpan())
            ps = [p + "_0" for p in params]
            wrapper = "ASTWrapper.%s(MastIR.%s(%s))" % (name, name, ', '.join(ps))
            methods.append("\n @method(%s)\n def %s(%s):%s\n  return %s" % (
                ', '.join(['"%s"' % g for g in guardNames(name, paramInfo)]),
                name, ', '.join(['self'] + params), ''.join(checks), wrapper))
    src = """
class ASTWrapper(object):
 __module__ = 'typhon.nano.mast_generatedwrapper'
%s
@autohelp
@audited.DF
class ASTBuilder(Object):
 __module__ = 'typhon.nano.mast_generatedwrapper'
 _immutable=True
%s
""" % (''.join(wrapperClasses),''.join(methods))
    d = {'ConstList': ConstList, 'userError': userError, 'Object': Object, 'audited': audited, 'method': method, 'autohelp': autohelp, 'SourceSpan': SourceSpan, 'rbigint': rbigint, 'NullObject': NullObject, 'MastIR': MastIR}
    modname = "typhon.nano.mast_generatedwrapper"
    fname = "typhon/nano/mast_generatedwrapper.py"
    open(fname, 'w').write(src)
    mod = ModuleType(modname)
    mod.__loader__ = GeneratedCodeLoader(src)
    mod.__dict__ .update(d)
    mod.__file__ = fname
    sys.modules[modname] = mod
    exec py.code.Source(src).compile(fname) in mod.__dict__
    linecache.getlines(fname, mod.__dict__)
    return mod.ASTBuilder, mod.ASTWrapper


ASTBuilder, ASTWrapper = makeMastBuilder()
theASTBuilder = ASTBuilder()
