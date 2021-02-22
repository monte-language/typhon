# encoding: utf-8

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
    sref = SwitchableRef(vat)
    return sref, LocalResolver(sref, vat, guard)


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


def isEventual(ref):
    if isinstance(ref, Promise):
        return ref.state() is EVENTUAL
    else:
        return False


def isNear(ref):
    if isinstance(ref, Promise):
        return ref.state() is NEAR
    else:
        return True


def optProblem(ref):
    if isinstance(ref, Promise):
        return ref.optProblem()
    return NullObject


def stateOf(ref):
    if isinstance(ref, Promise):
        return ref.state()
    return NEAR


@autohelp
@audited.DF
class RefOps(Object):
    """
    Reference ("ref") management and utilities.
    """

    def toString(self):
        return u"<Ref>"

    @method("Any", "Any", "Any", resolved="Bool")
    def makeProxy(self, handler, resolution, resolved=False):
        """
        Build a proxy far object.

        Proxy objects are inherently always far, but they are not required to
        resolve to a definite far object.

        A proxy waits on a `resolution`, which should be a promise for a
        FinalSlot, and delivers sent messages to `handler` while waiting. If
        the `resolution` never resolves, then the `handler` controls the
        behavior of the proxy.

        `resolved` proxies are settled on a far object.
        """

        from typhon.objects.proxy import makeProxy as mp
        return mp(handler, resolution, resolved)

    @method("Any", "Any")
    def optProblem(self, ref):
        """
        The problem which broke `ref`, if it is a broken promise, or `null`
        otherwise.
        """

        return optProblem(ref)

    @method("Str", "Any")
    def state(self, o):
        """
        Determine the resolution state of an object.
        """

        return stateOf(o).repr

    @method("List", guard="Any")
    def promise(self, guard=None):
        """
        Create a [promise, resolver] pair.

        The optional `=> guard` will coerce the promise's resolution.
        """

        p, r = makePromise(guard=guard)
        return [p, r]

    @method("Any", "Any")
    def broken(self, problem):
        """
        Return a broken ref with a description of a problem.
        """

        return UnconnectedRef(currentVat.get(), problem)

    @method.py("Bool", "Any")
    def isNear(self, ref):
        """
        Whether an object is near.

        Refs that are resolved to near objects are also near.
        """

        return isNear(ref)

    @method.py("Bool", "Any")
    def isEventual(self, ref):
        """
        Whether an object is an eventual ref.
        """

        return isEventual(ref)

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
                     [WhenResolvedOnlyReactor(callback, o, vat)],
                     EMPTY_MAP)
        return NullObject

    @method("Any", "Any", "Any")
    def whenBroken(self, o, callback):
        if not isinstance(o, Promise):
            # Near refs can't possibly be broken.
            return

        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenBrokenReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    @method("Any", "Any", "Any")
    def whenBrokenOnly(self, o, callback):
        if not isinstance(o, Promise):
            # Near refs can't possibly be broken.
            return

        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        return vat.sendOnly(o, _WHENMORERESOLVED_1,
                            [WhenBrokenOnlyReactor(callback, o, vat)],
                            EMPTY_MAP)

    @method("Any", "Any", "Any")
    def whenNear(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(o, _WHENMORERESOLVED_1,
                     [WhenNearReactor(callback, o, r, vat)],
                     EMPTY_MAP)
        return p

    @method("Any", "Any", "Any")
    def whenNearOnly(self, o, callback):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        return vat.sendOnly(o, _WHENMORERESOLVED_1,
                            [WhenNearOnlyReactor(callback, o, vat)],
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

        return isNear(o) and not self.isSelfless(o)


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
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when: %s | %s>" % (self._cb.toString(), self._eb.toString())

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if isResolved(self._ref):
            try:
                if isBroken(self._ref):
                    outcome = self._eb.call(u"run", [self._ref])
                else:
                    outcome = self._cb.call(u"run", [self._ref])
                    if isBroken(outcome):
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
class WhenNearReactor(Object):
    """
    A reactor that invokes its callback when a promise is resolved successfully.
    """

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when near: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if isNear(self._ref):
            try:
                outcome = self._cb.call(u"run", [self._ref])
                self._resolver.resolve(outcome)
            except UserException as ue:
                from typhon.objects.exceptions import sealException
                self._resolver.smash(sealException(ue))

            self.done = True
        elif isBroken(self._ref):
            self._resolver.resolve(self._ref)
            self.done = True
        else:
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)


@autohelp
class WhenNearOnlyReactor(Object):
    """
    A reactor that invokes its callback when a promise is resolved successfully.
    """

    done = False

    def __init__(self, callback, ref, vat):
        self._cb = callback
        self._ref = ref
        self.vat = vat

    def toString(self):
        return u"<when near: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if isNear(self._ref):
            self._cb.call(u"run", [self._ref])
            self.done = True
        elif isBroken(self._ref):
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
        if isEventual(self._ref):
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)
        elif isBroken(self._ref):
            try:
                # Deliver the brokenness notification.
                outcome = self._cb.call(u"run", [self._ref])
                # Success.
                self._resolver.resolve(outcome)
            except UserException as ue:
                # Failure. Continue delivering failures.
                from typhon.objects.exceptions import sealException
                self._resolver.smash(sealException(ue))


