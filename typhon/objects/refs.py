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
from typhon.errors import Refused, userError
from typhon.objects.auditors import deepFrozenStamp, selfless
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.data import StrObject
from typhon.objects.root import Object, method
from typhon.specs import Any, Bool, List, Str, Void
from typhon.vats import currentVat


class RefState(object):
    pass

BROKEN, EVENTUAL, NEAR = RefState(), RefState(), RefState()

RESOLVE_1 = getAtom(u"resolve", 1)
RESOLVE_2 = getAtom(u"resolve", 2)
RUN_1 = getAtom(u"run", 1)
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


@autohelp
class RefOps(Object):
    """
    Reference ("ref") management and utilities.
    """

    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<Ref>"

    @method([Any], Any)
    def broken(self, problem):
        """
        Return a broken ref with a description of a problem.
        """

        return UnconnectedRef(problem.toString())

    @method([Any], Bool)
    def isBroken(self, obj):
        """
        Whether an object is a broken ref.
        """

        if isinstance(obj, Promise):
            return obj.state() is BROKEN
        else:
            return False

    @method([Any], Bool)
    def isDeepFrozen(self, obj):
        """
        Whether an object has the `DeepFrozen` property.
        """

        return obj.auditedBy(deepFrozenStamp)

    @method([Any], Bool)
    def isEventual(self, obj):
        """
        Whether an object is an eventual ref.
        """

        if isinstance(obj, Promise):
            return obj.state() is EVENTUAL
        else:
            return False

    @method([Any], Bool)
    def isFar(self, obj):
        """
        Whether an object is a far ref.
        """

        if isinstance(obj, Promise):
            return obj.state() is EVENTUAL and obj.isResolved()
        else:
            return False

    @method([Any], Bool)
    def isNear(self, obj):
        """
        Whether an object is near.

        Refs that are resolved to near objects are also near.
        """

        if isinstance(obj, Promise):
            return obj.state() is NEAR
        else:
            return True

    @method([Any], Bool)
    def isResolved(self, obj):
        """
        Whether an object is resolved.
        """

        if isinstance(obj, Promise):
            return obj.isResolved()
        else:
            return True

    @method([Any], Bool)
    def isSelfish(self, obj):
        """
        Whether an object is "selfish"; that is, whether it does not have the
        `Selfless` property.

        Refs that are not near cannot be examined for selfishness; they are
        too far away.
        """

        if isinstance(obj, Promise):
            return obj.state() is NEAR and not obj.auditedBy(selfless)
        else:
            return not obj.auditedBy(selfless)

    @method([Any], Bool)
    def isSelfless(self, obj):
        """
        Whether an object has the `Selfless` property.
        """

        return obj.auditedBy(selfless)

    @method([], List)
    def promise(self):
        """
        Create a [promise, resolver] pair.
        """

        p, r = makePromise()
        return [p, r]

    # While "state" is not a reserved keyword in Python, it is used as a
    # method name by Promise and its subclasses, and poor RPython cannot deal
    # with that.
    @method([Any], Str, verb=u"state")
    def state_(self, obj):
        """
        Determine the resolution state of an object.
        """

        if isinstance(obj, Promise):
            s = obj.state()
        else:
            s = NEAR

        if s is EVENTUAL:
            return u"EVENTUAL"
        if s is NEAR:
            return u"NEAR"
        if s is BROKEN:
            return u"BROKEN"
        return u"UNKNOWN"

    @method([Any, Any], Any)
    def whenBroken(self, obj, callback):
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(obj, _WHENMORERESOLVED_1,
                     [WhenBrokenReactor(callback, obj, r, vat)])
        return p

    @method([Any, Any], Void)
    def whenBrokenOnly(self, obj, callback):
        vat = currentVat.get()
        vat.sendOnly(obj, _WHENMORERESOLVED_1,
                     [WhenBrokenReactor(callback, obj, None, vat)])

    @method([Any, Any], Any)
    def whenResolved(self, obj, callback):
        p, r = makePromise()
        vat = currentVat.get()
        vat.sendOnly(obj, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, obj, r, vat)])
        return p

    @method([Any, Any], Void)
    def whenResolvedOnly(self, obj, callback):
        vat = currentVat.get()
        vat.sendOnly(obj, _WHENMORERESOLVED_1,
                     [WhenResolvedReactor(callback, obj, None, vat)])


@autohelp
class WhenBrokenReactor(Object):
    """
    React to a ref becoming broken.
    """

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<whenBrokenReactor>"

    @method([Any], Void)
    def run(self, _):
        assert isinstance(self, WhenBrokenReactor)
        if isinstance(self._ref, Promise):
            if self._ref.state() is EVENTUAL:
                self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self])
            elif self._ref.state() is BROKEN:
                # XXX this could raise; we might need to reflect to user
                outcome = self._cb.call(u"run", [self._ref])

                if self._resolver is not None:
                    self._resolver.resolve(outcome)


@autohelp
class WhenResolvedReactor(Object):
    """
    React to a ref becoming resolved.
    """

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = _toRef(ref, vat)
        self._resolver = resolver
        self.vat = vat

    def toString(self):
        return u"<whenResolvedReactor>"

    @method([Any], Void)
    def run(self, _):
        assert isinstance(self, WhenResolvedReactor)
        if not self.done:
            if self._ref.isResolved():
                # XXX should reflect to user if exception?
                outcome = self._cb.call(u"run", [self._ref])

                if self._resolver is not None:
                    self._resolver.resolve(outcome)

                self.done = True
            else:
                self.vat.sendOnly(self._ref, _WHENMORERESOLVED_1, [self])


