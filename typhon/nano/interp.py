"""
A simple AST interpreter.
"""

from rpython.rlib import rvmprof
from rpython.rlib.jit import promote, unroll_safe, we_are_jitted

from typhon.atoms import getAtom
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.nano.bytecode import BytecodeIR, makeBytecode
from typhon.nano.main import mainPipeline
from typhon.nano.mix import mix
from typhon.nano.scopes import (SCOPE_FRAME, SCOPE_LOCAL,
                                SEV_BINDING, SEV_NOUN, SEV_SLOT)
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.constants import NullObject
from typhon.objects.collections.helpers import emptySet
from typhon.objects.collections.lists import unwrapList, wrapList
from typhon.objects.collections.maps import (ConstMap, EMPTY_MAP, monteMap,
                                             unwrapMap)
from typhon.objects.constants import unwrapBool
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.objects.slots import (Binding, FinalSlot, VarSlot, finalBinding,
                                  varBinding)
from typhon.profile import profileTyphon

COERCE_2 = getAtom(u"coerce", 2)
RUN_2 = getAtom(u"run", 2)
_UNCALL_0 = getAtom(u"_uncall", 0)

NULL_BINDING = finalBinding(NullObject, anyGuard)


ProfileNameIR = BytecodeIR.extend("ProfileName",
    ["ProfileName"],
    {
        "Method": {
            "MethodExpr": [("profileName", "ProfileName"), ("doc", None),
                           ("atom", None), ("patts", "Patt*"),
                           ("namedPatts", "NamedPatt*"), ("guard", "Expr"),
                           ("body", "Expr"), ("localSize", None)],
        },
        "Matcher": {
            "MatcherExpr": [("profileName", "ProfileName"), ("patt", "Patt"),
                            ("body", "Expr"), ("localSize", None)],
        },
    }
)

class MakeProfileNames(BytecodeIR.makePassTo(ProfileNameIR)):
    """
    Prebuild the strings which identify code objects to the profiler.

    This must be the last pass before evaluation, or else profiling will not
    work because the wrong objects will have been registered.
    """

    def __init__(self):
        # NB: self.objectNames cannot be empty unless we somehow obtain a
        # method/matcher without a body. ~ C.
        self.objectNames = []

    def visitClearObjectExpr(self, patt, script):
        # Push, do the recursion, pop.
        objName = script.name
        self.objectNames.append((objName.encode("utf-8"),
            script.layout.fqn.encode("utf-8").split("$")[0]))
        rv = self.super.visitClearObjectExpr(self, patt, script)
        self.objectNames.pop()
        return rv

    def visitObjectExpr(self, patt, guards, auditors, script, clipboard):
        # Push, do the recursion, pop.
        objName = script.name
        self.objectNames.append((objName.encode("utf-8"),
            script.layout.fqn.encode("utf-8").split("$")[0]))
        rv = self.super.visitObjectExpr(self, patt, guards, auditors, script,
                                        clipboard)
        self.objectNames.pop()
        return rv

    def makeProfileName(self, inner):
        name, fqn = self.objectNames[-1]
        return "mt:%s.%s:1:%s" % (name, inner, fqn)

    def visitMethodExpr(self, doc, atom, patts, namedPatts, guard, body,
            localSize):
        # NB: `atom.repr` is tempting but wrong. ~ C.
        description = "%s/%d" % (atom.verb.encode("utf-8"), atom.arity)
        profileName = self.makeProfileName(description)
        patts = [self.visitPatt(patt) for patt in patts]
        namedPatts = [self.visitNamedPatt(namedPatt) for namedPatt in
                namedPatts]
        guard = self.visitExpr(guard)
        body = self.visitExpr(body)
        rv = self.dest.MethodExpr(profileName, doc, atom, patts, namedPatts,
                guard, body, localSize)
        rvmprof.register_code(rv, lambda method: method.profileName)
        return rv

    def visitMatcherExpr(self, patt, body, localSize):
        profileName = self.makeProfileName("matcher")
        patt = self.visitPatt(patt)
        body = self.visitExpr(body)
        rv = self.dest.MatcherExpr(profileName, patt, body, localSize)
        rvmprof.register_code(rv, lambda matcher: matcher.profileName)
        return rv

# Register the interpreted code classes with vmprof.
rvmprof.register_code_object_class(ProfileNameIR.MethodExpr,
        lambda method: method.profileName)
rvmprof.register_code_object_class(ProfileNameIR.MatcherExpr,
        lambda matcher: matcher.profileName)