@autohelp
class WhenBrokenOnlyReactor(Object):
    """
    A reactor which delivers information about broken promises.
    """

    def __init__(self, callback, ref, vat):
        self._cb = callback
        # NB: Always a promise.
        self._ref = ref
        self.vat = vat

    def toString(self):
        return u"<when broken: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        if isEventual(self._ref):
            from typhon.objects.collections.maps import EMPTY_MAP
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)
        elif isBroken(self._ref):
            # Deliver the brokenness notification.
            self._cb.call(u"run", [self._ref])


@autohelp
class WhenResolvedReactor(Object):
    """
    A reactor which delivers information about resolved promises.
    """

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<when resolved: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if isResolved(self._ref):
            try:
                outcome = self._cb.call(u"run", [self._ref])
                self._resolver.resolve(outcome)
            except UserException as ue:
                from typhon.objects.exceptions import sealException
                self._resolver.smash(sealException(ue))

            self.done = True
        else:
            self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self],
                              EMPTY_MAP)


@autohelp
class WhenResolvedOnlyReactor(Object):
    """
    A reactor which delivers information about resolved promises.
    """

    done = False

    def __init__(self, callback, ref, vat):
        self._cb = callback
        self._ref = ref
        self.vat = vat

    def toString(self):
        return u"<when resolved: %s>" % self._cb.toString()

    @method("Void", "Any")
    def run(self, unused):
        from typhon.objects.collections.maps import EMPTY_MAP
        if self.done:
            return

        if isResolved(self._ref):
            self._cb.call(u"run", [self._ref])
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

    def __init__(self, ref, vat, guard):
        assert vat is not None, "Vat cannot be None"
        # NB: ref is always a SwitchableRef. After we switch it, then we set
        # it to None, both for GC and also to indicate that we're resolved.
        self._ref = ref
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
                with Ejector(u"resolver Vow") as ej:
                    try:
                        target = self.guard.call(u"coerce", [target, ej])
                    except Ejecting as e:
                        if e.ejector is not ej:
                            raise
                        target = UnconnectedRef(self.vat, e.value)
                    except UserException as ue:
                        from typhon.objects.exceptions import sealException
                        target = UnconnectedRef(self.vat, sealException(ue))
            target = resolution(target)
            self._ref.setTargetAndCommit(target)
            self._ref = None
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

    def recvNamed(self, atom, args, namedArgs):
        # Is it _whenMoreResolved? If not, treat it like a call.
        if atom is _WHENMORERESOLVED_1:
            callback = args[0]
            from typhon.objects.collections.maps import EMPTY_MAP
            # Welcome to _whenMoreResolved.
            # This method's implementation, in Monte, should be:
            # to _whenMoreResolved(callback): callback<-(self)
            vat = currentVat.get()
            vat.sendOnly(callback, RUN_1, [self], EMPTY_MAP)
            return NullObject

        return self.callAll(atom, args, namedArgs)

    # Eventual sends.

    def send(self, atom, args, namedArgs):
        # Resolution is done by the vat here; we don't get to access the
        # resolver ourselves.
        return self.sendAll(atom, args, namedArgs)

    def sendOnly(self, atom, args, namedArgs):
        self.sendAllOnly(atom, args, namedArgs)
        return NullObject

    # Promise API.

    # The most resolved version of this promise. Subclasses will usually
    # override this hook, but the default implementation is not bad.
    def resolution(self):
        return self

    def state(self):
        if self.optProblem() is not NullObject:
            return BROKEN
        target = self.resolution()
        if self is target:
            return EVENTUAL
        else:
            return target.state()


