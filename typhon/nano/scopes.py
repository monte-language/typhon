# -*- coding: utf-8 -*-

from collections import OrderedDict

from typhon.enum import makeEnum
from typhon.errors import userError
from typhon.nano.mast import SaveScriptIR

"""
Static scope analysis, in several passes:
 * Noun specialization
 * De Bruijn indices
 * Escape analysis
 * Slot specialization
 * Deslotification
"""

def scopeError(layout, message):
    return userError(u"Error in scope of %s: %s" % (layout.fqn, message))

# The scope of a name; where the name is defined relative to each name use.
SCOPE_OUTER, SCOPE_FRAME, SCOPE_LOCAL = makeEnum(u"scope",
    [u"outer", u"frame", u"local"])

# The severity of a name; how deeply-reified the binding and slot of a name
# are in the actual backing storage of a frame.
SEV_NOUN, SEV_SLOT, SEV_BINDING = makeEnum(u"severity",
    [u"noun", u"slot", u"binding"])

def layoutScopes(ast, outers, fqn, inRepl):
    """
    Perform scope analysis.
    """

    layoutPass = LayOutScopes(outers, fqn, inRepl)
    ast = layoutPass.visitExpr(ast)
    topLocalNames, localSize = layoutPass.top.collectTopLocals()
    return ast, topLocalNames, localSize

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


def countLocalSize(lo, sizeSeen):
    sizeSeen = max(sizeSeen, lo.position + 1)
    for x in lo.children:
        sizeSeen = max(countLocalSize(x, sizeSeen), sizeSeen)
    return sizeSeen


class ScopeBase(object):
    position = -1

    def __init__(self, next, fqn):
        self.next = next
        self.children = []
        self.node = None
        self.fqn = fqn

    def addChild(self, child):
        if child is self:
            assert False, "BZZT WRONG"
        self.children.append(child)


class ScopeOuter(ScopeBase):
    def __init__(self, outers, fqn, inRepl):
        self.outers = outers
        self.children = []
        self.fqn = fqn
        self.inRepl = inRepl

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

        return topLocals[:numLocals], countLocalSize(self, 0)

    def requireShadowable(self, name, toplevel):
        if name in self.outers and not (toplevel and self.inRepl):
            raise scopeError(self, u"Cannot redefine " + name)

    def find(self, name):
        if name in self.outers:
            return SCOPE_OUTER, self.outers.index(name), SEV_NOUN
        return None, 0, None


class ScopeFrame(ScopeBase):
    "Scope info associated with an object closure."

    def __init__(self, next, fqn):
        # Names closed over. The use of OrderedDict here forces this
        # dictionary to stay ordered according to insertion. Since we only
        # append to frameNames, iteration over this dict will be in the
        # correct order later. ~ C.
        self.frameNames = OrderedDict()
        # Names from outer scope used (not included in closure at runtime)
        self.outerNames = {}
        return ScopeBase.__init__(self, next, fqn)

    def requireShadowable(self, name, toplevel):
        return self.next.requireShadowable(name, False)

    def find(self, name):
        scope, idx, severity = self.next.find(name)
        if scope is None:
            return scope, idx, severity
        if scope is SCOPE_OUTER:
            self.outerNames[name] = (idx, severity)
            return scope, idx, severity
        if name not in self.frameNames:
            self.frameNames[name] = (len(self.frameNames), scope, idx,
                                     severity)
        return SCOPE_FRAME, self.frameNames[name][0], severity

    def swizzleFrame(self):
        """
        Rearrange the frame into an ordered form, swizzling from the
        dict of names into the list of positions in the frame.
        """

        # Cheat; the frameNames dict is already correctly ordered by
        # construction, so we can just iterate over it. ~ C.
        return [(n, scope, idx, severity) for (n, (i, scope, idx, severity))
                in self.frameNames.iteritems()]

    def positionOf(self, name):
        """
        The index of the position in the frame where the name would be placed,
        or -1 if no position is reserved.
        """

        return self.frameNames[name][0] if name in self.frameNames else -1


class ScopeBox(ScopeBase):
    "Scope info associated with a scope-introducing node."

    def __init__(self, next):
        ScopeBase.__init__(self, next, next.fqn)
        self.position = next.position

    def requireShadowable(self, name, toplevel):
        scope, idx, _ = self.find(name)
        if scope is SCOPE_OUTER:
            self.next.requireShadowable(name, False)

    def find(self, name):
        return self.next.find(name)


