# -*- coding: utf-8 -*-
from rpython.rlib.rbigint import BASE10
from typhon.errors import userError
from typhon.nano.mast import MastIR, SaveScriptIR
from typhon.quoting import quoteChar, quoteStr

"""
Static scope analysis, in several passes:
 * Noun specialization
 * De Bruijn indices
 * Escape analysis
 * Slot specialization
 * Deslotification
"""

LayoutIR = SaveScriptIR.extend(
    "Layout", [],
    {
        "Expr": {
            "BindingExpr": [("name", "Noun"), ("layout", None)],
            "NounExpr": [("name", "Noun"), ("layout", None)],
            "AssignExpr": [("name", "Noun"), ("value", "Expr"),
                           ("layout", None)],
            "MetaContextExpr": [("layout", None)],
            "MetaStateExpr": [("layout", None)],
            "ObjectExpr": [("doc", None), ("patt", "Patt"),
                           ("auditors", "Expr*"), ("methods", "Method*"),
                           ("matchers", "Matcher*"), ("mast", None),
                           ("layout", None)],
            "-HideExpr": None,
        },
        "Patt": {
            "BindingPatt": [("name", "Noun"), ("layout", None)],
            "FinalPatt": [("name", "Noun"), ("guard", "Expr"),
                          ("layout", None)],
            "VarPatt": [("name", "Noun"), ("guard", "Expr"), ("layout", None)],
        },
        "Matcher": {
            "MatcherExpr": [("patt", "Patt"), ("body", "Expr"),
                            ("layout", None)],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("verb", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("layout", None)],
        },
    }
)


class ScopeBase(object):
    position = -1

    def __init__(self, next):
        self.next = next
        self.children = []
        self.node = None

    def addChild(self, child):
        if child is self:
            assert False, "BZZT WRONG"
        self.children.append(child)


class ScopeOuter(ScopeBase):
    def __init__(self, outers):
        self.outers = outers
        self.children = []

    def collectTopLocals(self):
        # In an interactive context, we may want to keep locals defined at the
        # top level for future use.
        topLocals = [None] * 5
        scopeitems = self.children[:]
        numLocals = 0
        for sub in scopeitems:
            if isinstance(sub, ScopeItem):
                i = sub.position
                numLocals = max(numLocals, i + 1)
                while (i + 1) > len(topLocals):
                    topLocals.extend([None] * len(topLocals))
                topLocals[i] = sub.name
                scopeitems.extend(sub.children)

        return topLocals[:numLocals]

    def requireShadowable(self, name):
        if name in self.outers:
            raise userError(u"Cannot redefine " + name)

    def find(self, name):
        if name in self.outers:
            return ("outer", self.outers.index(name), "final")
        return (None, 0, "")


class ScopeFrame(ScopeBase):
    "Scope info associated with an object closure."

    def __init__(self, next):
        # Names closed over.
        self.frameNames = {}
        # Names from outer scope used (not included in closure at runtime)
        self.outerNames = {}
        return ScopeBase.__init__(self, next)

    def requireShadowable(self, name):
        return self.next.requireShadowable(name)

    def find(self, name):
        scope, idx, severity = self.next.find(name)
        if scope == "outer":
            self.outerNames[name] = (idx, severity)
            return scope, idx, severity
        if name not in self.frameNames:
            self.frameNames[name] = (len(self.frameNames), scope, idx,
                                     severity)
        return ("frame", self.frameNames[name][0], severity)


class ScopeBox(ScopeBase):
    "Scope info associated with a scope-introducing node."

    def __init__(self, next):
        ScopeBase.__init__(self, next)
        self.position = next.position

    def requireShadowable(self, name):
        scope, idx, _ = self.find(name)
        if scope is "outer":
            self.next.requireShadowable(name)

    def find(self, name):
        return self.next.find(name)


