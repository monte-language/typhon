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
from typhon.errors import Refused, userError
from typhon.objects.collections import ConstList
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.root import Object, runnable


class RefState(object):
    pass

BROKEN, EVENTUAL, NEAR = RefState(), RefState(), RefState()

BROKEN_1 = getAtom(u"broken", 1)
ISBROKEN_1 = getAtom(u"isBroken", 1)
PROMISE_0 = getAtom(u"promise", 0)
RESOLVE_1 = getAtom(u"resolve", 1)
RESOLVE_2 = getAtom(u"resolve", 2)
RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
WHENRESOLVED_2 = getAtom(u"whenResolved", 2)
_PRINTON_1 = getAtom(u"_printOn", 1)
_WHENBROKEN_1 = getAtom(u"_whenBroken", 1)
_WHENMORERESOLVED_1 = getAtom(u"_whenMoreResolved", 1)
_WHENMORERESOLVED_2 = getAtom(u"_whenMoreResolved", 2)


def makePromise(vat):
    buf = _Buffer([], vat)
    sref = SwitchableRef(BufferingRef(buf))
    return sref, LocalResolver(vat, sref, buf)


def _toRef(o, vat):
    if isinstance(o, Promise):
        return o
    return NearRef(o, vat)


def resolution(o):
    if isinstance(o, Promise):
        return o.resolution()
    return o


class RefOps(Object):
    """
    Public functions for ref manipulation. Exposed in safescope as 'Ref'.
    """

    def __init__(self, vat):
        self._vat = vat

    def toString(self):
        return u"<Ref>"

    def recv(self, atom, args):
        if atom is PROMISE_0:
            return self.promise()

        if atom is WHENRESOLVED_2:
            return self.whenResolved(args[0], args[1])

        if atom is ISBROKEN_1:
            return self.isBroken(args[0])

        if atom is BROKEN_1:
            return self.broken(unwrapStr(args[0]))

        raise Refused(atom, args)

    def promise(self):
        p, r = makePromise(self._vat)
        return ConstList([p, r])

    def broken(self, problem):
        return UnconnectedRef(problem, self._vat)

    def optBroken(self, optProblem):
        if optProblem is NullObject:
            return NullObject
        else:
            return self.broken(optProblem.toString())

    def isNear(self, ref):
        if isinstance(ref, Promise):
            return wrapBool(ref.state() is NEAR)
        else:
            return wrapBool(True)

    def isEventual(self, ref):
        if isinstance(ref, Promise):
            return wrapBool(ref.state() is EVENTUAL)
        else:
            return wrapBool(False)

    def isBroken(self, ref):
        if isinstance(ref, Promise):
            return wrapBool(ref.state() is BROKEN)
        else:
            return wrapBool(False)

    def optProblem(self, ref):
        if isinstance(ref, Promise):
            return ref.problem
        return NullObject

    def state(self, ref):
        if isinstance(ref, Promise):
            return ref.state()
        else:
            return NEAR

#    def fulfillment(self, ref):
#        ref = self.resolution(ref)
#        p = self.optProblem(ref)
#        if self.isResolved(ref):
#            if p is NullObject:
#                return ref
#            else:
#                raise p
#        else:
#            raise RuntimeError("Not resolved: %r" % (ref,))
#
#    def isResolved(self, ref):
#        if isinstance(ref, Promise):
#            return wrapBool(ref.isResolved())
#        else:
#            return wrapBool(True)

    def isFar(self, ref):
        return self.isEventual(ref) and self.isResolved(ref)

    def whenResolved(self, o, callback):
        p, r = makePromise(self._vat)
        prob = self._vat.sendOnly((o, _WHENMORERESOLVED_2,
                                  [self._vat, _whenResolvedReactor(callback,
                                      o, r, self._vat)]))
        # if prob is not None:
        #     return self.broken(prob)
        return p

    def whenResolvedOnly(self, o, callback):
        p, r = makePromise(self._vat)
        return self._vat.sendOnly((o, _WHENMORERESOLVED_2,
                                  [self._vat, _whenResolvedReactor(callback,
                                      o, r, self._vat)]))

    def whenBroken(self, o, callback):
        p, r = makePromise(self._vat)
        prob = self._vat.sendOnly((o, _WHENMORERESOLVED_2,
                                  [self._vat, _whenBrokenReactor(callback, o,
                                      r, self._vat)]))
        # if prob is not None:
        #     return self.broken(prob)
        return p

    def whenBrokenOnly(self, o, callback):
        p, r = makePromise(self._vat)
        return self._vat.sendOnly((o, _WHENMORERESOLVED_2,
                                  [self._vat, _whenBrokenReactor(callback, o,
                                      r, self._vat)]))


    def isDeepFrozen(self, o):
        # XXX
        return wrapBool(False)

    def isSelfless(self, o):
        # XXX
        return wrapBool(False)

    def isSelfish(self, o):
        return self.isNear(o) and not self.isSelfless(o)