@autohelp
class LocalResolver(Object):

    def __init__(self, ref, buf, vat):
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

    def enqueue(self, resolver, atom, args):
        self._buf.append((resolver, atom, args))

    def deliverAll(self, target):
        #XXX record sending-context information for causality tracing
        targRef = _toRef(target, self.vat)
        for resolver, atom, args in self._buf:
            if resolver is None:
                targRef.sendAllOnly(atom, args)
            else:
                result = targRef.sendAll(atom, args)
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

    def recv(self, atom, args):
        if atom is _PRINTON_1:
            out = args[0]
            return out.call(u"print", [StrObject(self.toString())])

        if atom is _WHENMORERESOLVED_1:
            return self._whenMoreResolved(args[0])

        return self.callAll(atom, args)

    def _whenMoreResolved(self, callback):
        # Welcome to _whenMoreResolved.
        # This method's implementation, in Monte, should be:
        # to _whenMoreResolved(callback): callback<-(self)
        vat = currentVat.get()
        vat.sendOnly(callback, RUN_1, [self])
        return NullObject

    # Synchronous calls.

    # Eventual sends.

    def send(self, atom, args):
        # Resolution is done by the vat here; we don't get to access the
        # resolver ourselves.
        return self.sendAll(atom, args)

    def sendOnly(self, atom, args):
        self.sendAllOnly(atom, args)
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
            return u"<switchable promise>"
        else:
            self.resolutionRef()
            return self._target.toString()

    def callAll(self, atom, args):
        if self.isSwitchable:
            raise userError(u"not synchronously callable (%s)" %
                    atom.repr.decode("utf-8"))
        else:
            self.resolutionRef()
            return self._target.callAll(atom, args)

    def sendAll(self, atom, args):
        self.resolutionRef()
        return self._target.sendAll(atom, args)

    def sendAllOnly(self, atom, args):
        self.resolutionRef()
        return self._target.sendAllOnly(atom, args)

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

    def callAll(self, atom, args):
        raise userError(u"not synchronously callable (%s)" %
                atom.repr.decode("utf-8"))

    def sendAll(self, atom, args):
        optMsgs = self._buf()
        if optMsgs is None:
            # XXX what does it mean for us to have no more buffer?
            return self
        else:
            p, r = makePromise()
            optMsgs.enqueue(r, atom, args)
            return p

    def sendAllOnly(self, atom, args):
        optMsgs = self._buf()
        if optMsgs is not None:
            optMsgs.enqueue(None, atom, args)
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
        self.target = target
        self.vat = vat

    def toString(self):
        return u"<nearref: %s>" % self.target.toString()

    def hash(self):
        return self.target.hash()

    def callAll(self, atom, args):
        return self.target.callAtom(atom, args)

    def sendAll(self, atom, args):
        return self.vat.send(self.target, atom, args)

    def sendAllOnly(self, atom, args):
        return self.vat.sendOnly(self.target, atom, args)

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


class LocalVatRef(Promise):
    """
    A reference to an object in a different vat in the same runtime.

    This object makes no effort to prove that its originating vat and target
    vat are different vats.
    """

    def __init__(self, target, vat):
        self.target = target
        self.vat = vat

    def toString(self):
        return u"<farref into vat %s>" % self.vat.toString()

    def hash(self):
        # XXX shouldn't this simply be unhashable?
        return self.target.hash()

    def callAll(self, atom, args):
        raise userError(u"not synchronously callable (%s)" %
                        atom.repr.decode("utf-8"))

    def sendAll(self, atom, args):
        vat = currentVat.get()
        refs = [LocalVatRef(arg, vat) for arg in args]
        return LocalVatRef(self.vat.send(self.target, atom, refs), self.vat)

    def sendAllOnly(self, atom, args):
        vat = currentVat.get()
        refs = [LocalVatRef(arg, vat) for arg in args]
        # NB: None is returned here and it's turned into null up above.
        return self.vat.sendOnly(self.target, atom, refs)

    def optProblem(self):
        return NullObject

    def state(self):
        return EVENTUAL

    def resolution(self):
        return self

    def resolutionRef(self):
        return self

    def isResolved(self):
        return True

    def commit(self):
        pass


class UnconnectedRef(Promise):

    def __init__(self, problem):
        assert isinstance(problem, unicode)
        self._problem = problem

    def toString(self):
        return u"<ref broken by %s>" % (self._problem,)

    def callAll(self, atom, args):
        self._doBreakage(atom, args)
        raise userError(self._problem)

    def sendAll(self, atom, args):
        self._doBreakage(atom, args)
        return self

    def sendAllOnly(self, atom, args):
        return self._doBreakage(atom, args)

    def state(self):
        return BROKEN

    def resolutionRef(self):
        return self

    def _doBreakage(self, atom, args):
        if atom in (_WHENMORERESOLVED_1, _WHENBROKEN_1):
            vat = currentVat.get()
            return vat.sendOnly(args[0], RUN_1, [self])

    def isResolved(self):
        return True

    def commit(self):
        pass
