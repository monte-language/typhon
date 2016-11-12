"""
A simple AST interpreter.
"""

from rpython.rlib import rvmprof
from rpython.rlib.jit import jit_debug, promote, unroll_safe, we_are_jitted
from rpython.rlib.objectmodel import import_from_mixin

from typhon.atoms import getAtom
from typhon.errors import Ejecting, UserException, userError
from typhon.nano.auditors import dischargeAuditors
from typhon.nano.escapes import elideEscapes
from typhon.nano.mast import saveScripts
from typhon.nano.mix import MixIR, mix
from typhon.nano.scopes import (SCOPE_FRAME, SCOPE_LOCAL,
                                SEV_BINDING, SEV_NOUN, SEV_SLOT, layoutScopes,
                                bindNouns)
from typhon.nano.slots import recoverSlots
from typhon.nano.structure import refactorStructure
from typhon.objects.constants import NullObject
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import (ConstMap, EMPTY_MAP, monteMap,
                                             unwrapMap)
from typhon.objects.constants import unwrapBool
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.root import Object
from typhon.objects.slots import (Binding, FinalSlot, VarSlot, finalBinding,
                                  varBinding)
from typhon.objects.user import UserObjectHelper
from typhon.profile import profileTyphon

RUN_2 = getAtom(u"run", 2)

NULL_BINDING = finalBinding(NullObject, anyGuard)


def mkMirandaArgs():
    _d = monteMap()
    _d[StrObject(u"FAIL")] = theThrower
    return ConstMap(_d)

MIRANDA_ARGS = mkMirandaArgs()


