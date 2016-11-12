"""
Partial evaluation.

This version of mixing is based on two separate stages. First, we stir the
outer names into the AST, closing its object graph. Second, we perform
whatever partial evaluation we like on the AST.

The separation allows us to make the first part short and sweet.
"""

from collections import OrderedDict

from typhon.errors import UserException
from typhon.nano.scopes import SEV_BINDING, SEV_NOUN, SEV_SLOT
from typhon.nano.structure import SplitAuditorsIR
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.slots import Binding, FinalSlot, VarSlot

def mix(ast, outers):
    ast = FillOuters(outers).visitExpr(ast)
    ast = ThawLiterals().visitExpr(ast)
    ast = SpecializeCalls().visitExpr(ast)
    return ast

NoOutersIR = SplitAuditorsIR.extend("NoOuters",
    ["Object"],
    {
        "Expr": {
            "LiveExpr": [("obj", "Object")],
            "ObjectExpr": [("doc", None), ("patt", "Patt"),
                           ("guards", None), ("auditors", "Expr*"),
                           ("script", "Script"), ("mast", "AST"),
                           ("layout", None), ("clipboard", None)],
            "-OuterExpr": None,
        }
    }
)

def retrieveGuard(severity, storage):
    """
    Get a guard from some storage.
    """

    if severity is SEV_BINDING:
        slot = storage.call(u"get", [])
        return slot.call(u"getGuard", [])
    elif severity is SEV_SLOT:
        if isinstance(storage, FinalSlot):
            valueGuard = storage.call(u"getGuard", [])
            return FinalSlotGuard(valueGuard)
        elif isinstance(storage, VarSlot):
            valueGuard = storage.call(u"getGuard", [])
            return VarSlotGuard(valueGuard)
        else:
            return anyGuard
    elif severity is SEV_NOUN:
        return anyGuard
    else:
        assert False, "landlord"

class FillOuters(SplitAuditorsIR.makePassTo(NoOutersIR)):

    def __init__(self, outers):
        self.outers = outers

    def visitObjectExpr(self, doc, patt, auditors, script, mast, layout,
                        clipboard):
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        script = self.visitScript(script)
        # Take all of the outers, find guards for them, and then save the
        # guards for later. We rely on this ordering to be consistent so that
        # we can strip the names when doing auditor cache comparisons. ~ C.
        guards = OrderedDict()
        for (name, (idx, severity)) in layout.outerNames.items():
            b = self.outers[idx]
            guards[name] = retrieveGuard(severity, b)
            # Mark the guard as static by destroying the relevant dynamic
            # guard key. Use .pop() to avoid KeyErrors from unused bindings.
            layout.frameTable.dynamicGuards.pop(name, 0)
        return self.dest.ObjectExpr(doc, patt, guards, auditors, script, mast,
                layout, clipboard)

    def visitOuterExpr(self, name, index):
        return self.dest.LiveExpr(self.outers[index])

NoLiteralsIR = NoOutersIR.extend("NoLiterals",
    [],
    {
        "Expr": {
            "-CharExpr": None,
            "-DoubleExpr": None,
            "-IntExpr": None,
            "-StrExpr": None,
        }
    }
)

class ThawLiterals(NoOutersIR.makePassTo(NoLiteralsIR)):

    def visitCharExpr(self, c):
        return self.dest.LiveExpr(CharObject(c))

    def visitDoubleExpr(self, d):
        return self.dest.LiveExpr(DoubleObject(d))

    def visitIntExpr(self, bi):
        try:
            return self.dest.LiveExpr(IntObject(bi.toint()))
        except OverflowError:
            return self.dest.LiveExpr(BigInt(bi))

    def visitStrExpr(self, s):
        return self.dest.LiveExpr(StrObject(s))

MixIR = NoLiteralsIR.extend("Mix",
    ["Exception"],
    {
        "Expr": {
            "ExceptionExpr": [("exception", "Exception")],
        }
    }
)

class SpecializeCalls(NoLiteralsIR.makePassTo(MixIR)):

    def enliven(self, expr):
        """
        If `expr` is live and DeepFrozen or thawable, return the live object.

        Otherwise, return None.
        """

        if isinstance(expr, self.dest.LiveExpr):
            obj = expr.obj
            if isinstance(obj, Binding) or isinstance(obj, FinalSlot):
                return obj
            elif obj.auditedBy(deepFrozenStamp):
                return obj
        return None

    def visitCallExpr(self, obj, atom, args, namedArgs):
        obj = self.visitExpr(obj)
        args = [self.visitExpr(arg) for arg in args]
        namedArgs = [self.visitNamedArg(namedArg) for namedArg in namedArgs]
        liveObj = self.enliven(obj)
        if liveObj is not None:
            liveArgs = [self.enliven(arg) for arg in args]
            if None not in liveArgs:
                # XXX named args
                if not namedArgs:
                    try:
                        # Side-effect: The live object might have observable
                        # side effects even though it is DeepFrozen; in
                        # particular, traceln() comes to mind. We generally
                        # don't care about those side effects, and invite them
                        # for debugging purposes, but it's good to be aware of
                        # this. ~ C.
                        result = liveObj.call(atom.verb, liveArgs)
                        assert result is not None, "livewire"
                        if result.auditedBy(deepFrozenStamp):
                            return self.dest.LiveExpr(result)
                    except UserException as ue:
                        return self.dest.ExceptionExpr(ue)
        return self.dest.CallExpr(obj, atom, args, namedArgs)
