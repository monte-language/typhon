from rpython.rlib.objectmodel import import_from_mixin

from typhon.atoms import getAtom
from typhon.errors import Ejecting, UserException, userError
from typhon.nano.mast import BuildKernelNodes, SaveScripts
from typhon.nano.scopes import (ReifyMetaIR, ReifyMeta, LayOutScopes,
                                SpecializeNouns)
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


class InterpMethod(object):
    def __init__(self, doc, verb, patts, namedPatts, guard, body, localSize):
        self.doc = doc
        self.verb = verb
        self.params = patts
        self.namedParams = namedPatts
        self.guard = guard
        self.body = body
        self.localSize = localSize


class InterpMatcher(object):
    def __init__(self, patt, body, localSize):
        self.pattern = patt
        self.body = body
        self.localSize = localSize


class InterpObject(Object):
    """
    An object whose script is executed by the AST evaluator.
    """
    import_from_mixin(AuditClipboard)
    import_from_mixin(UserObjectHelper)
    _immutable_fields_ = ("doc", "displayName", "methods[*]", "matchers[*]",
                          "outers", "report")

    def __init__(self, doc, name, methods, matchers, frame, outers,
                 guards, auditors, ast):
        self.reportCabinet = []
        self.fqn = u"LOL"
        self.objectAst = ast
        self.doc = doc
        self.displayName = name
        self.methods = methods
        self.matchers = matchers
        self.frame = frame
        self.outers = outers
        self.auditors = auditors
        if auditors:
            self.report = self.audit(auditors, guards)

    def docString(self):
        return self.doc

    def getDisplayName(self):
        return self.displayName

    def getMethod(self, atom):
        return self.methods.get(atom, None)

    def getMatchers(self):
        return self.matchers

    def respondingAtoms(self):
        d = {}
        for a, m in self.methods.iteritems():
            d[a] = m.doc
        return d

    def runMethod(self, method, args, namedArgs):
        e = Evaluator(self.frame, self.outers, method.localSize)
        if len(args) != len(method.params):
            raise userError(u"Method '%s.%s' expected %d args, got %d" % (
                self.getDisplayName(), method.verb, len(method.params),
                len(args)))
        for i in range(len(args)):
            e.matchBind(method.params[i], args[i], None)
        namedArgDict = unwrapMap(namedArgs)
        for np in method.namedParams:
            k = e.visitExpr(np.key)
            if k not in namedArgDict:
                raise userError(u"Named arg %s missing in call" % (
                    k.toString(),))
            if isinstance(np.default, ReifyMetaIR.NullExpr):
                e.matchBind(np.patt, namedArgDict[k], None)
            else:
                ej = Ejector()
                try:
                    e.matchBind(np.patt, namedArgDict[k], ej)
                except Ejecting, ee:
                    if ee.ejector is not ej:
                        raise
                    e.matchBind(np.patt, e.visitExpr(np.default), None)
        v = e.visitExpr(method.body)
        if method.guard is None:
            return v
        return e.runGuard(v, method.guard, None)

    def runMatcher(self, matcher, message, ej):
        e = Evaluator(self.frame, self.outers, matcher.localSize)
        e.matchBind(matcher.pattern, message, ej)