ProfileNameIR = MixIR.extend("ProfileName",
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

# super() doesn't work in RPython, so this is a way to get at the default
# implementations of the pass methods. ~ C.
_MakeProfileNames = MixIR.makePassTo(ProfileNameIR)
class MakeProfileNames(_MakeProfileNames):
    """
    Prebuild the strings which identify code objects to the profiler.

    This must be the last pass before evaluation, or else profiling will not
    work because the wrong objects will have been registered.
    """

    def __init__(self):
        # NB: self.objectNames cannot be empty unless we somehow obtain a
        # method/matcher without a body. ~ C.
        self.objectNames = []

    def visitClearObjectExpr(self, doc, patt, script, layout):
        # Push, do the recursion, pop.
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        self.objectNames.append((objName.encode("utf-8"),
            layout.fqn.encode("utf-8").split("$")[0]))
        rv = _MakeProfileNames.visitClearObjectExpr(self, doc, patt, script,
                                                    layout)
        self.objectNames.pop()
        return rv

    def visitObjectExpr(self, doc, patt, guards, auditors, script, mast,
                        layout, clipboard):
        # Push, do the recursion, pop.
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        self.objectNames.append((objName.encode("utf-8"),
            layout.fqn.encode("utf-8").split("$")[0]))
        rv = _MakeProfileNames.visitObjectExpr(self, doc, patt, guards,
                                               auditors, script, mast, layout,
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

    import_from_mixin(UserObjectHelper)

    _immutable_fields_ = "doc", "displayName", "script", "report"

    # Inline single-entry method cache.
    cachedMethod = None, None

    def __init__(self, doc, name, script, frame, ast, fqn):
        self.objectAst = ast
        self.fqn = fqn
        self.doc = doc
        self.displayName = name
        self.script = script
        self.frame = frame

        self.report = None

    def docString(self):
        return self.doc

    def getDisplayName(self):
        return self.displayName

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

    def getMatchers(self):
        return promote(self.script).matchers

    def respondingAtoms(self):
        d = {}
        for method in self.script.methods:
            d[method.atom] = method.doc
        return d

    # Two loops, both of which loop over greens. ~ C.
    @rvmprof.vmprof_execute_code("method",
            lambda self, method, args, namedArgs: method,
            result_class=Object)
    @unroll_safe
    def runMethod(self, method, args, namedArgs):
        e = Evaluator(self.frame, method.localSize)
        if len(args) != len(method.patts):
            raise userError(u"Method '%s.%s' expected %d args, got %d" % (
                self.getDisplayName(), method.atom.verb, len(method.patts),
                len(args)))
        for i in range(len(method.patts)):
            e.matchBind(method.patts[i], args[i])
        namedArgDict = unwrapMap(namedArgs)
        for np in method.namedPatts:
            k = e.visitExpr(np.key)
            if isinstance(np.default, ProfileNameIR.NullExpr):
                if k not in namedArgDict:
                    raise userError(u"Named arg %s missing in call" % (
                        k.toString(),))
                e.matchBind(np.patt, namedArgDict[k])
            elif k not in namedArgDict:
                e.matchBind(np.patt, e.visitExpr(np.default))
            else:
                e.matchBind(np.patt, namedArgDict[k])
        resultGuard = e.visitExpr(method.guard)
        v = e.visitExpr(method.body)
        if resultGuard is NullObject:
            return v
        return e.runGuard(resultGuard, v, None)

    @rvmprof.vmprof_execute_code("matcher",
            lambda self, matcher, message, ej: matcher,
            result_class=Object)
    def runMatcher(self, matcher, message, ej):
        e = Evaluator(self.frame, matcher.localSize)
        e.matchBind(matcher.patt, message, ej)
        return e.visitExpr(matcher.body)


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


class Evaluator(ProfileNameIR.makePassTo(None)):

    def __init__(self, frame, localSize):
        self.locals = [NULL_BINDING] * localSize
        self.frame = frame
        self.specimen = None
        self.patternFailure = None

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

    def visitLiveExpr(self, obj):
        jit_debug("LiveExpr")
        # Ta-dah~
        return obj

    def visitExceptionExpr(self, exception):
        jit_debug("ExceptionExpr")
        raise exception

    def visitNullExpr(self):
        jit_debug("NullExpr")
        return NullObject

    def visitLocalExpr(self, name, idx):
        jit_debug("LocalExpr %s" % name.encode("utf-8"))
        return self.locals[idx]

    def visitFrameExpr(self, name, idx):
        jit_debug("FrameExpr %s" % name.encode("utf-8"))
        return self.frame[idx]

    # Length of args and namedArgs are fixed. ~ C.
    @unroll_safe
    def visitCallExpr(self, obj, atom, args, namedArgs):
        jit_debug("CallExpr")
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
        return rcvr.recvNamed(atom, argVals, namedArgMap)

    def visitDefExpr(self, patt, ex, rvalue):
        jit_debug("DefExpr")
        ex = self.visitExpr(ex)
        val = self.visitExpr(rvalue)
        self.matchBind(patt, val, ex)
        return val

    def visitEscapeOnlyExpr(self, patt, body):
        jit_debug("EscapeOnlyExpr")
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
        jit_debug("EscapeExpr")
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
        jit_debug("FinallyExpr")
        try:
            return self.visitExpr(body)
        finally:
            self.visitExpr(atLast)

    def visitIfExpr(self, test, cons, alt):
        jit_debug("IfExpr")
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
    def visitClearObjectExpr(self, doc, patt, script, layout):
        jit_debug("ClearObjectExpr")
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        ast = NullObject
        frameTable = layout.frameTable
        frame = [self.lookupBinding(scope, index) for (_, scope, index, _)
                 in frameTable.frameInfo]

        # Build the object.
        val = InterpObject(doc, objName, script, frame, ast, layout.fqn)

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
    def visitObjectExpr(self, doc, patt, guards, auditors, script, mast,
                        layout, clipboard):
        jit_debug("ObjectExpr")
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        assert auditors, "hyacinth"
        guardAuditor = self.visitExpr(auditors[0])
        auds = [self.visitExpr(auditor) for auditor in auditors[1:]]
        if guardAuditor is NullObject:
            guardAuditor = anyGuard
        else:
            auds = [guardAuditor] + auds
        frameTable = layout.frameTable
        frame = [self.lookupBinding(scope, index) for (_, scope, index, _)
                 in frameTable.frameInfo]
        # Grab any remaining dynamic guards. We use a copy here in order to
        # preserve the original dict for reuse.
        guards = guards.copy()
        for name, index in frameTable.dynamicGuards.items():
            if name == objName:
                guards[name] = guardAuditor
            else:
                _, scope, idx, severity = frameTable.frameInfo[index]
                guards[name] = retrieveGuard(severity,
                        self.lookupBinding(scope, idx))

        assert len(layout.frameNames) == len(frame), "shortcoming"

        o = InterpObject(doc, objName, script, frame,  mast, layout.fqn)
        if auds and (len(auds) != 1 or auds[0] is not NullObject):
            # Actually perform the audit.
            o.report = clipboard.audit(auds, guards)
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
        jit_debug("SeqExpr")
        result = NullObject
        for expr in exprs:
            result = self.visitExpr(expr)
        return result

    def visitTryExpr(self, body, catchPatt, catchBody):
        jit_debug("TryExpr")
        try:
            return self.visitExpr(body)
        except UserException, ex:
            self.matchBind(catchPatt, sealException(ex))
            return self.visitExpr(catchBody)

    def visitIgnorePatt(self, guard):
        jit_debug("IgnorePatt")
        if not isinstance(guard, self.src.NullExpr):
            g = self.visitExpr(guard)
            self.runGuard(g, self.specimen, self.patternFailure)

    def visitNounPatt(self, name, guard, index):
        jit_debug("NounPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            val = self.specimen
        else:
            g = self.visitExpr(guard)
            val = self.runGuard(g, self.specimen, self.patternFailure)
        self.locals[index] = val

    def visitBindingPatt(self, name, index):
        jit_debug("BindingPatt %s" % name.encode("utf-8"))
        self.locals[index] = self.specimen

    def visitFinalBindingPatt(self, name, guard, idx):
        jit_debug("FinalBindingPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = finalBinding(val, guard)

    def visitFinalSlotPatt(self, name, guard, idx):
        jit_debug("FinalSlotPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = FinalSlot(val, guard)

    def visitVarBindingPatt(self, name, guard, idx):
        jit_debug("VarBindingPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = varBinding(val, guard)

    def visitVarSlotPatt(self, name, guard, idx):
        jit_debug("VarSlotPatt %s" % name.encode("utf-8"))
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = VarSlot(val, guard)

    # The list of patts is immutable. ~ C.
    @unroll_safe
    def visitListPatt(self, patts):
        jit_debug("ListPatt")
        listSpecimen = unwrapList(self.specimen, ej=self.patternFailure)
        ej = self.patternFailure
        if len(patts) != len(listSpecimen):
            throw(ej, StrObject(u"Failed list pattern (needed %d, got %d)" %
                                (len(patts), len(listSpecimen))))
        for i in range(len(patts)):
            self.matchBind(patts[i], listSpecimen[i], ej)

    def visitViaPatt(self, trans, patt):
        jit_debug("ViaPatt")
        ej = self.patternFailure
        v = self.visitExpr(trans)
        newSpec = v.callAtom(RUN_2, [self.specimen, ej], MIRANDA_ARGS)
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
    ss = saveScripts(expr)
    slotted = recoverSlots(ss)
    ll, outerNames, topLocalNames, localSize = layoutScopes(slotted,
            environment.keys(), fqnPrefix, inRepl)
    bound = bindNouns(ll)
    ast = elideEscapes(bound)
    ast = dischargeAuditors(ast)
    ast = refactorStructure(ast)
    outers = env2scope(outerNames, environment)
    ast = mix(ast, outers)
    ast = MakeProfileNames().visitExpr(ast)
    result = NullObject
    e = Evaluator([], localSize)
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