def _whenBrokenReactor(callback, ref, resolver, vat):
    @runnable(RUN_0)
    def whenBroken(_):
        if not isinstance(ref, Promise):
            return NullObject

        if ref.state() is EVENTUAL:
            vat.sendOnly(ref, _WHENMORERESOLVED_2, ConstList([whenBroken]))
        elif ref.state() is BROKEN:
            try:
                outcome = callback(ref)
            except Exception, e:
                outcome = e
            if resolver is not NullObject:
                resolver.resolve(outcome)
        return NullObject
    return whenBroken()


class _whenResolvedReactor(Object):

    done = False

    def __init__(self, callback, ref, resolver, vat):
        self._cb = callback
        self._ref = ref
        self._resolver = resolver
        self._vat = vat

    def recv(self, atom, args):
        if atom is RUN_0:
            if self.done:
                return NullObject

            if self._ref.isResolved():
                try:
                    outcome = self._cb.call(u"run", [self._ref])
                except Exception, e:
                    # XXX reify the exception and raise it in Monte
                    raise
                    # outcome = e

                if self._resolver is not NullObject:
                    self._resolver.resolve(outcome)
                self.done = True
            else:
                self._vat.sendOnly((self._ref, _WHENMORERESOLVED_1,
                    ConstList([_whenResolvedReactor])))

            return NullObject
        raise Refused(atom, args)


class LocalResolver(Object):

    def __init__(self, vat, ref, buf):
        self._vat = vat
        self._ref = ref
        self._buf = buf

    def toString(self):
        return u"<Ref$Resolver>"

    def recv(self, atom, args):
        if atom is RESOLVE_1:
            return wrapBool(self.resolve(args[0]))

        if atom is RESOLVE_2:
            return wrapBool(self.resolve(args[0], unwrapBool(args[1])))

        raise Refused(atom, args)

    def resolve(self, target, strict=True):
        if self._ref is None:
            if strict:
                raise userError(u"Already resolved")
            return False
        else:
            self._ref.setTarget(_toRef(target, self._vat))
            self._ref.commit()
            if self._buf is not None:
                self._buf.deliverAll(target)
            self._ref = None
            self._buf = None
            return True

    def resolveRace(self, target):
        return self.resolve(target, False)

    def smash(self, problem):
        return self.resolve(UnconnectedRef(problem, self._vat), False)

    def isDone(self):
        return wrapBool(self._ref is None)

    def _printOn(self, out):
        if self.ref is None:
            out.raw_print(u'<Closed Resolver>')
        else:
            out.raw_print(u'<Resolver>')


class _Buffer(object):
    def __init__(self, buf, vat):
        self._buf = buf
        self._vat = vat

    def deliverAll(self, target):
        #XXX record sending-context information for causality tracing
        msgs = self._buf
        del self._buf[:]
        targRef = _toRef(target, self._vat)
        for msg in msgs:
            targRef.sendMsg(msg)
        return len(msgs)


class Promise(Object):

    def callAll(self, atom, args):
        raise Refused(atom, args)

    def resolutionRef(self):
        # XXX mostly just here to sate RPython
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

    def sendMsg(self, msg):
        if msg.resolver is None:
            self.sendAllOnly(msg.verb, msg.args)
        else:
            msg.resolver.resolve(self.sendAll(msg.verb, msg.args))

    def toString(self):
        return u"<promise>"

    def recv(self, atom, args):
        if atom is _PRINTON_1:
            out = args[0]
            return out.call(u"write", [StrObject(self.toString())])

        if atom is _WHENMORERESOLVED_2:
            return self._whenMoreResolved(args[0], args[1])

        return self.callAll(atom, args)

    def _whenMoreResolved(self, vat, callback):
        # Welcome to _whenMoreResolved.
        # This method's implementation, in Monte, should be:
        # to _whenMoreResolved(callback): callback<-(self)
        # However, we can't do that in Python land without a vat. So, here we
        # are; this will be better someday. Perhaps. ~ C.
        from typhon.objects.vats import Vat
        assert isinstance(vat, Vat)
        vat.sendOnly((callback, RUN_1, [self]))
        return NullObject


