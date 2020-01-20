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
from typhon.nano.structure import AtomIR
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.user import Audition
from typhon.objects.slots import FinalSlot, VarSlot

from typhon.nano.mast import BuildKernelNodes
from typhon.objects.user import AuditClipboard


def mix(ast, outers):
    ast = FillOuters(outers).visitExpr(ast)
    ast = ThawLiterals().visitExpr(ast)
    ast = SplitAuditors().visitExpr(ast)
    ast = DischargeAuditors().visitExpr(ast)
    return ast

NoOutersIR = AtomIR.extend("NoOuters",
    ["Object"],
    {
        "Expr": {
            "LiveExpr": [("obj", "Object")],
            "ObjectExpr": [("patt", "Patt"), ("guards", None),
                           ("auditors", "Expr*"), ("script", "Script")],
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

class FillOuters(AtomIR.makePassTo(NoOutersIR)):

    def __init__(self, outers):
        self.outers = outers

    def visitObjectExpr(self, patt, auditors, script, span):
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        script = self.visitScript(script)
        # Take all of the outers, find guards for them, and then save the
        # guards for later. We rely on this ordering to be consistent so that
        # we can strip the names when doing auditor cache comparisons. ~ C.
        guards = OrderedDict()
        for (name, (idx, severity)) in script.layout.outerNames.items():
            b = self.outers[idx]
            guards[name] = retrieveGuard(severity, b)
            # Mark the guard as static by destroying the relevant dynamic
            # guard key. Use .pop() to avoid KeyErrors from unused bindings.
            script.layout.frameTable.dynamicGuards.pop(name, 0)
        return self.dest.ObjectExpr(patt, guards, auditors, script, span)

    def visitOuterExpr(self, name, index, span):
        return self.dest.LiveExpr(self.outers[index], span)

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

    def visitCharExpr(self, c, span):
        return self.dest.LiveExpr(CharObject(c), span)

    def visitDoubleExpr(self, d, span):
        return self.dest.LiveExpr(DoubleObject(d), span)

    def visitIntExpr(self, bi, span):
        try:
            return self.dest.LiveExpr(IntObject(bi.toint()), span)
        except OverflowError:
            return self.dest.LiveExpr(BigInt(bi), span)

    def visitStrExpr(self, s, span):
        return self.dest.LiveExpr(StrObject(s), span)


SplitAuditorsIR = NoLiteralsIR.extend(
    "SplitAuditors",
    ["AST"],
    {
        "Expr": {
            "ClearObjectExpr": [("patt", "Patt"), ("script", "Script")],
            "ObjectExpr": [("patt", "Patt"), ("guards", None),
                           ("auditors", "Expr*"), ("script", "Script"),
                           ("clipboard", None)],
        },
    }
)


class SplitAuditors(NoLiteralsIR.makePassTo(SplitAuditorsIR)):

    def visitObjectExpr(self, patt, guards, auditors, script, span):
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(auditor) for auditor in auditors]
        script = self.visitScript(script)
        if not auditors or (len(auditors) == 1 and
                            isinstance(auditors[0], self.dest.NullExpr)):
            # No more auditing.
            return self.dest.ClearObjectExpr(patt, script, span)
        else:
            # Runtime auditing.
            ast = BuildKernelNodes().visitExpr(script.mast)
            clipboard = AuditClipboard(script.layout.fqn, ast)
            return self.dest.ObjectExpr(patt, guards, auditors, script,
                                        clipboard, span)


StampedScriptIR = SplitAuditorsIR.extend("StampedScriptIR", [],
    {
        "Script": {
            "ScriptExpr": [("name", None), ("doc", None), ("mast", None),
                           ("layout", None), ("stamps", "Object*"),
                           ("methods", "Method*"),
                           ("matchers", "Matcher*")],
        },
    }
)


class DischargeAuditors(SplitAuditorsIR.makePassTo(StampedScriptIR)):

    def __init__(self):
        from typhon.metrics import globalRecorder
        recorder = globalRecorder()
        self.clearRate = recorder.getRateFor("DischargeAuditors clear")


    def visitScriptExpr(self, name, doc, mast, layout, methods, matchers,
                        span):
        return self.dest.ScriptExpr(name, doc, mast, layout,
                                    [],
                                    [self.visitMethod(m) for m in methods],
                                    [self.visitMatcher(m) for m in matchers],
                                    span)

    def visitObjectExpr(self, patt, guards, auditors, script, clipboard, span):
        script = self.visitScript(script)
        patt = self.visitPatt(patt)
        auditors = [self.visitExpr(a) for a in auditors]
        clear = False
        if auditors:
            asAuditor = auditors[0]
            if isinstance(asAuditor, self.dest.LiveExpr):
                patt.guard = asAuditor
                from typhon.nano.interp import GuardInfo, anyGuardLookup
                guardInfo = GuardInfo(guards, script.layout.frameTable, None, None,
                        anyGuardLookup)
                with Audition(script.layout.fqn, clipboard.ast, guardInfo) as audition:
                    for i, auditor in enumerate(auditors):
                        if not isinstance(auditor, self.dest.LiveExpr):
                            # Slice to save progress and take the non-clear
                            # path.
                            auditors = auditors[i:]
                            break
                        auditor = auditor.obj
                        # We don't care about the return value here. Instead,
                        # we determine which stamps to issue from the audition
                        # report. This is required to pick up
                        # subordinate/private stamps which the auditor knows
                        # about but which we don't have. The canonical example
                        # of such an auditor is DeepFrozen, which anoints
                        # DeepFrozenStamp but returns false from .ask/1. ~ C.
                        try:
                            audition.ask(auditor)
                        except UserException:
                            break
                    else:
                        # We made it through all of the auditors; we can go clear.
                        clear = True
                # Save any stamps that we've collected. Since we've sliced off
                # asked auditors, we can't lose these stamps.
                report = audition.prepareReport()
                stamps = report.stamps.keys()
                script = self.dest.ScriptExpr(script.name, script.doc,
                                              script.mast, script.layout,
                                              stamps,
                                              script.methods, script.matchers,
                                              span)
                # In order to be truly clear, we must not have depended on any
                # dynamic guards.
                clear &= not report.isDynamic

        if clear:
            self.clearRate.yes()
            return self.dest.ClearObjectExpr(patt, script, span)
        else:
            self.clearRate.no()
            return self.dest.ObjectExpr(patt, guards, auditors, script,
                                        clipboard, span)