class ScopeItem(ScopeBase):
    "A single name binding."
    def __init__(self, next, name, severity):
        self.name = name
        self.position = next.position + 1
        self.severity = severity
        return ScopeBase.__init__(self, next, next.fqn)

    def requireShadowable(self, name, toplevel):
        if self.name == name:
            raise scopeError(self, u"Cannot redefine " + name)
        self.next.requireShadowable(name, False)

    def find(self, name):
        if self.name == name:
            return SCOPE_LOCAL, self.position, self.severity
        return self.next.find(name)


class LayOutScopes(SaveScriptIR.makePassTo(LayoutIR)):
    """
    Set up scope boxes and collect variable definition sites.
    """
    def __init__(self, outers, fqn, inRepl=False):
        self.top = self.layout = ScopeOuter(outers, fqn, inRepl)

    def visitExprWithLayout(self, node, layout):
        origLayout = self.layout
        origLayout.addChild(layout)
        self.layout = layout
        result = self.visitExpr(node)
        layout.node = result
        self.layout = origLayout
        return result

    def visitExprNested(self, node):
        return self.visitExprWithLayout(node, ScopeBox(self.layout))

    def visitFinalPatt(self, name, guard):
        origLayout = self.layout
        self.layout.requireShadowable(name, True)
        result = self.dest.FinalPatt(name, self.visitExpr(guard), origLayout)
        # NB: Even if there's a guard, the guard will only be run once and
        # then the name will be accessed as if it were a noun. ~ C.
        severity = SEV_NOUN
        self.layout = ScopeItem(self.layout, name, severity)
        origLayout.addChild(self.layout)
        self.layout.node = result
        return result

    def visitVarPatt(self, name, guard):
        origLayout = self.layout
        self.layout.requireShadowable(name, True)
        result = self.dest.VarPatt(name, self.visitExpr(guard), origLayout)
        # Perhaps in the future we could do some sort of absorbing, but not
        # today. Nope.
        severity = SEV_SLOT
        self.layout = ScopeItem(self.layout, name, severity)
        self.layout.node = result
        origLayout.addChild(self.layout)
        return result

    def visitBindingPatt(self, name):
        origLayout = self.layout
        self.layout.requireShadowable(name, True)
        result = self.dest.BindingPatt(name, origLayout)
        self.layout = ScopeItem(self.layout, name, SEV_BINDING)
        self.layout.node = result
        origLayout.addChild(self.layout)
        return result

    def visitHideExpr(self, body):
        return self.visitExprNested(body)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body):
        origLayout = self.layout
        self.layout = ScopeBox(self.layout)
        origLayout.addChild(self.layout)
        result = self.dest.MethodExpr(
            doc, verb,
            [self.visitPatt(p) for p in patts],
            [self.visitNamedPatt(np) for np in namedPatts],
            self.visitExpr(guard), self.visitExpr(body), origLayout)
        self.layout.node = result
        self.layout = origLayout
        return result

    def visitMatcherExpr(self, patt, body):
        origLayout = self.layout
        self.layout = ScopeBox(self.layout)
        origLayout.addChild(self.layout)
        result = self.dest.MatcherExpr(self.visitPatt(patt),
                                       self.visitExpr(body), origLayout)
        self.layout.node = result
        self.layout = origLayout
        return result

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast):
        if isinstance(patt, self.src.IgnorePatt):
            objName = u'_'
        elif isinstance(patt, self.src.FinalPatt) or isinstance(
                patt, self.src.VarPatt):
            objName = patt.name
        else:
            objName = u'???'
        p = self.visitPatt(patt)
        origLayout = self.layout
        # Names defined in auditors exprs are visible inside the object but not
        # outside it, but aren't necessarily part of the frame.
        outerBox = ScopeBox(origLayout)
        origLayout.addChild(outerBox)
        auds = [self.visitExpr(a) for a in auditors]
        self.layout = ScopeFrame(outerBox, origLayout.fqn + u'$' + objName)
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
        origLayout.addChild(self.layout)
        p = self.visitPatt(patt)
        b = self.visitExpr(body)
        result = self.dest.EscapeOnlyExpr(p, b)
        self.layout.node = result
        self.layout = origLayout
        return result

    def visitEscapeExpr(self, ejPatt, ejBody, catchPatt, catchBody):
        origLayout = self.layout
        self.layout = layout1 = ScopeBox(origLayout)
        p = self.visitPatt(ejPatt)
        b = self.visitExpr(ejBody)
        self.layout = layout2 = ScopeBox(origLayout)
        origLayout.addChild(layout1)
        origLayout.addChild(layout2)
        cp = self.visitPatt(catchPatt)
        cb = self.visitExpr(catchBody)
        result = self.dest.EscapeExpr(p, b, cp, cb)
        layout1.node = result
        layout2.node = result
        self.layout = origLayout
        return result

    def visitFinallyExpr(self, body, atLast):
        return self.dest.FinallyExpr(
            self.visitExprNested(body),
            self.visitExprNested(atLast))

    def visitIfExpr(self, test, consq, alt):
        origLayout = self.layout
        self.layout = layout1 = ScopeBox(origLayout)
        origLayout.addChild(layout1)
        t = self.visitExpr(test)
        c = self.visitExpr(consq)
        self.layout = layout2 = ScopeBox(origLayout)
        origLayout.addChild(layout2)
        e = self.visitExpr(alt)
        result = self.dest.IfExpr(t, c, e)
        layout1.node = result
        layout2.node = result
        self.layout = origLayout
        return result

    def visitTryExpr(self, body, catchPatt, catchBody):
        b = self.visitExprNested(body)
        origLayout = self.layout
        self.layout = ScopeBox(origLayout)
        origLayout.addChild(self.layout)
        cp = self.visitPatt(catchPatt)
        cb = self.visitExpr(catchBody)
        result = self.dest.TryExpr(b, cp, cb)
        self.layout.node = result
        self.layout = origLayout
        return result


