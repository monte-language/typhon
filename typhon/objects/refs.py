# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import weakref

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.enum import makeEnum
from typhon.errors import Refused, UserException, userError
from typhon.log import log
from typhon.objects.auditors import deepFrozenStamp, selfless
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.data import StrObject
from typhon.objects.root import Object, audited
from typhon.vats import currentVat


BROKEN, EVENTUAL, NEAR = makeEnum(u"RefState",
                                  u"broken eventual near".split())

BROKEN_1 = getAtom(u"broken", 1)
FULFILLMENT_1 = getAtom(u"fulfillment", 1)
ISBROKEN_1 = getAtom(u"isBroken", 1)
ISDEEPFROZEN_1 = getAtom(u"isDeepFrozen", 1)
ISEVENTUAL_1 = getAtom(u"isEventual", 1)
ISFAR_1 = getAtom(u"isFar", 1)
ISNEAR_1 = getAtom(u"isNear", 1)
ISRESOLVED_1 = getAtom(u"isResolved", 1)
ISSELFISH_1 = getAtom(u"isSelfish", 1)
ISSELFLESS_1 = getAtom(u"isSelfless", 1)
ISSETTLED_1 = getAtom(u"isSettled", 1)
MAKEPROXY_3 = getAtom(u"makeProxy", 3)
OPTPROBLEM_1 = getAtom(u"optProblem", 1)
PROMISE_0 = getAtom(u"promise", 0)
RESOLVE_1 = getAtom(u"resolve", 1)
RESOLVE_2 = getAtom(u"resolve", 2)
RUN_1 = getAtom(u"run", 1)
SMASH_1 = getAtom(u"smash", 1)
STATE_1 = getAtom(u"state", 1)
WHENBROKEN_2 = getAtom(u"whenBroken", 2)
WHENRESOLVED_2 = getAtom(u"whenResolved", 2)
WHENRESOLVEDONLY_2 = getAtom(u"whenResolvedOnly", 2)
_PRINTON_1 = getAtom(u"_printOn", 1)
_WHENBROKEN_1 = getAtom(u"_whenBroken", 1)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


def makePromise():
    vat = currentVat.get()
    buf = MessageBuffer(vat)
    sref = SwitchableRef(BufferingRef(buf))
    return sref, LocalResolver(sref, buf, vat)


def _toRef(o, vat):
    if isinstance(o, Promise):
        return o
    return NearRef(o, vat)


def resolution(o):
    if isinstance(o, Promise):
        return o.resolution()
    return o


def isResolved(o):
    if isinstance(o, Promise):
        return o.isResolved()
    else:
        return True


def isBroken(o):
    if isinstance(o, Promise):
        return o.state() is BROKEN
    else:
        return False


