"""
A simple AST interpreter.
"""

from rpython.rlib import rvmprof
from rpython.rlib.jit import promote, unroll_safe, we_are_jitted
from rpython.rlib.objectmodel import import_from_mixin

from typhon.atoms import getAtom
from typhon.errors import Ejecting, UserException, userError
from typhon.nano.mast import BuildKernelNodes, SaveScripts
from typhon.nano.scopes import ReifyMeta, LayOutScopes, SpecializeNouns
from typhon.nano.structure import ProfileNameIR, refactorStructure
from typhon.objects.constants import NullObject
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import (ConstMap, EMPTY_MAP, monteMap,
                                             unwrapMap)
from typhon.objects.constants import unwrapBool
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject, unwrapStr)
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import anyGuard
from typhon.objects.root import Object
from typhon.objects.slots import Binding, finalBinding, varBinding
from typhon.objects.user import AuditClipboard, UserObjectHelper

RUN_2 = getAtom(u"run", 2)

NULL_BINDING = finalBinding(NullObject, anyGuard)


def mkMirandaArgs():
    _d = monteMap()
    _d[StrObject(u"FAIL")] = theThrower
    return ConstMap(_d)

MIRANDA_ARGS = mkMirandaArgs()


class InterpObject(Object):
    """
    An object whose script is executed by the AST evaluator.
    """
    import_from_mixin(AuditClipboard)
    import_from_mixin(UserObjectHelper)

    _immutable_fields_ = "doc", "displayName", "script", "outers", "report"

    # Inline single-entry method cache.
    cachedMethod = None, None

    def __init__(self, doc, name, script, frame, outers,
                 guards, auditors, ast, fqn):
        self.reportCabinet = []
        self.objectAst = ast
        self.fqn = fqn
        self.doc = doc
        self.displayName = name
        self.script = script
        self.frame = frame
        self.outers = outers
        self.auditors = auditors
        self.report = None
        if auditors and auditors != [NullObject]:
            self.report = self.audit(auditors, guards)

    def docString(self):
        return self.doc

    def getDisplayName(self):
        return self.displayName

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
        e = Evaluator(self.frame, self.outers, method.localSize)
        if len(args) != len(method.patts):
            raise userError(u"Method '%s.%s' expected %d args, got %d" % (
                self.getDisplayName(), method.atom.verb, len(method.patts),
                len(args)))
        for i in range(len(method.patts)):
            e.matchBind(method.patts[i], args[i], None)
        namedArgDict = unwrapMap(namedArgs)
        for np in method.namedPatts:
            k = e.visitExpr(np.key)
            if isinstance(np.default, ProfileNameIR.NullExpr):
                if k not in namedArgDict:
                    raise userError(u"Named arg %s missing in call" % (
                        k.toString(),))
                e.matchBind(np.patt, namedArgDict[k], None)
            elif k not in namedArgDict:
                e.matchBind(np.patt, e.visitExpr(np.default), None)
            else:
                e.matchBind(np.patt, namedArgDict[k], None)
        resultGuard = e.visitExpr(method.guard)
        v = e.visitExpr(method.body)
        if resultGuard is NullObject:
            return v
        return e.runGuard(resultGuard, v, None)

    @rvmprof.vmprof_execute_code("matcher",
            lambda self, matcher, message, ej: matcher,
            result_class=Object)
    def runMatcher(self, matcher, message, ej):
        e = Evaluator(self.frame, self.outers, matcher.localSize)
        e.matchBind(matcher.patt, message, ej)
        return e.visitExpr(matcher.body)