def bindNouns(ast):
    ast = SpecializeNouns().visitExpr(ast)
    ast = ReifyMeta().visitExpr(ast)
    return ast


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
        "Matcher": {
            "MatcherExpr": [("patt", "Patt"), ("body", "Expr"),
                            ("localSize", None)],
        },
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
        if severity is SEV_NOUN:
            raise scopeError(layout, u"Cannot assign to final variable " + name)
        value = self.visitExpr(rvalue)
        if scope is SCOPE_FRAME:
            return self.dest.FrameAssignExpr(name, idx, value)
        if scope is SCOPE_OUTER:
            return self.dest.OuterAssignExpr(name, idx, value)
        return self.dest.LocalAssignExpr(name, idx, value)

    def visitNounExpr(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        if scope is SCOPE_FRAME:
            return self.dest.FrameNounExpr(name, idx)
        if scope is SCOPE_OUTER:
            return self.dest.OuterNounExpr(name, idx)
        return self.dest.LocalNounExpr(name, idx)

    def visitBindingExpr(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        if scope is SCOPE_FRAME:
            return self.dest.FrameBindingExpr(name, idx)
        if scope is SCOPE_OUTER:
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
            countLocalSize(layout, 0) + 2)

    def visitMatcherExpr(self, patt, body, layout):
        return self.dest.MatcherExpr(
            self.visitPatt(patt),
            self.visitExpr(body),
            countLocalSize(layout, 0) + 2)


ReifyMetaIR = BoundNounsIR.extend(
    "ReifyMeta", [], {
        "Expr": {
            "-MetaContextExpr": None,
            "-MetaStateExpr": None,
        }
    }
)

class ReifyMeta(BoundNounsIR.makePassTo(ReifyMetaIR)):

    def mkNoun(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is SCOPE_OUTER:
            return self.dest.OuterNounExpr(name, idx)
        if scope is SCOPE_FRAME:
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
                                 self.dest.FrameBindingExpr(
                                     name, frame[name][0])],
                        [])], [])
                for name in frame.keys()], [])

    def visitMetaContextExpr(self, layout):
        fqn = layout.fqn
        frame = ScopeFrame(layout, u'META')
        return self.dest.ObjectExpr(
            u"",
            self.dest.IgnorePatt(self.dest.NullExpr()),
            [], [self.dest.MethodExpr(
                u"", u"getFQNPrefix", [], [], self.dest.NullExpr(),
                self.dest.StrExpr(fqn + u'$'), 0)],
            [], None, frame)