class ScopeItem(ScopeBase):
    "A single name binding."
    def __init__(self, next, name, severity):
        self.name = name
        self.position = next.position + 1
        self.severity = severity
        return ScopeBase.__init__(self, next)

    def requireShadowable(self, name):
        if self.name == name:
            raise userError(u"Cannot redefine " + name)
        self.next.requireShadowable(name)

    def find(self, name):
        if self.name == name:
            return ("local", self.position, self.severity)
        return self.next.find(name)


class LayOutScopes(SaveScriptIR.makePassTo(LayoutIR)):
    """
    Set up scope boxes and collect variable definition sites.
    """
    def __init__(self, outers):
        self.layout = ScopeOuter(outers)

    def visitExprWithLayout(self, node, layout):
        origLayout = self.layout
        self.layout = layout
        result = self.visitExpr(node)
        layout.node = result
        self.layout = origLayout
        origLayout.addChild(layout)
        return result

    def visitExprNested(self, node):
        return self.visitExprWithLayout(node, ScopeBox(self.layout))

    def visitFinalPatt(self, name, guard):
        origLayout = self.layout
        self.layout.requireShadowable(name)
        result = self.dest.FinalPatt(name, self.visitExpr(guard), origLayout)
        self.layout = ScopeItem(self.layout, name, "final")
        self.layout.node = result
        origLayout.addChild(self.layout)
        return result

    def visitVarPatt(self, name, guard):
        origLayout = self.layout
        self.layout.requireShadowable(name)
        result = self.dest.VarPatt(name, self.visitExpr(guard), origLayout)
        self.layout = ScopeItem(self.layout, name, "var")
        self.layout.node = result
        origLayout.addChild(self.layout)
        return result

    def visitBindingPatt(self, name):
        origLayout = self.layout
        self.layout.requireShadowable(name)
        result = self.dest.BindingPatt(name, origLayout)
        self.layout = ScopeItem(self.layout, name, "binding")
        self.layout.node = result
        origLayout.addChild(self.layout)
        return result

    def visitHideExpr(self, body):
        return self.visitExprNested(body)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body):
        origLayout = self.layout
        self.layout = ScopeBox(self.layout)
        result = self.dest.MethodExpr(
            doc, verb,
            [self.visitPatt(p) for p in patts],
            [self.visitNamedPatt(np) for np in namedPatts],
            self.visitExpr(guard), self.visitExpr(body), origLayout)
        self.layout.node = result
        origLayout.addChild(self.layout)
        self.layout = origLayout
        return result

    def visitMatcherExpr(self, patt, body):
        origLayout = self.layout
        self.layout = ScopeBox(self.layout)
        result = self.dest.MatcherExpr(self.visitPatt(patt),
                                       self.visitExpr(body), origLayout)
        self.layout.node = result
        origLayout.addChild(self.layout)
        self.layout = origLayout
        return result

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast):
        p = self.visitPatt(patt)
        origLayout = self.layout
        # Names defined in auditors exprs are visible inside the object but not
        # outside it, but aren't necessarily part of the frame.
        outerBox = ScopeBox(origLayout)
        origLayout.addChild(outerBox)
        auds = [self.visitExpr(a) for a in auditors]
        self.layout = ScopeFrame(outerBox)
        outerBox.addChild(self.layout)
        result = self.dest.ObjectExpr(
            doc, p, auds,
            [self.visitMethod(m) for m in methods],
            [self.visitMatcher(m) for m in matchers],
            mast,
            # Everything else captures the layout previous to its node, but
            # here we store the ScopeFrame itself (since there's no other
            # good place to put it).
            self.layout)
        self.layout.node = result
        self.layout = origLayout
        return result

    def visitMetaContextExpr(self):
        return self.dest.MetaContextExpr(self.layout)

    def visitMetaStateExpr(self):
        return self.dest.MetaStateExpr(self.layout)

    def visitNounExpr(self, name):
        return self.dest.NounExpr(name, self.layout)

    def visitBindingExpr(self, name):
        return self.dest.BindingExpr(name, self.layout)

    def visitAssignExpr(self, name, value):
        return self.dest.AssignExpr(name, self.visitExpr(value), self.layout)

    def visitEscapeOnlyExpr(self, patt, body):
        origLayout = self.layout
        self.layout = ScopeBox(origLayout)
        p = self.visitPatt(patt)
        b = self.visitExpr(body)
        result = self.dest.EscapeOnlyExpr(p, b)
        self.layout.node = result
        origLayout.addChild(self.layout)
        self.layout = origLayout
        return result

    def visitEscapeExpr(self, ejPatt, ejBody, catchPatt, catchBody):
        origLayout = self.layout
        self.layout = layout1 = ScopeBox(origLayout)
        p = self.visitPatt(ejPatt)
        b = self.visitExpr(ejBody)
        self.layout = layout2 = ScopeBox(origLayout)
        cp = self.visitPatt(catchPatt)
        cb = self.visitExpr(catchBody)
        result = self.dest.EscapeExpr(p, b, cp, cb)
        layout1.node = result
        layout2.node = result
        origLayout.addChild(layout1)
        origLayout.addChild(layout2)
        self.layout = origLayout
        return result

    def visitFinallyExpr(self, body, atLast):
        return self.dest.FinallyExpr(
            self.visitExprNested(body),
            self.visitExprNested(atLast))

    def visitIfExpr(self, test, consq, alt):
        origLayout = self.layout
        self.layout = layout1 = ScopeBox(origLayout)
        t = self.visitExpr(test)
        c = self.visitExpr(consq)
        self.layout = layout2 = ScopeBox(origLayout)
        e = self.visitExpr(alt)
        result = self.dest.IfExpr(t, c, e)
        layout1.node = result
        layout2.node = result
        origLayout.addChild(layout1)
        origLayout.addChild(layout2)
        self.layout = origLayout
        return result

    def visitTryExpr(self, body, catchPatt, catchBody):
        b = self.visitExprNested(body)
        origLayout = self.layout
        self.layout = ScopeBox(origLayout)
        cp = self.visitPatt(catchPatt)
        cb = self.visitExpr(catchBody)
        result = self.dest.TryExpr(b, cp, cb)
        self.layout.node = result
        origLayout.addChild(self.layout)
        self.layout = origLayout
        return result


