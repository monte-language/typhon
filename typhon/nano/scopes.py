# -*- coding: utf-8 -*-

from collections import OrderedDict

from typhon.enum import makeEnum
from typhon.errors import userError
from typhon.nano.slots import NoAssignIR

"""
Static scope analysis, in several passes:
 * Discovering the static scope layout
 * Removing meta.context()
 * Removing meta.state()
 * Laying out specialized frames
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
    return ast, layoutPass.top.outers, topLocalNames, localSize

LayoutIR = NoAssignIR.extend(
    "Layout", [],
    {
        "Expr": {
            "BindingExpr": [("name", "Noun"), ("layout", None)],
            "SlotExpr": [("name", "Noun"), ("layout", None)],
            "NounExpr": [("name", "Noun"), ("layout", None)],
            "TempNounExpr": [("name", "Noun"), ("layout", None)],
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
            "TempPatt": [("name", "Noun"), ("layout", None)],
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

    def findChild(self, name):
        """
        Search through children and find the given name.
        """

        for child in self.children:
            scope, idx, severity = child.find(name)
            if scope is not None:
                return scope, idx, severity
        raise scopeError(self, u"Impossibility in findChild")


class ScopeOuter(ScopeBase):
    def __init__(self, outers, fqn, inRepl):
        self.outers = OrderedDict()
        for i, outer in enumerate(outers):
            self.outers[outer] = i, SEV_SLOT
        self.children = []
        self.fqn = fqn
        self.inRepl = inRepl

    def collectTopLocals(self):
        # In an interactive context, we may want to keep locals defined at the
        # top level for future use.
        topLocals = [(u"", SEV_BINDING)] * 5
        scopeitems = self.children[:]
        numLocals = 0
        for sub in scopeitems:
            if isinstance(sub, ScopeItem):
                i = sub.position
                numLocals = max(numLocals, i + 1)
                while (i + 1) > len(topLocals):
                    topLocals.extend([(u"", SEV_BINDING)] * len(topLocals))
                topLocals[i] = sub.name, sub.severity
                scopeitems.extend(sub.children)

        return topLocals[:numLocals], countLocalSize(self, 0)

    def requireShadowable(self, name, toplevel):
        if name in self.outers and not (toplevel and self.inRepl):
            raise scopeError(self, u"Cannot redefine " + name)

    def deepen(self, name, severity):
        if name in self.outers:
            index, sev = self.outers[name]
            if sev.asInt < severity.asInt:
                self.outers[name] = index, severity

    def find(self, name):
        if name in self.outers:
            index, severity = self.outers[name]
            return SCOPE_OUTER, index, severity
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
        self.outerNames = OrderedDict()
        return ScopeBase.__init__(self, next, fqn)

    def requireShadowable(self, name, toplevel):
        return self.next.requireShadowable(name, False)

    def deepen(self, name, severity):
        self.next.deepen(name, severity)

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

    def deepen(self, name, severity):
        self.next.deepen(name, severity)

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

    def deepen(self, name, severity):
        if self.name == name and self.severity.asInt < severity.asInt:
            self.severity = severity
        self.next.deepen(name, severity)

    def find(self, name):
        if self.name == name:
            return SCOPE_LOCAL, self.position, self.severity
        return self.next.find(name)


class LayOutScopes(NoAssignIR.makePassTo(LayoutIR)):
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
        # NB: If there's a guard, then we'll promote this to slot severity so
        # that auditors can recover the guard. ~ C.
        if isinstance(result.guard, self.dest.NullExpr):
            severity = SEV_NOUN
        else:
            severity = SEV_SLOT
        self.layout = ScopeItem(self.layout, name, severity)
        origLayout.addChild(self.layout)
        self.layout.node = result
        return result

    def visitTempPatt(self, name):
        origLayout = self.layout
        self.layout.requireShadowable(name, True)
        result = self.dest.TempPatt(name, origLayout)
        self.layout = ScopeItem(self.layout, name, SEV_NOUN)
        origLayout.addChild(self.layout)
        self.layout.node = result
        return result

    def visitVarPatt(self, name, guard):
        origLayout = self.layout
        self.layout.requireShadowable(name, True)
        result = self.dest.VarPatt(name, self.visitExpr(guard), origLayout)
        # Perhaps in the future we could do some sort of absorbing, but not
        # today. Nope.
        self.layout = ScopeItem(self.layout, name, SEV_SLOT)
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
        # If we have auditors, then we need to make sure that the as-auditor
        # is added to the slot information, so we need to reify the slot.
        if auds and (isinstance(p, self.dest.FinalPatt) or
                     isinstance(p, self.dest.VarPatt)):
            self.layout.deepen(p.name, SEV_SLOT)
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

    def visitTempNounExpr(self, name):
        return self.dest.TempNounExpr(name, self.layout)

    def visitSlotExpr(self, name):
        self.layout.deepen(name, SEV_SLOT)
        return self.dest.SlotExpr(name, self.layout)

    def visitBindingExpr(self, name):
        self.layout.deepen(name, SEV_BINDING)
        return self.dest.BindingExpr(name, self.layout)

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
    ast = ReifyMetaState().visitExpr(ast)
    ast = ReifyMetaContext().visitExpr(ast)
    ast = SpecializeNouns().visitExpr(ast)
    return ast


ReifyMetaStateIR = LayoutIR.extend(
    "ReifyMetaState", [], {
        "Expr": {
            "-MetaStateExpr": None,
        }
    }
)

class ReifyMetaState(LayoutIR.makePassTo(ReifyMetaStateIR)):

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
            self.dest.NounExpr(u"_makeMap", layout),
            u"fromPairs", [
                self.dest.CallExpr(
                    self.dest.NounExpr(u"_makeList", layout),
                    u"run", [self.dest.CallExpr(
                        self.dest.NounExpr(u"_makeList", layout),
                        u"run", [self.dest.StrExpr(u"&&" + name),
                                 self.dest.BindingExpr(name, layout)],
                        [])], [])
                for name in frame.keys()], [])


ReifyMetaContextIR = ReifyMetaStateIR.extend(
    "ReifyMetaContext", [], {
        "Expr": {
            "-MetaContextExpr": None,
        }
    }
)

class ReifyMetaContext(ReifyMetaStateIR.makePassTo(ReifyMetaContextIR)):

    def visitMetaContextExpr(self, layout):
        fqn = layout.fqn
        frame = ScopeFrame(layout, u'META')
        return self.dest.ObjectExpr(
            u"",
            self.dest.IgnorePatt(self.dest.NullExpr()),
            [], [self.dest.MethodExpr(
                u"", u"getFQNPrefix", [], [], self.dest.NullExpr(),
                self.dest.StrExpr(fqn + u'$'), layout)],
            [], None, frame)


BoundNounsIR = ReifyMetaContextIR.extend(
    "BoundNouns", [], {
        "Expr": {
            "-NounExpr": None,
            "-TempNounExpr": None,
            "-SlotExpr": None,
            "-BindingExpr": None,
            "LocalExpr": [("name", "Noun"), ("index", None)],
            "FrameExpr": [("name", "Noun"), ("index", None)],
            "OuterExpr": [("name", "Noun"), ("index", None)],
        },
        "Patt": {
            "-TempPatt": None,
            "-FinalPatt": None,
            "-VarPatt": None,
            "NounPatt": [("name", "Noun"), ("guard", "Expr"),
                          ("index", None)],
            "FinalSlotPatt": [("name", "Noun"), ("guard", "Expr"),
                              ("index", None)],
            "VarSlotPatt": [("name", "Noun"), ("guard", "Expr"),
                            ("index", None)],
            "FinalBindingPatt": [("name", "Noun"), ("guard", "Expr"),
                                 ("index", None)],
            "VarBindingPatt": [("name", "Noun"), ("guard", "Expr"),
                               ("index", None)],
            "BindingPatt": [("name", "Noun"), ("index", None)],
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

class SpecializeNouns(ReifyMetaContextIR.makePassTo(BoundNounsIR)):

    def visitBindingPatt(self, name, layout):
        return self.dest.BindingPatt(name, layout.position + 1)

    def visitFinalPatt(self, name, guard, layout):
        _, _, severity = layout.findChild(name)
        guard = self.visitExpr(guard)
        if severity is SEV_NOUN:
            return self.dest.NounPatt(name, guard, layout.position + 1)
        elif severity is SEV_SLOT:
            return self.dest.FinalSlotPatt(name, guard, layout.position + 1)
        elif severity is SEV_BINDING:
            return self.dest.FinalBindingPatt(name, guard, layout.position + 1)
        else:
            assert False, "snape"

    def visitTempPatt(self, name, layout):
        _, _, severity = layout.findChild(name)
        guard = self.dest.NullExpr()
        if severity is SEV_NOUN:
            return self.dest.NounPatt(name, guard, layout.position + 1)
        elif severity is SEV_SLOT:
            return self.dest.FinalSlotPatt(name, guard, layout.position + 1)
        elif severity is SEV_BINDING:
            return self.dest.FinalBindingPatt(name, guard, layout.position + 1)
        else:
            assert False, "snape"

    def visitVarPatt(self, name, guard, layout):
        _, _, severity = layout.findChild(name)
        guard = self.visitExpr(guard)
        # NB: Not prepared to handle SEV_NOUN vars yet.
        if severity is SEV_SLOT:
            return self.dest.VarSlotPatt(name, guard, layout.position + 1)
        elif severity is SEV_BINDING:
            return self.dest.VarBindingPatt(name, guard, layout.position + 1)
        else:
            assert False, "snape"

    def makeStorage(self, name, index, scope):
        if scope is SCOPE_LOCAL:
            return self.dest.LocalExpr(name, index, scope)
        elif scope is SCOPE_FRAME:
            return self.dest.FrameExpr(name, index, scope)
        elif scope is SCOPE_OUTER:
            return self.dest.OuterExpr(name, index, scope)
        else:
            assert False, "thesaurus"

    def bindingToSlot(self, noun):
        return self.dest.CallExpr(noun, u"get", [], [])

    def slotToNoun(self, noun):
        return self.dest.CallExpr(noun, u"get", [], [])

    def visitNounExpr(self, name, layout):
        scope, idx, severity = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        storage = self.makeStorage(name, idx, scope)
        if severity is SEV_BINDING:
            return self.slotToNoun(self.bindingToSlot(storage))
        elif severity is SEV_SLOT:
            return self.slotToNoun(storage)
        else:
            return storage

    def visitTempNounExpr(self, name, layout):
        scope, idx, severity = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        storage = self.makeStorage(name, idx, scope)
        if severity is SEV_BINDING:
            return self.slotToNoun(self.bindingToSlot(storage))
        elif severity is SEV_SLOT:
            return self.slotToNoun(storage)
        else:
            return storage

    def visitSlotExpr(self, name, layout):
        scope, idx, severity = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        storage = self.makeStorage(name, idx, scope)
        if severity is SEV_BINDING:
            return self.bindingToSlot(storage)
        else:
            return storage

    def visitBindingExpr(self, name, layout):
        scope, idx, _ = layout.find(name)
        if scope is None:
            raise scopeError(layout, name + u" is not defined")
        return self.makeStorage(name, idx, scope)

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