class SwitchableRef(Promise):
    """
    Starts out pointing to one promise and switches to another later.
    """

    isSwitchable = True

    def __init__(self, target):
        self._target = target

    def toString(self):
        if self.isSwitchable:
            return u"<promise>"
        else:
            self.resolutionRef()
            return self._target.toString()

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

    def callAll(self, atom, args):
        if self.isSwitchable:
            raise userError(u"not synchronously callable (%s)" %
                    atom.repr().decode("utf-8"))
        else:
            self.resolutionRef()
            return self._target.callAll(atom, args)

    def sendMsg(self, msg):
        self.resolutionRef()
        self._target.sendMsg(msg)

    def sendAll(self, atom, args):
        self.resolutionRef()
        return self._target.sendAll(atom, args)

    def sendAllOnly(self, atom, args):
        self.resolutionRef()
        return self._target.sendAllOnly(atom, args)

    def isResolved(self):
        if self.isSwitchable:
            return wrapBool(False)
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

    def hash(self):
        if self.isSwitchable:
            raise userError(u"must be settled")
        else:
            return self._target.hash()


class BufferingRef(Promise):

    def __init__(self, buf):
        # Note to self: Weakref.
        self._buf = weakref.ref(buf)
        self._vat = buf._vat

    def optProblem(self):
        return NullObject

    def resolutionRef(self):
        return self

    def state(self):
        return EVENTUAL

    def callAll(self, atom, args):
        raise userError(u"not synchronously callable (%s)" %
                atom.repr().decode("utf-8"))

    def sendAll(self, atom, args):
        optMsgs = self._buf()
        if optMsgs is None:
            return self
        else:
            p, r = makePromise(self._vat)
            optMsgs.buf.append((r, atom, args))
            return ConstList([p, r])

    def sendAllOnly(self, atom, args):
        optMsgs = self._buf()
        if optMsgs is not None:
            optMsgs.buf.append((NullObject, atom, args))
        return NullObject

    def isResolved(self):
        return wrapBool(False)

    def commit(self):
        pass


class NearRef(Promise):

    def __init__(self, target, vat):
        self._target = target
        self._vat = vat

    def toString(self):
        return self._target.toString()

    def optProblem(self):
        return NullObject

    def state(self):
        return NEAR

    def resolution(self):
        return self._target

    def resolutionRef(self):
        return self

    def callAll(self, atom, args):
        return self._target.call(atom.verb, args)

    def sendAll(self, atom, args):
        return self._vat.sendAll(self._target, atom, args)

    def sendAllOnly(self, atom, args):
        return self._vat.sendAllOnly(self._target, atom, args)

    def isResolved(self):
        return wrapBool(True)

    def sendMsg(self, msg):
        self.vat.qSendMsg(self._target, msg)

    def commit(self):
        pass

    def hash(self):
        return hash(self._target)


class UnconnectedRef(Promise):

    def __init__(self, problem, vat):
        assert isinstance(problem, unicode)
        self._problem = problem
        self._vat = vat

    def toString(self):
        return u"<ref broken by %s>" % (self._problem,)

    def state(self):
        return BROKEN

    def resolutionRef(self):
        return self

    def _doBreakage(self, atom, args):
        if atom in (_WHENMORERESOLVED_1, _WHENBROKEN_1):
            return self._vat.sendOnly((args[0], RUN_1, [self]))

    def callAll(self, atom, args):
        self._doBreakage(atom, args)
        raise userError(self._problem)

    def sendAll(self, atom, args):
        self._doBreakage(atom, args)
        return self

    def sendAllOnly(self, atom, args):
        return self._doBreakage(atom, args)

    def isResolved(self):
        return wrapBool(True)

    def commit(self):
        pass