@autohelp
@audited.DF
class RefOps(Object):
    """
    Ref management and utilities.
    """

    def toString(self):
        return u"<Ref>"

    def recv(self, atom, args):
        if atom is BROKEN_1:
            return self.broken(args[0])

        if atom is FULFILLMENT_1:
            return self.fulfillment(args[0])

        if atom is ISBROKEN_1:
            return wrapBool(self.isBroken(args[0]))

        if atom is ISDEEPFROZEN_1:
            return wrapBool(self.isDeepFrozen(args[0]))

        if atom is ISEVENTUAL_1:
            return wrapBool(self.isEventual(args[0]))

        if atom is ISNEAR_1:
            return wrapBool(self.isNear(args[0]))

        if atom is ISFAR_1:
            return wrapBool(self.isFar(args[0]))

        if atom is ISRESOLVED_1:
            return wrapBool(isResolved(args[0]))

        if atom is ISSELFISH_1:
            return wrapBool(self.isSelfish(args[0]))

        if atom is ISSELFLESS_1:
            return wrapBool(self.isSelfless(args[0]))

        if atom is ISSETTLED_1:
            return wrapBool(args[0].isSettled())

        if atom is MAKEPROXY_3:
            from typhon.objects.proxy import makeProxy
            return makeProxy(args[0], args[1], args[2])

        if atom is OPTPROBLEM_1:
            ref = args[0]
            if isinstance(ref, Promise):
                return ref.optProblem()
            return NullObject

        if atom is PROMISE_0:
            return self.promise()

        # Inlined for name clash reasons.
        if atom is STATE_1:
            o = args[0]
            if isinstance(o, Promise):
                s = o.state()
            else:
                s = NEAR
            return StrObject(s.repr)

        if atom is WHENBROKEN_2:
            return self.whenBroken(args[0], args[1])

        if atom is WHENRESOLVED_2:
            return self.whenResolved(args[0], args[1])

        if atom is WHENRESOLVEDONLY_2:
            return self.whenResolvedOnly(args[0], args[1])

        raise Refused(self, atom, args)

    def promise(self):
        from typhon.objects.collections.lists import wrapList
        p, r = makePromise()
        return wrapList([p, r])

    def broken(self, problem):
        return UnconnectedRef(problem)

    def optBroken(self, optProblem):
        if optProblem is NullObject:
            return NullObject
        else:
            return self.broken(optProblem)

    def isNear(self, ref):
        if isinstance(ref, Promise):
            return ref.state() is NEAR
        else:
            return True

    def isEventual(self, ref):
        if isinstance(ref, Promise):
            return ref.state() is EVENTUAL
        else:
            return False

    def isBroken(self, ref):
        return isBroken(ref)

    def fulfillment(self, ref):
        ref = resolution(ref)
        if isResolved(ref):
            if isBroken(ref):
                raise UserException(ref.optProblem())
            return ref
        else:
            raise RuntimeError("Not resolved: %r" % (ref,))

    def isFar(self, ref):
        return self.isEventual(ref) and isResolved(ref)

    def whenResolved(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    def whenResolvedOnly(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, o, None, vat)],
                     EMPTY_MAP)
        return NullObject

    def whenBroken(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenBrokenReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    def whenBrokenOnly(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        return vat.sendOnly(o, _WHENMORERESOLVED_1,
                            [WhenBrokenReactor(callback, o, None, vat)],
                            EMPTY_MAP)

    def isDeepFrozen(self, o):
        return o.auditedBy(deepFrozenStamp)

    def isSelfless(self, o):
        return o.auditedBy(selfless)

    def isSelfish(self, o):
        return self.isNear(o) and not self.isSelfless(o)


@autohelp
class WhenBrokenReactor(Object):

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<whenBrokenReactor>"

    def recv(self, atom, args):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is RUN_1:
            if not isinstance(self._ref, Promise):
                return NullObject

            if self._ref.state() is EVENTUAL:
                self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                                  EMPTY_MAP)
            elif self._ref.state() is BROKEN:
                # XXX this could raise; we might need to reflect to user
                outcome = self._cb.call(u"run", [self._ref])

                if self._resolver is not None:
                    self._resolver.resolve(outcome)

            return NullObject
        raise Refused(self, atom, args)


@autohelp
class WhenResolvedReactor(Object):

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = _toRef(ref, vat)
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<whenResolvedReactor>"

    def recv(self, atom, args):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is RUN_1:
            if self.done:
                return NullObject

            if self._ref.isResolved():
                # XXX should reflect to user if exception?
                outcome = self._cb.call(u"run", [self._ref])

                if self._resolver is not None:
                    self._resolver.resolve(outcome)

                self.done = True
            else:
                self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                                  EMPTY_MAP)

            return NullObject
        raise Refused(self, atom, args)