class InterpObject(Object):
    """
    An object whose script is executed by the AST evaluator.
    """

    _immutable_fields_ = "script", "report", "stamps[*]"

    # Inline single-entry method cache.
    cachedMethod = None, None

    # Auditor report.
    report = None

    def __init__(self, name, script, closure, fqn):
        self.fqn = fqn
        self.script = script
        self.closure = closure

    def docString(self):
        return self.script.doc

    def getDisplayName(self):
        return self.script.name

    # Justified by the immutability of stamps on the script. ~ C.
    @unroll_safe
    @profileTyphon("_auditedBy.run/2")
    def auditedBy(self, prospect):
        """
        Whether the prospect has stamped or audited this object.
        """

        # Same reasoning as in t.o.root.
        prospect = promote(prospect)

        # Note that the identity check used here by default will only work for
        # stamps which are process-global. Presumably, this functionality will
        # only cover DeepFrozenStamp, Selfless, and TransparentStamp at first,
        # but it could eventually justify promotion to a proper set built in
        # t.n.structure. ~ C.
        if prospect in self.script.stamps:
            return True

        if prospect in self.stamps:
            return True

        # super().
        return Object.auditedBy(self, prospect)

    @unroll_safe
    def getMethod(self, atom):
        # If we are JIT'd, then don't bother with the method cache. It will
        # only slow things down. Instead, head directly to the script and find
        # the right method.
        if we_are_jitted():
            for method in promote(self.script).methods:
                if method.atom is atom:
                    return promote(method)
        else:
            if self.cachedMethod[0] is atom:
                return self.cachedMethod[1]
            for method in self.script.methods:
                if method.atom is atom:
                    self.cachedMethod = atom, method
                    return method

    def respondingAtoms(self):
        d = {}
        for method in self.script.methods:
            d[method.atom] = method.doc
        return d

    @rvmprof.vmprof_execute_code("method",
            lambda self, method, args, namedArgs: method,
            result_class=Object)
    def runMethod(self, method, args, namedArgs):
        e = Evaluator(method.frame, self.closure, method.localSize)
        return e.run(method.expr)

    @rvmprof.vmprof_execute_code("matcher",
            lambda self, matcher, message, ej: matcher,
            result_class=Object)
    def runMatcher(self, matcher, message, ej):
        e = Evaluator(matcher.frame, self.closure, matcher.localSize)
        return e.run(matcher.expr)

    def toString(self):
        # Easily the worst part of the entire stringifying experience. We must
        # be careful to not recurse here.
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.getDisplayName()
        except UserException, e:
            return (u"<%s (threw exception %s when printed)>" %
                    (self.getDisplayName(), e.error()))

    def printOn(self, printer):
        # Note that the printer is a Monte-level object. Also note that, at
        # this point, we have had a bad day; we did not respond to _printOn/1.
        from typhon.objects.data import StrObject
        printer.call(u"print",
                     [StrObject(u"<%s>" % self.getDisplayName())])

    def auditorStamps(self):
        if self.report is None:
            return emptySet
        else:
            return self.report.getStamps()

    def isSettled(self, sofar=None):
        if selfless in self.auditorStamps():
            if transparentStamp in self.auditorStamps():
                if sofar is None:
                    sofar = {self: None}
                # Uncall and recurse.
                return self.callAtom(_UNCALL_0, [],
                                     EMPTY_MAP).isSettled(sofar=sofar)
            # XXX Semitransparent support goes here

        # Well, we're resolved, so I guess that we're good!
        return True

    def recvNamed(self, atom, args, namedArgs):
        method = self.getMethod(atom)
        if method:
            return self.runMethod(method, args, namedArgs)
        else:
            # Maybe we should invoke a Miranda method.
            val = self.mirandaMethods(atom, args, namedArgs)
            if val is None:
                # No atoms matched, so there's no prebuilt methods. Instead,
                # we'll use our matchers.
                return self.runMatchers(atom, args, namedArgs)
            else:
                return val

    @unroll_safe
    def runMatchers(self, atom, args, namedArgs):
        message = wrapList([StrObject(atom.verb), wrapList(args),
                            namedArgs])
        for matcher in promote(self.script).matchers:
            with Ejector() as ej:
                try:
                    return self.runMatcher(matcher, message, ej)
                except Ejecting as e:
                    if e.ejector is ej:
                        # Looks like unification failed. On to the next
                        # matcher!
                        continue
                    else:
                        # It's not ours, cap'n.
                        raise

        raise Refused(self, atom, args)


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

