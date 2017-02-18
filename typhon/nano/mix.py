"""
Partial evaluation.

This version of mixing is based on two separate stages. First, we stir the
outer names into the AST, closing its object graph. Second, we perform
whatever partial evaluation we like on the AST.

The separation allows us to make the first part short and sweet.
"""

from collections import OrderedDict

from typhon.errors import Ejecting, UserException
from typhon.nano.scopes import SEV_BINDING, SEV_NOUN, SEV_SLOT
from typhon.nano.structure import SplitAuditorsIR
from typhon.objects.auditors import deepFrozenGuard
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.ejectors import Ejector
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.user import Audition
from typhon.objects.slots import Binding, FinalSlot, VarSlot

def mix(ast, outers):
    ast = FillOuters(outers).visitExpr(ast)
    ast = ThawLiterals().visitExpr(ast)
    ast = SpecializeCalls().visitExpr(ast)
    ast = DischargeAuditors().visitExpr(ast)
    return ast

NoOutersIR = SplitAuditorsIR.extend("NoOuters",
    ["Object"],
    {
        "Expr": {
            "LiveExpr": [("obj", "Object")],
            "ObjectExpr": [("patt", "Patt"), ("guards", None),
                           ("auditors", "Expr*"), ("script", "Script"),
                           ("mast", "AST"), ("layout", None),
                           ("clipboard", None)],
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

    def visitObjectExpr(self, patt, auditors, script, mast, layout,
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
        return self.dest.ObjectExpr(patt, guards, auditors, script, mast,
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

# XXX I don't know why this isn't defined anywhere else. The version in
# t.o.refs is suspect. ~ C.
def isDeepFrozen(obj):
    with Ejector() as ej:
        try:
            deepFrozenGuard.coerce(obj, ej)
            return True
        except Ejecting as ex:
            if ex.ejector is not ej:
                raise
    return False

class SpecializeCalls(NoLiteralsIR.makePassTo(MixIR)):

    def enliven(self, expr):
        """
        If `expr` is live and DeepFrozen or thawable, return the live object.

        Otherwise, return None.
        """

        # Side-effect: The live object might have observable side effects even
        # though it is DeepFrozen; in particular, traceln() comes to mind. If
        # it *is* traceln(), then we make an effort to not write misleading
        # things into the debug log. ~ C.

        if isinstance(expr, self.dest.LiveExpr):
            obj = expr.obj

            # Special case for traceln().
            from typhon.scopes.safe import TraceLn
            if isinstance(obj, TraceLn):
                return None

            if isinstance(obj, Binding) or isinstance(obj, FinalSlot):
                return obj
            elif isDeepFrozen(obj):
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
                        result = liveObj.call(atom.verb, liveArgs)
                        assert result is not None, "livewire"
                        if isDeepFrozen(result):
                            return self.dest.LiveExpr(result)
                        # print "Not DF:", str(result)[:50]
                    except UserException as ue:
                        return self.dest.ExceptionExpr(ue)
        return self.dest.CallExpr(obj, atom, args, namedArgs)

class DischargeAuditors(MixIR.selfPass()):

    def __init__(self):
        from typhon.metrics import globalRecorder
        recorder = globalRecorder()
        self.clearRate = recorder.getRateFor("DischargeAuditors clear")

    def visitObjectExpr(self, patt, guards, auditors, script, mast,
                        layout, clipboard):
        script = self.visitScript(script)
        clear = False
        if auditors:
            asAuditor = auditors[0]
            if isinstance(asAuditor, self.src.LiveExpr):
                patt.guard = asAuditor
                from typhon.nano.interp import GuardInfo, anyGuardLookup
                guardInfo = GuardInfo(guards, layout.frameTable, None, None,
                        anyGuardLookup)
                with Audition(layout.fqn, mast, guardInfo) as audition:
                    for i, auditor in enumerate(auditors):
                        if not isinstance(auditor, self.src.LiveExpr):
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
                script = self.dest.ScriptExpr(script.doc,
                                              script.stamps + stamps,
                                              script.methods, script.matchers)
                # In order to be truly clear, we must not have depended on any
                # dynamic guards.
                clear &= not report.isDynamic

        if clear:
            self.clearRate.yes()
            return self.dest.ClearObjectExpr(patt, script, layout)
        else:
            self.clearRate.no()
            return self.dest.ObjectExpr(patt, guards, auditors, script, mast,
                                        layout, clipboard)