BoundNounsIR = LayoutIR.extend(
    "BoundNouns", [], {
        "Expr": {
            "-NounExpr": None,
            "-BindingExpr": None,
            "-AssignExpr": None,
            "LocalNounExpr": [("name", "Noun"), ("index", None)],
            "FrameNounExpr": [("name", "Noun"), ("index", None)],
            "OuterNounExpr": [("name", "Noun"), ("index", None)],
            "LocalBindingExpr": [("name", "Noun"), ("index", None)],
            "FrameBindingExpr": [("name", "Noun"), ("index", None)],
            "OuterBindingExpr": [("name", "Noun"), ("index", None)],
            "LocalAssignExpr": [("name", "Noun"), ("index", None),
                                ("value", "Expr")],
            "FrameAssignExpr": [("name", "Noun"), ("index", None),
                                ("value", "Expr")],
            "OuterAssignExpr": [("name", "Noun"), ("index", None),
                                ("value", "Expr")],
        },
        "Patt": {
            "BindingPatt": [("name", "Noun"), ("index", None)],
            "FinalPatt": [("name", "Noun"), ("guard", "Expr"),
                          ("index", None)],
            "VarPatt": [("name", "Noun"), ("guard", "Expr"), ("index", None)],
        },
        "Method": {
            "MethodExpr": [("doc", None), ("verb", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("localSize", None)],
        },
    }
)

ReifyMetaIR = BoundNounsIR.extend(
    "ReifyMeta", [], {
        "Expr": {
            "-MetaContextExpr": None,
            "-MetaStateExpr": None,
        }
    }
)


class SpecializeNouns(LayoutIR.makePassTo(BoundNounsIR)):
    def visitBindingPatt(self, name, layout):
        return self.dest.BindingPatt(name, layout.position + 1)

    def visitFinalPatt(self, name, guard, layout):
        return self.dest.FinalPatt(name, self.visitExpr(guard),
                                   layout.position + 1)

    def visitVarPatt(self, name, guard, layout):
        return self.dest.VarPatt(name, self.visitExpr(guard),
                                 layout.position + 1)

    def visitAssignExpr(self, name, rvalue, layout):
        scope, idx, severity = layout.find(name)
        if severity == "final":
            raise userError(u"Cannot assign to final variable " + name)
        value = self.visitExpr(rvalue)
        if scope == "frame":
            return self.dest.FrameAssignExpr(name, idx, value)
        if scope == "outer":
            return self.dest.OuterAssignExpr(name, idx, value)
        return self.dest.LocalAssignExpr(name, idx, value)

    def visitNounExpr(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is None:
            raise userError(name + u" is not defined")
        if scope == "frame":
            return self.dest.FrameNounExpr(name, idx)
        if scope == "outer":
            return self.dest.OuterNounExpr(name, idx)
        return self.dest.LocalNounExpr(name, idx)

    def visitBindingExpr(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is None:
            raise userError(name + u" is not defined")
        if scope == "frame":
            return self.dest.FrameBindingExpr(name, idx)
        if scope == "outer":
            return self.dest.OuterBindingExpr(name, idx)
        return self.dest.LocalBindingExpr(name, idx)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        layout):
        return self.dest.MethodExpr(
            doc, verb,
            [self.visitPatt(p) for p in patts],
            [self.visitNamedPatt(np) for np in namedPatts],
            self.visitExpr(guard),
            self.visitExpr(body),
            countLocalSize(layout, 0))


def countLocalSize(lo, sizeSeen):
    sizeSeen = max(sizeSeen, lo.position)
    for x in lo.children:
        sizeSeen = max(countLocalSize(x, sizeSeen), sizeSeen)
    return sizeSeen


class ReifyMeta(BoundNounsIR.makePassTo(ReifyMetaIR)):
    def mkNoun(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope == "outer":
            return self.dest.OuterNounExpr(name, idx)
        if scope == "frame":
            return self.dest.FrameNounExpr(name, idx)
        return self.dest.LocalNounExpr(name, idx)

    def visitMetaStateExpr(self, layout):
        s = layout
        while not isinstance(s, ScopeFrame):
            if isinstance(s, ScopeOuter):
                frame = {}
                break
            s = s.next
        else:
            frame = s.frameNames
        return self.dest.CallExpr(
            self.mkNoun(u"_makeMap", layout),
            u"fromPairs", [
                self.dest.CallExpr(
                self.mkNoun(u"_makeList", layout),
                    u"run", [self.dest.CallExpr(
                        self.mkNoun(u"_makeList", layout),
                        u"run", [self.dest.StrExpr(u"&&" + name),
                                 self.dest.FrameBindingExpr(name, frame[name][0])],
                        [])], [])
                for name in frame.keys()], [])

    def visitMetaContextExpr(self, layout):
        fqnPrefix = u"<LOL>"
        frame = ScopeFrame(layout)
        return self.dest.ObjectExpr(u"",
            self.dest.IgnorePatt(self.dest.NullExpr()),
             [], [self.dest.MethodExpr(
                u"", u"getFQNPrefix", [], [], self.dest.NullExpr(),
                 self.dest.StrExpr(fqnPrefix), 0)],
            [], None, frame)


def asIndex(i):
    return u"".join([unichr(0x2050 + ord(c)) for c in str(i)])


class PrettySpecialNouns(ReifyMetaIR.makePassTo(None)):

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

    def visitFrameAssignExpr(self, name, idx, rvalue):
        self.write(name)
        self.write(u"⒡")
        self.write(asIndex(idx))
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitLocalAssignExpr(self, name, idx, rvalue):
        self.write(name)
        self.write(u"⒧")
        self.write(asIndex(idx))
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitOuterAssignExpr(self, name, idx, rvalue):
        self.write(name)
        self.write(asIndex(idx))
        self.write(u" := ")
        self.visitExpr(rvalue)

    def visitLocalBindingExpr(self, name, index):
        self.write(u"&&")
        self.write(name)
        self.write(u"⒧")
        self.write(asIndex(index))

    def visitFrameBindingExpr(self, name, index):
        self.write(u"&&")
        self.write(name)
        self.write(u"⒡")
        self.write(asIndex(index))

    def visitOuterBindingExpr(self, name, index):
        self.write(u"&&")
        self.write(name)
        self.write(asIndex(index))

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
        if not isinstance(patt, BoundNounsIR.VarPatt):
            self.write(u"def ")
        self.visitPatt(patt)
        if not isinstance(ex, BoundNounsIR.NullExpr):
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

    def visitIfExpr(self, test, cons, alt):
        self.write(u"if (")
        self.visitExpr(test)
        self.write(u") {")
        self.visitExpr(cons)
        self.write(u"} else {")
        self.visitExpr(alt)
        self.write(u"}")

    def visitMetaContextExpr(self, layout):
        self.write(u"meta.context()")

    def visitMetaStateExpr(self, layout):
        self.write(u"meta.state()")

    def visitLocalNounExpr(self, name, index):
        self.write(name)
        self.write(u"⒧")
        self.write(asIndex(index))

    def visitFrameNounExpr(self, name, index):
        self.write(name)
        self.write(u"⒡")
        self.write(asIndex(index))

    def visitOuterNounExpr(self, name, index):
        self.write(name)
        self.write(asIndex(index))

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast,
                        layout):
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
        self.write(u" ⎣")
        self.write(u" ".join(layout.frameNames.keys()))
        self.write(u"⎤ ")
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
        if not isinstance(guard, BoundNounsIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitBindingPatt(self, name, layout):
        self.write(u"&&")
        self.write(name)

    def visitFinalPatt(self, name, guard, idx):
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, BoundNounsIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)

    def visitVarPatt(self, name, guard, idx):
        self.write(u"var ")
        self.write(name)
        self.write(asIndex(idx))
        if not isinstance(guard, BoundNounsIR.NullExpr):
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

    def visitMatcherExpr(self, patt, body, layout):
        self.write(u"match ")
        self.visitPatt(patt)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        layout):
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
        if not isinstance(guard, BoundNounsIR.NullExpr):
            self.write(u" :")
            self.visitExpr(guard)
        self.write(u" {")
        self.visitExpr(body)
        self.write(u"}")


## We'll come back to this in a bit once we have some more scope info.
# DeBruijnIR = SaveScriptIR.extend("De Bruijn", ["Index", "-Noun"],
#     {
#         "Expr": {
#             "AssignExpr": [("index", "Index"), ("rvalue", "Expr")],
#             "BindingExpr": [("index", "Index")],
#             "NounExpr": [("index", "Index")],
#         },
#         "Patt": {
#             "BindingPatt": [("index", "Index")],
#             "FinalPatt": [("index", "Index"), ("guard", "Expr")],
#             "VarPatt": [("index", "Index"), ("guard", "Expr")],
#         },
#     }
# )

# class AssignDeBruijn(SaveScriptIR.makePassTo(DeBruijnIR)):

#     def __init__(self):
#         self.scopeStack = [[]]

#     def boundNames(self):
#         return self.scopeStack[-1]

#     def push(self):
#         self.scopeStack.append([])

#     def pop(self):
#         return self.scopeStack.pop()

#     def visitNoun(self, name):
#         boundNames = self.boundNames()
#         try:
#             return boundNames.index(name)
#         except ValueError:
#             rv = len(boundNames)
#             boundNames.append(name)
#             return rv