@autohelp
class LocalResolver(Object):

    def __init__(self, ref, buf, vat):
        assert vat is not None, "Vat cannot be None"
        self._ref = ref
        self._buf = buf
        self.vat = vat

    def toString(self):
        if self._ref is None:
            return u"<closed resolver>"
        else:
            return u"<resolver>"

    def recv(self, atom, args):
        if atom is RESOLVE_1:
            return wrapBool(self.resolve(args[0]))

        if atom is RESOLVE_2:
            return wrapBool(self.resolve(args[0], unwrapBool(args[1])))

        if atom is SMASH_1:
            return wrapBool(self.smash(args[0]))

        raise Refused(self, atom, args)

    def resolve(self, target, strict=True):
        if self._ref is None:
            if strict:
                raise userError(u"Already resolved")
            return False
        else:
            self._ref.setTarget(_toRef(target, self.vat))
            self._ref.commit()
            self._buf.deliverAll(target)

            self._ref = None
            self._buf = None
            return True

    def resolveRace(self, target):
        return self.resolve(target, False)

    def smash(self, problem):
        return self.resolve(UnconnectedRef(problem), False)

    def isDone(self):
        return wrapBool(self._ref is None)


class MessageBuffer(object):

    def __init__(self, vat):
        self.vat = vat

        self._buf = []

    def enqueue(self, resolver, atom, args, namedArgs):
        self._buf.append((resolver, atom, args, namedArgs))

    def deliverAll(self, target):
        #XXX record sending-context information for causality tracing
        targRef = _toRef(target, self.vat)
        for resolver, atom, args, namedArgs in self._buf:
            if resolver is None:
                targRef.sendAllOnly(atom, args, namedArgs)
            else:
                result = targRef.sendAll(atom, args, namedArgs)
                resolver.resolve(result)
        rv = len(self._buf)
        self._buf = []
        return rv