class GuardLookup(object):
    def lookupGuard(self, name, frameTable):
        pass
# noGuardLookup = GuardLookup()

class _AnyGuardLookup(GuardLookup):
    def lookupGuard(self, name, frameTable):
        from typhon.objects.guards import anyGuard
        return anyGuard
anyGuardLookup = _AnyGuardLookup()

class EvaluatorGuardLookup(GuardLookup):

    def __init__(self, evaluator):
        self.evaluator = evaluator

    def lookupGuard(self, name, frameTable):
        index = frameTable.dynamicGuards[name]
        _, scope, idx, severity = frameTable.frameInfo[index]
        return retrieveGuard(severity, self.evaluator.lookupBinding(scope, idx))


class Evaluator(ProfileNameIR.makePassTo(None)):

    def __init__(self, staticFrame, frame, localSize):
        self.locals = [NULL_BINDING] * localSize
        self.stack = []
        self.staticFrame = staticFrame
        self.frame = frame
        self.specimen = None
        self.patternFailure = None

        self.guardLookup = EvaluatorGuardLookup(self)

    def run(self, expr):
        self.visitExpr(expr)
        return self.stack[-1]

    def matchBind(self, patt, val, ej=theThrower):
        oldSpecimen = self.specimen
        oldPatternFailure = self.patternFailure
        self.specimen = val
        self.patternFailure = ej
        self.visitPatt(patt)
        self.specimen = oldSpecimen
        self.patternFailure = oldPatternFailure

    def runGuard(self, guard, specimen, ej):
        if ej is None:
            ej = theThrower
        return guard.call(u"coerce", [specimen, ej])

    def sliceStack(self, count):
        offset = len(self.stack) - count
        rv = self.stack[offset:]
        self.stack = self.stack[:offset]
        return rv

    def makeObject(self, script, gatherStamps=False):
        objName = script.name
        frameTable = script.layout.frameTable
        closure = [self.lookupBinding(scope, index) for (_, scope, index, _)
                 in frameTable.frameInfo]
        # Build the object.
        val = InterpObject(objName, script, closure, script.layout.fqn)
        if gatherStamps:
            val.stamps = self.stack.pop()
        self.stack.append(val)

    # Instructions are immutable.
    @unroll_safe
    def visitBytecodeExpr(self, insts):
        from typhon.nano import bytecode as bc
        for inst, idx in insts:
            if inst == bc.POP:
                self.stack.pop()
            elif inst == bc.DUP:
                self.stack.append(self.stack[-1])
            elif inst == bc.SWAP:
                x = self.stack.pop()
                y = self.stack.pop()
                self.stack.append(x)
                self.stack.append(y)
            elif inst == bc.NROT:
                x = self.stack.pop()
                y = self.stack.pop()
                z = self.stack.pop()
                self.stack.append(x)
                self.stack.append(z)
                self.stack.append(y)
            elif inst == bc.OVER:
                self.stack.append(self.stack[-2])
            elif inst == bc.LIVE:
                self.stack.append(self.staticFrame.lives[idx])
            elif inst == bc.EX:
                raise self.staticFrame.exs[idx]
            elif inst == bc.LOCAL:
                self.stack.append(self.locals[idx])
            elif inst == bc.FRAME:
                self.stack.append(self.frame[idx])
            elif inst == bc.BINDFB:
                ej = self.stack.pop()
                specimen = self.stack.pop()
                guard = self.stack.pop()
                val = guard.callAtom(COERCE_2, [specimen, ej], EMPTY_MAP)
                self.locals[idx] = finalBinding(val, guard)
            elif inst == bc.BINDFS:
                ej = self.stack.pop()
                specimen = self.stack.pop()
                guard = self.stack.pop()
                val = guard.callAtom(COERCE_2, [specimen, ej], EMPTY_MAP)
                self.locals[idx] = FinalSlot(val, guard)
            elif inst == bc.BINDN:
                self.locals[idx] = self.stack.pop()
            elif inst == bc.BINDVB:
                ej = self.stack.pop()
                specimen = self.stack.pop()
                guard = self.stack.pop()
                val = guard.callAtom(COERCE_2, [specimen, ej], EMPTY_MAP)
                self.locals[idx] = varBinding(val, guard)
            elif inst == bc.BINDVS:
                ej = self.stack.pop()
                specimen = self.stack.pop()
                guard = self.stack.pop()
                val = guard.callAtom(COERCE_2, [specimen, ej], EMPTY_MAP)
                self.locals[idx] = VarSlot(val, guard)
            elif inst == bc.CALL:
                atom = self.staticFrame.atoms[idx]
                args = self.sliceStack(atom.arity)
                obj = self.stack.pop()
                self.stack.append(obj.callAtom(atom, args, EMPTY_MAP))
            elif inst == bc.CALLMAP:
                atom = self.staticFrame.atoms[idx]
                namedArgs = self.stack.pop()
                args = self.sliceStack(atom.arity)
                obj = self.stack.pop()
                self.stack.append(obj.callAtom(atom, args, namedArgs))
            elif inst == bc.MATCHLIST:
                ej = self.stack.pop()
                l = unwrapList(self.stack.pop(), ej=ej)
                for obj in reversed(l):
                    self.stack.append(obj)
                    self.stack.append(ej)
            elif inst == bc.AUDIT:
                clipboard = self.staticFrame.clipboards[idx]
                auditors = self.sliceStack(clipboard.auditorSize)
                clipboard.guardInfo.guardLookup = self
                clipboard.audit(auditors, clipboard.guardInfo)
            elif inst == bc.MAKEOBJECT:
                self.makeObject(self.staticFrame.scripts[idx])
            elif inst == bc.MAKESTAMPEDOBJECT:
                self.makeObject(self.staticFrame.scripts[idx],
                        gatherStamps=True)
            elif inst == bc.TIEKNOT:
                obj = self.stack[-1]
                assert isinstance(obj, InterpObject), "tonguetied"
                obj.closure[idx] = obj
            else:
                import pdb; pdb.set_trace()
                assert False, "unprepared"
        return self.stack[-1]

    def visitLiveExpr(self, obj):
        # jit_debug("LiveExpr")
        # Ta-dah~
        return obj

    def visitExceptionExpr(self, exception):
        # jit_debug("ExceptionExpr")
        raise exception

    def visitNullExpr(self):
        # jit_debug("NullExpr")
        return NullObject

    def visitLocalExpr(self, name, idx):
        # jit_debug("LocalExpr %s" % name.encode("utf-8"))
        return self.locals[idx]

    def visitFrameExpr(self, name, idx):
        # jit_debug("FrameExpr %s" % name.encode("utf-8"))
        return self.frame[idx]

    # Length of args and namedArgs are fixed. ~ C.
    @unroll_safe
    def visitCallExpr(self, obj, atom, args, namedArgs):
        # jit_debug("CallExpr")
        rcvr = self.visitExpr(obj)
        argVals = [self.visitExpr(a) for a in args]
        if namedArgs:
            d = monteMap()
            for na in namedArgs:
                (k, v) = self.visitNamedArg(na)
                d[k] = v
            namedArgMap = ConstMap(d)
        else:
            namedArgMap = EMPTY_MAP
        return rcvr.callAtom(atom, argVals, namedArgMap)

    def visitDefExpr(self, patt, ex, rvalue):
        # jit_debug("DefExpr")
        ex = self.visitExpr(ex)
        val = self.visitExpr(rvalue)
        self.matchBind(patt, val, ex)
        return val

    def visitEscapeOnlyExpr(self, patt, body):
        # jit_debug("EscapeOnlyExpr")
        ej = Ejector()
        self.matchBind(patt, ej)
        try:
            val = self.visitExpr(body)
            ej.disable()
            return val
        except Ejecting as e:
            if e.ejector is not ej:
                raise
            ej.disable()
            return e.value

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody):
        # jit_debug("EscapeExpr")
        ej = Ejector()
        self.matchBind(patt, ej)
        try:
            val = self.visitExpr(body)
            ej.disable()
            return val
        except Ejecting as e:
            if e.ejector is not ej:
                raise
            ej.disable()
            self.matchBind(catchPatt, e.value)
            return self.visitExpr(catchBody)

    def visitFinallyExpr(self, body, atLast):
        # jit_debug("FinallyExpr")
        try:
            return self.visitExpr(body)
        finally:
            self.visitExpr(atLast)

    def visitIfExpr(self, test, cons, alt):
        # jit_debug("IfExpr")
        if unwrapBool(self.visitExpr(test)):
            return self.visitExpr(cons)
        else:
            return self.visitExpr(alt)

    def selfGuard(self, patt):
        if (isinstance(patt, self.src.FinalBindingPatt) or
            isinstance(patt, self.src.VarBindingPatt) or
            isinstance(patt, self.src.FinalSlotPatt) or
            isinstance(patt, self.src.VarSlotPatt)):
            if not isinstance(patt.guard, self.src.NullExpr):
                return self.visitExpr(patt.guard)
        return anyGuard

    def lookupBinding(self, scope, idx):
        if scope is SCOPE_LOCAL:
            return self.locals[idx]
        elif scope is SCOPE_FRAME:
            return self.frame[idx]
        else:
            assert False, "teacher"

    # Everything passed to this method, except self, is immutable. ~ C.
    @unroll_safe
    def visitClearObjectExpr(self, patt, script):
        # jit_debug("ClearObjectExpr")
        objName = script.name
        frameTable = script.layout.frameTable
        frame = [self.lookupBinding(scope, index) for (_, scope, index, _)
                 in frameTable.frameInfo]

        # Build the object.
        val = InterpObject(objName, script, frame, script.layout.fqn)

        # Check whether we have a spot in the frame.
        position = frameTable.positionOf(objName)

        # Set up the self-binding.
        selfGuard = self.selfGuard(patt)
        if isinstance(patt, self.src.IgnorePatt):
            b = NULL_BINDING
        elif isinstance(patt, self.src.FinalBindingPatt):
            b = finalBinding(val, selfGuard)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.VarBindingPatt):
            b = varBinding(val, selfGuard)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.FinalSlotPatt):
            b = FinalSlot(val, selfGuard)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.VarSlotPatt):
            b = VarSlot(val, selfGuard)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.NounPatt):
            b = val
            self.locals[patt.index] = b
        else:
            raise userError(u"Unsupported object pattern")

        # Assign to the frame.
        if position != -1:
            frame[position] = b
        return val

    # Everything passed to this method, except self and clipboard, are
    # immutable. Clipboards are not a problem since their loops are
    # internalized in methods. ~ C.
    @unroll_safe
    def visitObjectExpr(self, patt, guards, auditors, script, clipboard):
        # jit_debug("ObjectExpr")

        # Discover the object's common name and also find the
        # as-guard/auditor.
        # XXX In the future, we could erase the as-guard semantics earlier.
        guardAuditor = None
        objName = script.name
        if not isinstance(patt, self.src.IgnorePatt):
            # If there's a guard, use that as the as-guard.
            if not isinstance(patt.guard, self.src.NullExpr):
                guardAuditor = self.visitExpr(patt.guard)
        assert auditors, "hyacinth"
        if guardAuditor is None:
            guardAuditor = self.visitExpr(auditors[0])
            auds = [self.visitExpr(auditor) for auditor in auditors[1:]]
        else:
            auds = [self.visitExpr(auditor) for auditor in auditors]
        if guardAuditor is NullObject:
            guardAuditor = anyGuard
        else:
            auds = [guardAuditor] + auds
        frameTable = script.layout.frameTable
        frame = [self.lookupBinding(scope, index) for (_, scope, index, _)
                 in frameTable.frameInfo]
        # Set up guard information.
        guardInfo = GuardInfo(guards, frameTable, objName, guardAuditor,
                self.guardLookup)

        assert len(script.layout.frameNames) == len(frame), "shortcoming"

        o = InterpObject(objName, script, frame, script.layout.fqn)
        if auds and (len(auds) != 1 or auds[0] is not NullObject):
            # Actually perform the audit.
            o.report = clipboard.audit(auds, guardInfo)
        val = self.runGuard(guardAuditor, o, theThrower)

        # Check whether we have a spot in the frame.
        position = frameTable.positionOf(objName)

        # Set up the self-binding.
        if isinstance(patt, self.src.IgnorePatt):
            b = NULL_BINDING
        elif isinstance(patt, self.src.FinalBindingPatt):
            b = finalBinding(val, guardAuditor)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.VarBindingPatt):
            b = varBinding(val, guardAuditor)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.FinalSlotPatt):
            b = FinalSlot(val, guardAuditor)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.VarSlotPatt):
            b = VarSlot(val, guardAuditor)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.NounPatt):
            b = val
            self.locals[patt.index] = b
        else:
            raise userError(u"Unsupported object pattern")

        # Assign to the frame.
        if position != -1:
            frame[position] = b
        return val

    # Risky; we expect that the list of exprs is from a SeqExpr and that it's
    # immutable. ~ C.
    @unroll_safe
    def visitSeqExpr(self, exprs):
        # jit_debug("SeqExpr")
        result = NullObject
        for expr in exprs:
            result = self.visitExpr(expr)
        return result

    def visitTryExpr(self, body, catchPatt, catchBody):
        # jit_debug("TryExpr")
        try:
            return self.visitExpr(body)
        except UserException, ex:
            self.matchBind(catchPatt, sealException(ex))
            return self.visitExpr(catchBody)

    def visitIgnorePatt(self, guard):
        # jit_debug("IgnorePatt")
        if not isinstance(guard, self.src.NullExpr):
            g = self.visitExpr(guard)
            self.runGuard(g, self.specimen, self.patternFailure)

    def visitNounPatt(self, name, guard, index):
        # jit_debug("NounPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            val = self.specimen
        else:
            g = self.visitExpr(guard)
            val = self.runGuard(g, self.specimen, self.patternFailure)
        self.locals[index] = val

    def visitBindingPatt(self, name, index):
        # jit_debug("BindingPatt %s" % name.encode("utf-8"))
        self.locals[index] = self.specimen

    def visitFinalBindingPatt(self, name, guard, idx):
        # jit_debug("FinalBindingPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = finalBinding(val, guard)

    def visitFinalSlotPatt(self, name, guard, idx):
        # jit_debug("FinalSlotPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = FinalSlot(val, guard)

    def visitVarBindingPatt(self, name, guard, idx):
        # jit_debug("VarBindingPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = varBinding(val, guard)

    def visitVarSlotPatt(self, name, guard, idx):
        # jit_debug("VarSlotPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = VarSlot(val, guard)

    # The list of patts is immutable. ~ C.
    @unroll_safe
    def visitListPatt(self, patts):
        # jit_debug("ListPatt")
        listSpecimen = unwrapList(self.specimen, ej=self.patternFailure)
        ej = self.patternFailure
        if len(patts) != len(listSpecimen):
            throw(ej, StrObject(u"Failed list pattern (needed %d, got %d)" %
                                (len(patts), len(listSpecimen))))
        for i in range(len(patts)):
            self.matchBind(patts[i], listSpecimen[i], ej)

    def visitViaPatt(self, trans, patt, span):
        # jit_debug("ViaPatt")
        ej = self.patternFailure
        v = self.visitExpr(trans)
        newSpec = v.callAtom(RUN_2, [self.specimen, ej])
        self.matchBind(patt, newSpec, ej)

    def visitNamedArgExpr(self, key, value):
        return (self.visitExpr(key), self.visitExpr(value))


