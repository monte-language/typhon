"""
Partial evaluation.

This version of mixing is based on two separate stages. First, we stir the
outer names into the AST, closing its object graph. Second, we perform
whatever partial evaluation we like on the AST.

The separation allows us to make the first part short and sweet.
"""

from collections import OrderedDict

from typhon.nano.scopes import SEV_BINDING, SEV_NOUN, SEV_SLOT
from typhon.nano.structure import SplitAuditorsIR
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.slots import FinalSlot, VarSlot

def mix(ast, outers):
    ast = FillOuters(outers).visitExpr(ast)
    return ast

MixIR = SplitAuditorsIR.extend("Mix",
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

class FillOuters(SplitAuditorsIR.makePassTo(MixIR)):

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
        return self.dest.ObjectExpr(doc, patt, guards, auditors, script, mast,
                layout, clipboard)

    def visitOuterExpr(self, name, index):
        return self.dest.LiveExpr(self.outers[index])