@autohelp
class Promise(Object):
    """
    A promised reference.

    All methods on this class are helpers; this class cannot be instantiated
    directly.
    """

    # Monte core.

    def isSettled(self, sofar=None):
        # Strangely, we cannot be part of the looping problem here!
        return self.isResolved()

    def recv(self, atom, args):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is _WHENMORERESOLVED_1:
            return self._whenMoreResolved(args[0])

        return self.callAll(atom, args, EMPTY_MAP)

    def _whenMoreResolved(self, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        # Welcome to _whenMoreResolved.
        # This method's implementation, in Monte, should be:
        # to _whenMoreResolved(callback): callback<-(self)
        vat = currentVat.get()
        vat.sendOnly(callback, RUN_1, [self], EMPTY_MAP)
        return NullObject

    # Eventual sends.

    def send(self, atom, args, namedArgs):
        # Resolution is done by the vat here; we don't get to access the
        # resolver ourselves.
        return self.sendAll(atom, args, namedArgs)

    def sendOnly(self, atom, args, namedArgs):
        self.sendAllOnly(atom, args, namedArgs)
        return NullObject

    # Promise API.

    def resolutionRef(self):
        return self

    def resolution(self):
        result = self.resolutionRef()
        if self is result:
            return result
        else:
            return result.resolution()

    def state(self):
        if self.optProblem() is not NullObject:
            return BROKEN
        target = self.resolutionRef()
        if self is target:
            return EVENTUAL
        else:
            return target.state()


class SwitchableRef(Promise):
    """
    Starts out pointing to one promise and switches to another later.
    """

    isSwitchable = True

    def __init__(self, target):
        self._target = target

    def toString(self):
        if self.isSwitchable:
            # NB: This should be an exceptional state, but some stuff in our
            # stack can't handle it yet. ~ C.
            return u"<unsafely-printed promise>"
        else:
            self.resolutionRef()
            return self._target.toString()

    def computeHash(self, depth):
        if self.isSwitchable:
            raise userError(u"Unsettled promise is not hashable")
        return Object.computeHash(self, depth)

    def callAll(self, atom, args, namedArgs):
        if self.isSwitchable:
            raise userError(u"not synchronously callable (%s)" %
                    atom.repr.decode("utf-8"))
        else:
            self.resolutionRef()
            return self._target.callAll(atom, args, namedArgs)

    def sendAll(self, atom, args, namedArgs):
        self.resolutionRef()
        return self._target.sendAll(atom, args, namedArgs)

    def sendAllOnly(self, atom, args, namedArgs):
        self.resolutionRef()
        return self._target.sendAllOnly(atom, args, namedArgs)

    def optProblem(self):
        if self.isSwitchable:
            return NullObject
        else:
            self.resolutionRef()
            return self._target.optProblem()

    def resolutionRef(self):
        self._target = self._target.resolutionRef()
        if self.isSwitchable:
            return self
        else:
            return self._target

    def state(self):
        if self.isSwitchable:
            return EVENTUAL
        else:
            self.resolutionRef()
            return self._target.state()

    def isResolved(self):
        if self.isSwitchable:
            return False
        else:
            self.resolutionRef()
            return self._target.isResolved()

    def setTarget(self, newTarget):
        if self.isSwitchable:
           self._target = newTarget.resolutionRef()
           if self is self._target:
               raise userError(u"Ref loop")
        else:
            raise userError(u"No longer switchable")

    def commit(self):
        if not self.isSwitchable:
            return
        newTarget = self._target.resolutionRef()
        self._target = None
        self.isSwitchable = False
        newTarget = newTarget.resolutionRef()
        if newTarget is None:
            raise userError(u"Ref loop")
        else:
            self._target = newTarget


class BufferingRef(Promise):

    def __init__(self, buf):
        # Note to self: Weakref.
        self._buf = weakref.ref(buf)

    def toString(self):
        return u"<bufferingRef>"

    def computeHash(self, depth):
        raise userError(u"Unsettled promise is not hashable")

    def callAll(self, atom, args, namedArgs):
        raise userError(u"not synchronously callable (%s)" %
                atom.repr.decode("utf-8"))

    def sendAll(self, atom, args, namedArgs):
        optMsgs = self._buf()
        if optMsgs is None:
            # XXX what does it mean for us to have no more buffer?
            return self
        else:
            p, r = makePromise()
            optMsgs.enqueue(r, atom, args, namedArgs)
            return p

    def sendAllOnly(self, atom, args, namedArgs):
        optMsgs = self._buf()
        if optMsgs is not None:
            optMsgs.enqueue(None, atom, args, namedArgs)
        return NullObject

    def optProblem(self):
        return NullObject

    def resolutionRef(self):
        return self

    def state(self):
        return EVENTUAL

    def isResolved(self):
        return False

    def commit(self):
        pass


class NearRef(Promise):

    def __init__(self, target, vat):
        assert vat is not None, "Vat cannot be None"
        self.target = target
        self.vat = vat

    def toString(self):
        return self.target.toString()

    def computeHash(self, depth):
        return self.target.computeHash(depth)

    def callAll(self, atom, args, namedArgs):
        return self.target.callAtom(atom, args, namedArgs)

    def sendAll(self, atom, args, namedArgs):
        return self.vat.send(self.target, atom, args, namedArgs)

    def sendAllOnly(self, atom, args, namedArgs):
        return self.vat.sendOnly(self.target, atom, args, namedArgs)

    def optProblem(self):
        return NullObject

    def state(self):
        return NEAR

    def resolution(self):
        return self.target

    def resolutionRef(self):
        return self

    def isResolved(self):
        return True

    def commit(self):
        pass


def packLocalRef(obj, objVat, originVat):
    assert objVat is not None, "Vat cannot be None"
    assert originVat is not None, "Vat cannot be None"
    if objVat is originVat:
        log(["ref"], u"Eliding ref from (and to) vat %s" % objVat.name)
        return obj
    elif (isinstance(obj, LocalVatRef) and obj.originVat is objVat and
          obj.targetVat is originVat):
        log(["ref"], u"Short-circuiting round-trip ref for vat %s" %
            objVat.name)
        return obj.target
    return LocalVatRef(obj, objVat, originVat)

def packLocalRefs(args, targetVat, originVat):
    # XXX Upgrade this to honor the real serialization protocol.
    return [packLocalRef(arg, targetVat, originVat) for arg in args]

def packLocalNamedRefs(namedArgs, targetVat, originVat):
    from typhon.objects.collections.maps import ConstMap, monteMap
    # XXX monteMap()
    namedRefs = monteMap()
    for k, v in namedArgs.objectMap.items():
        namedRefs[packLocalRef(k, targetVat, originVat)] = packLocalRef(v, targetVat, originVat)
    return ConstMap(namedRefs)

class LocalVatRef(Promise):
    """
    A reference to an object in a different vat in the same runtime.

    This object makes no effort to prove that its originating vat and target
    vat are different vats.
    """

    def __init__(self, target, targetVat, originVat):
        self.target = target
        self.targetVat = targetVat
        self.originVat = originVat

    def toString(self):
        return u"<farRef from vat %s into vat %s>" % (
                self.originVat.name, self.targetVat.name)

    def computeHash(self, depth):
        raise userError(u"Non-local ref is not hashable")

    def callAll(self, atom, args, namedArgs):
        raise userError(u"not synchronously callable (%s)" %
                        atom.repr.decode("utf-8"))

    def sendAll(self, atom, args, namedArgs):
        vat = currentVat.get()
        # Think about it: These args are in the current vat, and we're
        # accessing them from our target's vat. Therefore, these refs should
        # be from our target's vat into the current vat.
        refs = packLocalRefs(args, vat, self.targetVat)
        namedRefs = packLocalNamedRefs(namedArgs, vat, self.targetVat)
        return packLocalRef(self.targetVat.send(self.target, atom, refs,
                                                namedRefs),
                            self.targetVat, vat)

    def sendAllOnly(self, atom, args, namedArgs):
        vat = currentVat.get()
        refs = packLocalRefs(args, vat, self.targetVat)
        namedRefs = packLocalNamedRefs(namedArgs, vat, self.targetVat)
        # NB: None is returned here and it's turned into null up above.
        return self.targetVat.sendOnly(self.target, atom, refs, namedRefs)

    def optProblem(self):
        return NullObject

    def state(self):
        return EVENTUAL

    def resolution(self):
        if self.target.auditedBy(deepFrozenStamp):
            return self.target
        return self

    def resolutionRef(self):
        return self

    def isResolved(self):
        return True

    def commit(self):
        pass


class UnconnectedRef(Promise):

    def __init__(self, problem):
        assert isinstance(problem, Object)
        self._problem = problem

    def toString(self):
        return u"<ref broken by %s>" % self._problem.toString()

    def computeHash(self, depth):
        raise userError(u"Broken promise is not hashable")

    def callAll(self, atom, args, namedArgs):
        self._doBreakage(atom, args, namedArgs)
        raise UserException(self._problem)

    def sendAll(self, atom, args, namedArgs):
        self._doBreakage(atom, args, namedArgs)
        return self

    def sendAllOnly(self, atom, args, namedArgs):
        return self._doBreakage(atom, args, namedArgs)

    def state(self):
        return BROKEN

    def optProblem(self):
        return self._problem

    def resolutionRef(self):
        return self

    def _doBreakage(self, atom, args, namedArgs):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom in (_WHENMORERESOLVED_1, _WHENBROKEN_1):
            vat = currentVat.get()
            return vat.sendOnly(args[0], RUN_1, [self], EMPTY_MAP)

    def isResolved(self):
        return True

    def commit(self):
        pass


@autohelp
class Smash(Object):
    _immutable_fields_ = "resolver",

    def __init__(self, resolver):
        self.resolver = resolver

    def recv(self, atom, args):
        if atom is RUN_1:
            return wrapBool(self.resolver.smash(args[0]))
        raise Refused(self, atom, args)
