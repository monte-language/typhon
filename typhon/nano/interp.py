from rpython.rlib.debug import debug_print

from typhon.atoms import getAtom
from typhon.errors import Ejecting, UserException, userError
from typhon.nano.mast import BuildKernelNodes, SaveScripts
from typhon.nano.scopes import BoundNounsIR, LayOutScopes, SpecializeNouns
from typhon.objects.constants import NullObject
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import ConstMap, EMPTY_MAP, monteMap
from typhon.objects.constants import unwrapBool
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import anyGuard
from typhon.objects.slots import finalBinding, varBinding
from typhon.objects.user import AuditClipboard, UserObject

RUN_2 = getAtom(u"run", 2)


def mkMirandaArgs():
    _d = monteMap()
    _d[StrObject(u"FAIL")] = theThrower
    return ConstMap(_d)

MIRANDA_ARGS = mkMirandaArgs()


class InterpMethod(object):
    def __init__(self, doc, patts, namedPatts, guard, body):
        self.doc = doc
        self.params = patts
        self.namedParams = namedPatts
        self.guard = guard
        self.body = body


class InterpMatcher(object):
    def __init__(self, patt, body):
        self.pattern = patt
        self.body = body


class InterpObject(UserObject, AuditClipboard):
    """
    An object whose script is executed by the AST evaluator.
    """
    _immutable_fields_ = ("doc", "displayName", "methods[*]", "matchers[*]",
                          "outers", "report")

    def __init__(self, doc, name, methods, matchers, frame, outers,
                 guards, auditors, ast):
        AuditClipboard.__init__(self)
        self.fqn = "LOL"
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
        return self.methods.get(atom.verb)

    def getMatchers(self):
        return self.matchers

    def respondingAtoms(self):
        d = {}
        for a, m in self.methods.iteritems():
            d[a] = m.getDoc()
        return d

    def runMethod(self, method, args, namedArgs):
        e = Evaluator(self.frame, self.outers)
        if len(args) != len(method.params):
            raise userError(u"Method '%s.%s' expected %d args, got %d" % (
                self.getDisplayName(), method.name, len(method.params),
                len(args)))
        for (p, a) in zip(method.params, args):
            e.matchBind(p, a, theThrower)
        e.matchBind(method.namedParams, namedArgs)
        v = e.visitExpr(method.body)
        if method.guard is None:
            return v
        return self.runGuard(v, method.guard, theThrower)

    def runMatchers(self, matcher, message, ej):
        e = Evaluator(self.frame, self.outers)
        e.matchBind(matcher.pattern, message, ej)


class Evaluator(BoundNounsIR.makePassTo(None)):
    def __init__(self, frame, outers):
        self.locals = []
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
        self.locals[idx].slot.put(rvalue)

    def visitFrameAssignExpr(self, name, idx, rvalue):
        self.frame[idx].slot.put(rvalue)

    def visitOuterAssignExpr(self, name, idx, rvalue):
        self.outers[idx].slot.put(rvalue)

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
        return rcvr.recvNamed(verb, argVals, namedArgMap)

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
        return self.locals[index].slot.get()

    def visitFrameNounExpr(self, name, index):
        return self.frameslot.get()

    def visitOuterNounExpr(self, name, index):
        return self.outers[index].slot.get()

    def visitObjectExpr(self, doc, patt, auditors, methods, matchers, mast,
                        layout):
        if isinstance(patt, BoundNounsIR.IgnorePatt):
            objName = u"_"
        else:
            objName = patt.name
        frameItems = layout.frameNames.items().sort(key=lambda f: f[1][0])
        frame = []
        guards = {}
        for (name, (i, scope, idx, severity)) in frameItems:
            if name == objName:
                # deal with this later
                frame.append(None)
            if scope == "local":
                frame.append(self.locals[idx])
                guards[name] = self.locals[idx].getGuard()
            elif scope == "frame":
                frame.append(self.frame[idx])
                guards[name] = self.frame[idx].getGuard()
        for (name, (idx, severity)) in layout.outerNames.iteritems():
            # OuterNounExpr doesn't get rewritten to FrameNounExpr so no
            # need to put the binding in frame.
            guards[name] = self.outers[idx].getGuard()

        if not auditors:
            guardAuditor = anyGuard
            ast = None
        else:
            guardAuditor = self.visitExpr(auditors[0])
            auds = [guardAuditor] + [self.visitExpr(auditor)
                                     for auditor in auditors[1:]]
            ast = BuildKernelNodes().visit(mast)
        meths = dict([self.visitMethod(method) for method in methods])
        matchs = [self.visitMatcher(matcher) for matcher in matchers]
        o = InterpObject(doc, name, meths, matchs, frame, self.outers,
                         guards, auds, ast)
        val = self.runGuard(o, guardAuditor, theThrower)
        if isinstance(patt, BoundNounsIR.FinalPatt):
            b = finalBinding(val, guardAuditor)
        elif isinstance(patt, BoundNounsIR.VarPatt):
            b = varBinding(val, guardAuditor)
        selfLayout = layout.frameNames.get(objName)
        if selfLayout is not None:
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
        if not isinstance(guard, BoundNounsIR.NullExpr):
            g = self.visitExpr(guard)
            self.runGuard(g, self.specimen)
        return NullObject

    def visitBindingPatt(self, name, index):
        self.stack[0].locals[index] = self.specimen

    def visitFinalPatt(self, name, guard, idx):
        if isinstance(guard, BoundNounsIR.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(self.specimen, guard, self.patternFailure)
        self.stack[0].locals[idx] = finalBinding(val, guard)

    def visitVarPatt(self, name, guard, idx):
        if isinstance(guard, BoundNounsIR.NullExpr):
            guard = anyGuard
        else:
            guard = self.visitExpr(guard)
        val = self.runGuard(self.specimen, guard, self.patternFailure)
        self.stack[0].locals[idx] = varBinding(val, guard)

    def visitListPatt(self, patts):
        listSpecimen = unwrapList(self.specimen)
        ej = self.patternFailure
        if len(patts) != len(listSpecimen):
            throw(ej, StrObject(u"Failed list pattern (needed %d, got %d)" %
                                (len(patts), len(listSpecimen))))

        for (patt, item) in zip(patts, listSpecimen):
            self.matchBind(patt, item, ej)

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
        elif not isinstance(default, BoundNounsIR.NullExpr):
            v = self.visitExpr(default)
        else:
            throw(self.patternFailure,
                  StrObject(u"Named arg %s missing in call" % (k.toString(),)))
        self.matchBind(patt, v, self.patternFailure)

    def visitMatcherExpr(self, patt, body, layout):
        return InterpMatcher(patt, body)

    def visitMethodExpr(self, doc, verb, patts, namedPatts, guard, body,
                        layout):
        return verb, InterpMethod(doc, patts, namedPatts, guard, body)


def evalMonte(expr, scope):
    result = NullObject
    try:
        ss = SaveScripts().visitExpr(expr)
        ll = LayOutScopes(scope.keys()).visitExpr(ss)
        sl = SpecializeNouns().visitExpr(ll)
        result = Evaluator().visitExpr(sl)
    except UserException as ue:
            debug_print("Caught exception:", ue.formatError())
    return result