def scope2env(scope):
    environment = {}
    for k, v in scope.items():
        s = unwrapStr(k)
        if not s.startswith("&&") or not isinstance(v, Binding):
            raise userError(u"scope map must be of the "
                            "form '[\"&&name\" => binding]'")
        environment[s[2:]] = v
    return environment


def env2scope(outerNames, env):
    scope = []
    for name, (_, severity) in outerNames.iteritems():
        val = env[name]
        if severity is SEV_NOUN:
            val = val.call(u"get", []).call(u"get", [])
        elif severity is SEV_SLOT:
            val = val.call(u"get", [])
        scope.append(val)
    return scope


def evalMonte(expr, environment, fqnPrefix, inRepl=False):
    # Run the main nanopass pipeline.
    ast, outerNames, topLocalNames, localSize = mainPipeline(expr,
            environment.keys(), fqnPrefix, inRepl)

    outers = env2scope(outerNames, environment)
    ast = mix(ast, outers)
    ast, topFrame = makeBytecode(ast)
    ast = MakeProfileNames().visitExpr(ast)
    result = NullObject
    e = Evaluator(topFrame, [], localSize)
    result = e.visitExpr(ast)
    topLocals = []
    for i, (name, severity) in enumerate(topLocalNames):
        local = e.locals[i]
        if severity is SEV_NOUN:
            local = finalBinding(local, anyGuard)
        elif severity is SEV_SLOT:
            local = Binding(local, anyGuard)
        topLocals.append((name, local))
    return result, topLocals


def evalToPair(expr, scopeMap, inRepl=False):
    scope = unwrapMap(scopeMap)
    result, topLocals = evalMonte(expr, scope2env(scope), u"<eval>", inRepl)
    d = scope.copy()
    # XXX Future versions may choose to keep old env structures so that
    # debuggers can rewind and inspect bindings in old REPL lines.
    for name, val in topLocals:
        d[StrObject(u"&&" + name)] = val
    return result, ConstMap(d)