class Evaluator(ProfileNameIR.makePassTo(None)):
    def __init__(self, frame, outers, localSize):
        self.locals = [NULL_BINDING] * localSize
        self.frame = frame
        self.outers = outers
        self.specimen = None
        self.patternFailure = None

    def matchBind(self, patt, val, ej):
        oldSpecimen = self.specimen
        oldPatternFailure = self.patternFailure
        if ej is None:
            ej = theThrower
        self.specimen = val
        self.patternFailure = ej
        self.visitPatt(patt)
        self.specimen = oldSpecimen
        self.patternFailure = oldPatternFailure

    def runGuard(self, guard, specimen, ej):
        if ej is None:
            ej = theThrower
        return guard.call(u"coerce", [specimen, ej])

    def visitNullExpr(self):
        return NullObject

    def visitCharExpr(self, c):
        return CharObject(c)

    def visitDoubleExpr(self, d):
        return DoubleObject(d)

    def visitIntExpr(self, i):
        try:
            return IntObject(i.toint())
        except OverflowError:
            return BigInt(i)

    def visitStrExpr(self, s):
        return StrObject(s)

    def visitLocalAssignExpr(self, name, idx, rvalue):
        b = self.locals[idx]
        assert isinstance(b, Binding)
        v = self.visitExpr(rvalue)
        b.slot.call(u"put", [v])
        return v

    def visitFrameAssignExpr(self, name, idx, rvalue):
        b = self.frame[idx]
        assert isinstance(b, Binding)
        v = self.visitExpr(rvalue)
        b.slot.call(u"put", [v])
        return v

    def visitOuterAssignExpr(self, name, idx, rvalue):
        b = self.outers[idx]
        assert isinstance(b, Binding)
        v = self.visitExpr(rvalue)
        b.call(u"put", [v])
        return v

    def visitLocalBindingExpr(self, name, index):
        return self.locals[index]

    def visitFrameBindingExpr(self, name, index):
        return self.frame[index]

    def visitOuterBindingExpr(self, name, index):
        return self.outers[index]

    # Length of args and namedArgs are fixed. ~ C.
    @unroll_safe
    def visitCallExpr(self, obj, atom, args, namedArgs):
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
        ex = self.visitExpr(ex)
        val = self.visitExpr(rvalue)
        self.matchBind(patt, val, ex)
        return val

    def visitEscapeOnlyExpr(self, patt, body):
        ej = Ejector()
        self.matchBind(patt, ej, None)
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
        ej = Ejector()
        self.matchBind(patt, ej, None)
        try:
            val = self.visitExpr(body)
            ej.disable()
            return val
        except Ejecting as e:
            if e.ejector is not ej:
                raise
            ej.disable()
            self.matchBind(catchPatt, e.value, None)
            return self.visitExpr(catchBody)


    def visitFinallyExpr(self, body, atLast):
        try:
            return self.visitExpr(body)
        finally:
            self.visitExpr(atLast)

    def visitIfExpr(self, test, cons, alt):
        if unwrapBool(self.visitExpr(test)):
            return self.visitExpr(cons)
        else:
            return self.visitExpr(alt)

    def visitLocalNounExpr(self, name, index):
        b = self.locals[index]
        assert isinstance(b, Binding)
        return b.slot.call(u"get", [])

    def visitFrameNounExpr(self, name, index):
        b = self.frame[index]
        assert isinstance(b, Binding)
        return b.slot.call(u"get", [])

    def visitOuterNounExpr(self, name, index):
        b = self.outers[index]
        assert isinstance(b, Binding)
        return b.slot.call(u"get", [])

    def visitObjectExpr(self, doc, patt, auditors, script, mast, layout):
        if isinstance(patt, self.src.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        ast = NullObject
        auds = []
        guardAuditor = anyGuard
        if auditors:
            guardAuditor = self.visitExpr(auditors[0])
            auds = [self.visitExpr(auditor) for auditor in auditors[1:]]
            if guardAuditor is not NullObject:
                auds = [guardAuditor] + auds
            else:
                guardAuditor = anyGuard
            if auds:
                ast = BuildKernelNodes().visitExpr(mast)
        frameItems = [(u"", "", 0, "")] * len(layout.frameNames)
        for n, (i, scope, idx, severity) in layout.frameNames.items():
            frameItems[i] = (n, scope, idx, severity)
        frame = []
        guards = {}
        for (name, scope, idx, severity) in frameItems:
            if name == objName:
                # deal with this later
                frame.append(NULL_BINDING)
                guards[name] = guardAuditor
            elif scope == "local":
                b = self.locals[idx]
                assert isinstance(b, Binding)
                frame.append(b)
                guards[name] = b.guard
            elif scope == "frame":
                b = self.frame[idx]
                assert isinstance(b, Binding)
                frame.append(b)
                guards[name] = b.guard
        for (name, (idx, severity)) in layout.outerNames.items():
            # OuterNounExpr doesn't get rewritten to FrameNounExpr so no
            # need to put the binding in frame.
            b = self.outers[idx]
            assert isinstance(b, Binding)
            guards[name] = b.guard
        o = InterpObject(doc, objName, script, frame, self.outers,
                         guards, auds, ast, layout.fqn)
        val = self.runGuard(guardAuditor, o, theThrower)
        if isinstance(patt, self.src.IgnorePatt):
            b = NULL_BINDING
        elif isinstance(patt, self.src.FinalPatt):
            b = finalBinding(val, guardAuditor)
            self.locals[patt.index] = b
        elif isinstance(patt, self.src.VarPatt):
            b = varBinding(val, guardAuditor)
            self.locals[patt.index] = b
        else:
            raise userError(u"Unsupported object pattern")
        selfLayout = layout.frameNames.get(objName, (0, None, 0, ""))
        if selfLayout[1] is not None:
            frame[selfLayout[0]] = b
        return val

    # Risky; we expect that the list of exprs is from a SeqExpr and that it's
    # immutable. ~ C.
    @unroll_safe
    def visitSeqExpr(self, exprs):
        result = NullObject
        for expr in exprs:
            result = self.visitExpr(expr)
        return result

    def visitTryExpr(self, body, catchPatt, catchBody):
        try:
            return self.visitExpr(body)
        except UserException, ex:
            self.matchBind(catchPatt, sealException(ex), None)
            return self.visitExpr(catchBody)

    def visitIgnorePatt(self, guard):
        if not isinstance(guard, self.src.NullExpr):
            g = self.visitExpr(guard)
            self.runGuard(g, self.specimen, self.patternFailure)

    def visitBindingPatt(self, name, index):
        b = self.specimen
        assert isinstance(b, Binding)
        self.locals[index] = b

    def visitFinalPatt(self, name, guard, idx):
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = finalBinding(val, guard)

    def visitVarPatt(self, name, guard, idx):
        if isinstance(guard, self.src.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(guard, self.specimen, self.patternFailure)
        self.locals[idx] = varBinding(val, guard)

    def visitListPatt(self, patts):
        listSpecimen = unwrapList(self.specimen, ej=self.patternFailure)
        ej = self.patternFailure
        if len(patts) != len(listSpecimen):
            throw(ej, StrObject(u"Failed list pattern (needed %d, got %d)" %
                                (len(patts), len(listSpecimen))))
        for i in range(len(patts)):
            self.matchBind(patts[i], listSpecimen[i], ej)

    def visitViaPatt(self, trans, patt):
        ej = self.patternFailure
        v = self.visitExpr(trans)
        newSpec = v.callAtom(RUN_2, [self.specimen, ej], MIRANDA_ARGS)
        self.matchBind(patt, newSpec, ej)

    def visitNamedArgExpr(self, key, value):
        return (self.visitExpr(key), self.visitExpr(value))

    def visitNamedPattern(self, key, patt, default):
        namedArgs = self.specimen
        assert isinstance(namedArgs, ConstMap)
        k = self.visitExpr(key)
        if k in namedArgs:
            v = namedArgs.objectMap[k]
        elif not isinstance(default, self.src.NullExpr):
            v = self.visitExpr(default)
        else:
            throw(self.patternFailure,
                  StrObject(u"Named arg %s missing in call" % (k.toString(),)))
        self.matchBind(patt, v, self.patternFailure)


def scope2env(scope):
    environment = {}
    for k, v in scope.items():
        s = unwrapStr(k)
        if not s.startswith("&&") or not isinstance(v, Binding):
            raise userError(u"scope map must be of the "
                            "form '[\"&&name\" => binding]'")
        environment[s[2:]] = v
    return environment


def evalMonte(expr, environment, fqnPrefix, inRepl=False):
    ss = SaveScripts().visitExpr(expr)
    lo = LayOutScopes(environment.keys(), fqnPrefix, inRepl)
    ll = lo.visitExpr(ss)
    topLocalNames, localSize = lo.top.collectTopLocals()
    sl = SpecializeNouns().visitExpr(ll)
    ml = ReifyMeta().visitExpr(sl)
    finalAST = refactorStructure(ml)
    result = NullObject
    e = Evaluator([], environment.values(), localSize)
    result = e.visitExpr(finalAST)
    topLocals = []
    for i in range(len(topLocalNames)):
        topLocals.append((topLocalNames[i], e.locals[i]))
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