class Evaluator(ReifyMetaIR.makePassTo(None)):
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
        return guard.call(u"coerce", [specimen, ej])

    def visitNullExpr(self):
        return None

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
        s = self.locals[idx].slot
        s.call(u"put", [self.visitExpr(rvalue)])

    def visitFrameAssignExpr(self, name, idx, rvalue):
        s = self.frame[idx].slot
        s.call(u"put", [self.visitExpr(rvalue)])

    def visitOuterAssignExpr(self, name, idx, rvalue):
        s = self.outers[idx].slot
        s.call(u"put", [self.visitExpr(rvalue)])

    def visitLocalBindingExpr(self, name, index):
        return self.locals[index]

    def visitFrameBindingExpr(self, name, index):
        return self.frame[index]

    def visitOuterBindingExpr(self, name, index):
        return self.outers[index]

    def visitCallExpr(self, obj, verb, args, namedArgs):
        rcvr = self.visitExpr(obj)
        argVals = [self.visitExpr(a) for a in args]
        if namedArgs:
            d = monteMap()
            for na in namedArgs:
                (k, v) = self.visitNamedArg(na)
                d[k] = v
            namedArgMap = ConstMap(d)
        namedArgMap = EMPTY_MAP
        atom = getAtom(verb, len(argVals))
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
            self.visitExpr(body)
        except Ejecting:
            return NullObject

    def visitEscapeExpr(self, patt, body, catchPatt, catchBody):
        ej = Ejector()
        self.matchBind(patt, ej, None)
        try:
            return self.visitExpr(body)
        except Ejecting as e:
            if e.ejector is not ej:
                raise
            self.matchBind(catchPatt, e.value, None)
            return self.visitExpr(catchBody)

    def visitFinallyExpr(self, body, atLast):
        try:
            self.visitExpr(body)
        finally:
            self.visitExpr(atLast)

    def visitIfExpr(self, test, cons, alt):
        if unwrapBool(self.visitExpr(test)):
            return self.visitExpr(cons)
        else:
            return self.visitExpr(alt)

    def visitLocalNounExpr(self, name, index):
        return self.locals[index].slot.call(u"get", [])

    def visitFrameNounExpr(self, name, index):
        return self.frame[index].slot.call(u"get", [])

    def visitOuterNounExpr(self, name, index):
        return self.outers[index].slot.call(u"get", [])

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast,
                        layout):
        if isinstance(patt, ReifyMetaIR.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        frameItems = [(u"", "", 0, "")] * len(layout.frameNames)
        for n, (i, scope, idx, severity) in layout.frameNames.items():
            frameItems[i] = (n, scope, idx, severity)
        frame = []
        guards = {}
        for (name, scope, idx, severity) in frameItems:
            if name == objName:
                # deal with this later
                frame.append(NULL_BINDING)
            if scope == "local":
                frame.append(self.locals[idx])
                guards[name] = self.locals[idx].guard
            elif scope == "frame":
                frame.append(self.frame[idx])
                guards[name] = self.frame[idx].guard
        for (name, (idx, severity)) in layout.outerNames.items():
            # OuterNounExpr doesn't get rewritten to FrameNounExpr so no
            # need to put the binding in frame.
            guards[name] = self.outers[idx].guard
        ast = NullObject
        guardAuditor = anyGuard
        auds = []
        if auditors:
            guardAuditor = self.visitExpr(auditors[0])
            auds = [guardAuditor] + [self.visitExpr(auditor)
                                     for auditor in auditors[1:]]
            ast = BuildKernelNodes().visitExpr(mast)
        meths = {}
        for method in methods:
            name, m = self.visitMethod(method)
            meths[name] = m
        matchs = [self.visitMatcher(matcher) for matcher in matchers]
        o = InterpObject(doc, objName, meths, matchs, frame, self.outers,
                         guards, auds, ast)
        val = self.runGuard(o, guardAuditor, theThrower)
        if isinstance(patt, ReifyMetaIR.FinalPatt):
            b = finalBinding(val, guardAuditor)
        elif isinstance(patt, ReifyMetaIR.VarPatt):
            b = varBinding(val, guardAuditor)
        else:
            raise userError(u"Unsupported object pattern")
        selfLayout = layout.frameNames.get(objName, (0, None, 0, ""))
        if selfLayout[1] is not None:
            frame[selfLayout[2]] = b
        return val

    def visitSeqExpr(self, exprs):
        for expr in exprs:
            self.visitExpr(expr)

    def visitTryExpr(self, body, catchPatt, catchBody):
        try:
            return self.visitExpr(body)
        except UserException, ex:
            self.matchBind(catchPatt, sealException(ex), None)
            return self.visitExpr(catchBody)

    def visitIgnorePatt(self, guard):
        if not isinstance(guard, ReifyMetaIR.NullExpr):
            g = self.visitExpr(guard)
            self.runGuard(g, self.specimen, self.patternFailure)
        return NullObject

    def visitBindingPatt(self, name, index):
        b = self.specimen
        assert isinstance(b, Binding)
        self.locals[index] = b

    def visitFinalPatt(self, name, guard, idx):
        if isinstance(guard, ReifyMetaIR.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(self.specimen, guard, self.patternFailure)
        self.locals[idx] = finalBinding(val, guard)

    def visitVarPatt(self, name, guard, idx):
        if isinstance(guard, ReifyMetaIR.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(self.specimen, guard, self.patternFailure)
        self.locals[idx] = varBinding(val, guard)

    def visitListPatt(self, patts):
        listSpecimen = unwrapList(self.specimen)
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
        elif not isinstance(default, ReifyMetaIR.NullExpr):
            v = self.visitExpr(default)
        else:
            throw(self.patternFailure,
                  StrObject(u"Named arg %s missing in call" % (k.toString(),)))
        self.matchBind(patt, v, self.patternFailure)

    def visitMatcherExpr(self, patt, body, localSize):
        return InterpMatcher(patt, body, localSize)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        localSize):
        return (getAtom(verb, len(patts)),
                InterpMethod(doc, verb, patts, namedPatts,
                             self.visitExpr(guard),
                             body, localSize))


def evalMonte(expr, scopeMap):
    environment = {}
    scope = unwrapMap(scopeMap)
    for k, v in scope.items():
        s = unwrapStr(k)
        if not s.startswith("&&") or not isinstance(v, Binding):
            raise userError(u"scope map must be of the "
                            "form '[\"&&name\" => binding]'")
        environment[s[2:]] = v
    result = NullObject
    ss = SaveScripts().visitExpr(expr)
    ll = LayOutScopes(environment.keys()).visitExpr(ss)
    topLocalNames = ll.layout.collectTopLocals()
    sl = SpecializeNouns().visitExpr(ll)
    ml = ReifyMeta().visitExpr(sl)
    e = Evaluator([], environment.values(), len(topLocalNames))
    result = e.visitExpr(ml)
    d = monteMap()
    for i in range(len(topLocalNames)):
        d[StrObject(u"&&" + topLocalNames[i])] = e.locals[i]
    d.update(scope)
    return result, ConstMap(d)