class SwitchableRef(Promise):
    """
    Starts out not really pointing to anything, but can switch to point to
    something later.
    """

    # NB: We switch all of our mutable state at once. Either:
    # * isSwitchable, _target is None, len(_buf)
    # * not isSwitchable, _target, _buf is None

    isSwitchable = True
    _target = None

    def __init__(self, vat):
        self.vat = vat
        self._messageBuf = []

    # NB: Recursion is possible here. To avoid it, we deliberately imagine our
    # call to resolution(self._target) as re-entrant upon this method, in the
    # case when we have multiple SwitchableRefs in a row. This allows us to
    # amortize the consumption of refs. Specifically:
    # * Suppose that we have N SwitchableRefs in a row. SwitchableRefs are the
    #   only possible non-trivial branch nodes that resolve in an immediate
    #   near manner for user-level code, so they are the only relevant case.
    # * N is too big; if we recurse N times, we will overflow the RPython
    #   stack, and this is forbidden by assumption.
    # * But we might notice after a constant number c=2 of calls that we are
    #   potentially headed down such a chain. We could halt the recursion and
    #   return a partially-resolved target.
    # * The user-level code doing the resolution will send M messages to the
    #   not-fully-resolved target. this will create N-c=N-2 extra vat turns
    #   where M messages are copied in extra work from SwitchableRef to
    #   SwitchableRef down the chain.
    # * Suppose that we perform this split N times over N different user-level
    #   actions. Then, on one hand, we perform M×N² amount of work, but we
    #   amortize it across N calls. This should be linear performance.
    def _resolveMore(self):
        # This implies that self._target is not None and also that self._buf
        # is None. This is enough to reconstruct the following trickery from
        # case analysis; these are the only possibilities.
        if self.isSwitchable:
            return self
        assert not self.isSwitchable, "resolute"

        while isinstance(self._target, SwitchableRef):
            if self is self._target:
                raise userError(u"Ref loop while coalescing switched promises")
            elif self._target.isSwitchable:
                self = self._target
                break
            else:
                self._target = self._target._target
        else:
            # There aren't any other cases that nasty, right? So we shouldn't
            # build up that many stack frames here.
            self._target = resolution(self._target)
        # Callers may need to adjust their sense of self.
        return self

    def toString(self):
        self = self._resolveMore()
        if self.isSwitchable:
            return u"<switchable promise>"
        else:
            return self._target.toString()

    def computeHash(self, depth):
        if self.isSwitchable:
            raise userError(u"Unsettled promise is not hashable")
        return Object.computeHash(self, depth)

    def callAll(self, atom, args, namedArgs):
        self = self._resolveMore()
        if self.isSwitchable:
            raise userError(u"not synchronously callable (%s)" %
                    atom.repr.decode("utf-8"))
        else:
            return self._target.callAtom(atom, args, namedArgs)

    def sendAll(self, atom, args, namedArgs):
        self = self._resolveMore()
        if self.isSwitchable:
            p, r = makePromise()
            self._messageBuf.append((r, atom, args, namedArgs))
            return p
        else:
            return self.vat.send(self._target, atom, args, namedArgs)

    def sendAllOnly(self, atom, args, namedArgs):
        self = self._resolveMore()
        if self.isSwitchable:
            self._messageBuf.append((None, atom, args, namedArgs))
        else:
            self.vat.sendOnly(self._target, atom, args, namedArgs)
        return NullObject

    def optProblem(self):
        self = self._resolveMore()
        if self.isSwitchable:
            return NullObject
        else:
            return optProblem(self._target)

    def state(self):
        self = self._resolveMore()
        if self.isSwitchable:
            return EVENTUAL
        else:
            return stateOf(self._target)

    def isResolved(self):
        self = self._resolveMore()
        if self.isSwitchable:
            return False
        else:
            return isResolved(self._target)

    def resolution(self):
        self = self._resolveMore()
        if self.isSwitchable:
            return self
        else:
            return self._target

    def _become(self, newTarget):
        assert self.isSwitchable, "goodnight"
        self.isSwitchable = False
        self._target = newTarget
        self._messageBuf = None

    def setTargetAndCommit(self, newTarget):
        if not self.isSwitchable:
            raise userError(u"No longer switchable")

        # Deliver buffered messages.
        for resolver, atom, args, namedArgs in self._messageBuf:
            if resolver is None:
                self.vat.sendOnly(newTarget, atom, args, namedArgs)
            else:
                result = self.vat.send(newTarget, atom, args, namedArgs)
                resolver.resolve(result)

        # And switch to become the new ref.
        self._become(newTarget)


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
        target = resolution(self.target)
        if target.auditedBy(deepFrozenStamp) and target.auditedBy(selfless):
            return target
        return self

    def isResolved(self):
        return True

    def commit(self):
        pass


class UnconnectedRef(Promise):
    """
    A broken reference.

    Rather than a value, this promise refers to a problem which caused it to
    become broken.
    """

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

    def _doBreakage(self, atom, args, namedArgs):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is _WHENMORERESOLVED_1:
            return self.vat.sendOnly(args[0], RUN_1, [self], EMPTY_MAP)

    def isResolved(self):
        return True

    def commit(self):
        pass
