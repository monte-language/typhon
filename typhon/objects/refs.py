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
from typhon.autohelp import autohelp, method
from typhon.enum import makeEnum
from typhon.errors import Ejecting, UserException, userError
from typhon.log import log
from typhon.objects.auditors import deepFrozenStamp, selfless
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import Object, audited
from typhon.vats import currentVat


BROKEN, EVENTUAL, NEAR = makeEnum(u"RefState",
                                  u"broken eventual near".split())

RESOLVE_1 = getAtom(u"resolve", 1)
RESOLVE_2 = getAtom(u"resolve", 2)
RUN_1 = getAtom(u"run", 1)
_WHENBROKEN_1 = getAtom(u"_whenBroken", 1)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)


def makePromise(guard=None):
    vat = currentVat.get()
    buf = MessageBuffer(vat)
    sref = SwitchableRef(BufferingRef(buf))
    return sref, LocalResolver(sref, buf, vat, guard)


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
    Reference ("ref") management and utilities.
    """

    def toString(self):
        return u"<Ref>"

    @method("Any", "Any", "Any", "Any")
    def makeProxy(self, x, y, z):
        from typhon.objects.proxy import makeProxy
        return makeProxy(x, y, z)

    @method("Any", "Any")
    def optProblem(self, ref):
        if isinstance(ref, Promise):
            return ref.optProblem()
        return NullObject

    @method("Str", "Any")
    def state(self, o):
        """
        Determine the resolution state of an object.
        """

        if isinstance(o, Promise):
            s = o.state()
        else:
            s = NEAR
        return s.repr

    @method("List", guard="Any")
    def promise(self, guard=None):
        """
        Create a [promise, resolver] pair.
        """

        p, r = makePromise(guard=guard)
        return [p, r]

    @method("Any", "Any")
    def broken(self, problem):
        """
        Return a broken ref with a description of a problem.
        """

        return UnconnectedRef(currentVat.get(), problem)

    def optBroken(self, optProblem):
        if optProblem is NullObject:
            return NullObject
        else:
            return self.broken(optProblem)

    @method.py("Bool", "Any")
    def isNear(self, ref):
        """
        Whether an object is near.

        Refs that are resolved to near objects are also near.
        """

        if isinstance(ref, Promise):
            return ref.state() is NEAR
        else:
            return True

    @method.py("Bool", "Any")
    def isEventual(self, ref):
        """
        Whether an object is an eventual ref.
        """

        if isinstance(ref, Promise):
            return ref.state() is EVENTUAL
        else:
            return False

    @method("Bool", "Any")
    def isBroken(self, ref):
        """
        Whether an object is a broken ref.
        """

        return isBroken(ref)

    @method("Bool", "Any")
    def isResolved(self, ref):
        """
        Whether an object is resolved.
        """

        return isResolved(ref)

    @method("Any", "Any")
    def fulfillment(self, ref):
        ref = resolution(ref)
        if isResolved(ref):
            if isBroken(ref):
                raise UserException(ref.optProblem())
            return ref
        else:
            raise userError(u"Not resolved: %s" % (ref.toString(),))

    @method("Bool", "Any")
    def isFar(self, ref):
        """
        Whether an object is a far ref.
        """

        return self.isEventual(ref) and isResolved(ref)

    @method("Any", "Any", "Any", "Any")
    def when(self, o, callback, errback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenReactor(callback, errback, o, r, vat)],
                     EMPTY_MAP)
        return p

    @method("Any", "Any", "Any")
    def whenResolved(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    @method("Any", "Any", "Any")
    def whenResolvedOnly(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, o, None, vat)],
                     EMPTY_MAP)
        return NullObject

    @method("Any", "Any", "Any")
    def whenBroken(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenBrokenReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    @method("Any", "Any", "Any")
    def whenBrokenOnly(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        return vat.sendOnly(o, _WHENMORERESOLVED_1,
                            [WhenBrokenReactor(callback, o, None, vat)],
                            EMPTY_MAP)

    @method("Bool", "Any")
    def isDeepFrozen(self, o):
        """
        Whether an object has the `DeepFrozen` property.
        """

        return o.auditedBy(deepFrozenStamp)

    @method.py("Bool", "Any")
    def isSelfless(self, o):
        """
        Whether an object has the `Selfless` property.
        """

        return o.auditedBy(selfless)

    @method("Bool", "Any")
    def isSelfish(self, o):
        """
        Whether an object is "selfish"; that is, whether it does not have the
        `Selfless` property.

        Refs that are not near cannot be examined for selfishness; they are
        too far away.
        """

        return self.isNear(o) and not self.isSelfless(o)


@autohelp
class WhenReactor(Object):
    """
    A reactor which handles both resolved and broken promises, invoking the
    success callback if the promise is not resolved and not broken. The failure
    callback is invoked if the promise is broken, or if the success callback
    produces a broken promise or throws.
    """

    done = False

    def __init__(self, callback, errback, ref, resolver, vat):
        self._cb = callback
        self._eb = errback
        self._ref = _toRef(ref, vat)
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when: %s | %s>" % (self._cb.toString(), self._eb.toString())

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if self._ref.isResolved():
            if isBroken(self._ref):
                f = self._eb
            else:
                f = self._cb
            try:
                outcome = f.call(u"run", [self._ref])
                if not isBroken(self._ref) and isBroken(outcome):
                    # success arm returned a broken promise
                    outcome = self._eb.call(u"run", [outcome])
                self._resolver.resolve(outcome)
            except UserException as ue:
                from typhon.objects.exceptions import sealException
                if not isBroken(self._ref):
                    # success arm threw
                    try:
                        self._resolver.resolve(self._eb.call(u"run", [UnconnectedRef(currentVat.get(), sealException(ue))]))
                    except UserException as ue2:
                        self._resolver.smash(sealException(ue2))
                else:
                    # failure arm threw
                    self._resolver.smash(sealException(ue))
            self.done = True
        else:
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)

@autohelp
class WhenBrokenReactor(Object):
    """
    A reactor which delivers information about broken promises.
    """

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when broken: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if not isinstance(self._ref, Promise):
            # Near refs can't possibly be broken.
            return

        if self._ref.state() is EVENTUAL:
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)
        elif self._ref.state() is BROKEN:
            try:
                # Deliver the brokenness notification.
                outcome = self._cb.call(u"run", [self._ref])
                if self._resolver is not None:
                    # Success.
                    self._resolver.resolve(outcome)
            except UserException as ue:
                # Failure. Continue delivering failures.
                if self._resolver is None:
                    raise
                else:
                    from typhon.objects.exceptions import sealException
                    self._resolver.smash(sealException(ue))


@autohelp
class WhenResolvedReactor(Object):
    """
    A reactor which delivers information about resolved promises.
    """

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = _toRef(ref, vat)
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when resolved: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if self._ref.isResolved():
            try:
                outcome = self._cb.call(u"run", [self._ref])
                if self._resolver is not None:
                    self._resolver.resolve(outcome)
            except UserException as ue:
                if self._resolver is None:
                    raise
                else:
                    from typhon.objects.exceptions import sealException
                    self._resolver.smash(sealException(ue))

            self.done = True
        else:
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)


@autohelp
class Smash(Object):
    """
    A breaker of promises.
    """

    def __init__(self, resolver):
        self.resolver = resolver

    @method("Bool", "Any")
    def run(self, problem):
        return self.resolver.smash(problem)


@autohelp
class LocalResolver(Object):
    """
    A resolver for a promise.
    """

    def __init__(self, ref, buf, vat, guard):
        assert vat is not None, "Vat cannot be None"
        self._ref = ref
        self._buf = buf
        self.vat = vat
        self.guard = guard

    def toString(self):
        if self._ref is None:
            return u"<closed resolver>"
        else:
            return u"<resolver>"

    def _resolve(self, target, strict=True):
        if self._ref is None:
            if strict:
                raise userError(u"Already resolved")
            return False
        else:
            if self.guard is not None and not isinstance(target,
                    UnconnectedRef):
                # Coerce. If there's a problem, then smash the promise.
                with Ejector() as ej:
                    try:
                        target = self.guard.call(u"coerce", [target, ej])
                    except Ejecting as e:
                        if e.ejector is not ej:
                            raise
                        target = UnconnectedRef(self.vat, e.value)
                    except UserException as ue:
                        from typhon.objects.exceptions import sealException
                        target = UnconnectedRef(self.vat, sealException(ue))
            self._ref.setTarget(_toRef(target, self.vat))
            self._ref.commit()
            self._buf.deliverAll(target)

            self._ref = None
            self._buf = None
            return True

    @method.py("Bool", "Any")
    def resolve(self, target):
        return self._resolve(target, True)

    @method.py("Bool", "Any")
    def resolveRace(self, target):
        return self._resolve(target, False)

    @method.py("Bool", "Any")
    def smash(self, problem):
        return self._resolve(UnconnectedRef(self.vat, problem), False)

    @method("Bool")
    def isDone(self):
        return self._ref is None

    def makeSmasher(self):
        return Smash(self)


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
        elif isinstance(result, Promise):
            return result.resolution()
        else:
            return result

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
           newTarget = newTarget.resolutionRef()
           if self is newTarget:
               raise userError(u"Ref loop")
           else:
               self._target = newTarget
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
    for k, v in namedArgs.iteritems():
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

    def __init__(self, vat, problem):
        assert isinstance(problem, Object)
        self._problem = problem
        self.vat = vat

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
        if atom is _WHENMORERESOLVED_1:
            return self.vat.sendOnly(args[0], RUN_1, [self], EMPTY_MAP)

    def isResolved(self):
        return True

    def commit(self):
        pass
