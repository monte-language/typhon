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

from rpython.rlib.rthread import ThreadLocalReference, allocate_lock

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, UserException
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.root import Object, runnable
from typhon.objects.data import unwrapStr


RUN_0 = getAtom(u"run", 0)
SEED_1 = getAtom(u"seed", 1)
SPROUT_1 = getAtom(u"sprout", 1)


class Callable(object):
    """
    One of the ugliest hacks I've ever written.

    RPython is not good. Today, RPython is not good in that RPython cannot
    unify bound methods that are disjoint. This means that "zero-argument
    callable" is not a possible type to achieve in RPython. I am very
    disappointed.
    """

    def call(self):
        """
        Feel bad about life.
        """


@autohelp
class Vat(Object):
    """
    Turn management and object isolation.
    """

    name = u"pa"

    def __init__(self, manager, reactor, name=None):
        self._manager = manager
        self._reactor = reactor
        if name is not None:
            self.name = name

        self._callbacks = []

        self._pendingLock = allocate_lock()
        self._pending = []

    def toString(self):
        return u"<vat(%s, %d turns pending)>" % (self.name, len(self._pending))

    def recv(self, atom, args):
        if atom is SEED_1:
            f = args[0]
            if not f.auditedBy(deepFrozenStamp):
                print "seed/1: Warning: Seeded receiver is not DeepFrozen"
            return self.send(f, RUN_0, [])

        if atom is SPROUT_1:
            name = unwrapStr(args[0])
            vat = Vat(self._manager, self._reactor, name)
            self._manager.vats.append(vat)
            return vat

        raise Refused(self, atom, args)

    def send(self, target, atom, args):
        from typhon.objects.refs import makePromise
        promise, resolver = makePromise()
        with self._pendingLock:
            self._pending.append((resolver, target, atom, args))
            # print "Planning to send", target, atom, args
        return promise

    def sendOnly(self, target, atom, args):
        with self._pendingLock:
            self._pending.append((None, target, atom, args))
            # print "Planning to sendOnly", target, atom, args

    def hasTurns(self):
        # Note that if we have pending callbacks but no pending turns, we
        # should still indicate that we have work to do. In takeSomeTurns(),
        # we'll take zero turns and then run our callbacks. This prevents
        # callbacks prepared in the initial turn from being skipped in the
        # event that there are no queued turns.
        return len(self._pending) or len(self._callbacks)

    def takeTurn(self):
        from typhon.objects.refs import Promise, resolution

        with self._pendingLock:
            resolver, target, atom, args = self._pending.pop(0)

        # If the target is a promise, then we should send to it instead of
        # calling. Try to resolve it as much as possible first, though.
        target = resolution(target)

        # print "Taking turn:", self, resolver, target, atom, args

        if resolver is None:
            # callOnly/sendOnly.
            if isinstance(target, Promise):
                target.sendOnly(atom, args)
            else:
                # Oh, that's right; we don't do callOnly since it's silly.
                target.callAtom(atom, args)
        else:
            # call/send.
            if isinstance(target, Promise):
                result = target.send(atom, args)
            else:
                result = target.callAtom(atom, args)
            resolver.resolve(result)

    def afterTurn(self, callback):
        """
        After the current turn, run this callback.

        The callback must guarantee that it will *not* take turns on the vat!

        It is acceptable for the callback to queue more turns; in fact, it's
        expected.
        """

        self._callbacks.append(callback)

    def runCallbacks(self):
        # Reallocate the callback list so that callbacks can queue more
        # callbacks for after the next turn.
        callbacks = self._callbacks
        self._callbacks = []

        for callback in callbacks:
            callback.call()

    def takeSomeTurns(self):
        # Limit the number of continuous turns to keep network latency low.
        # It's possible that more turns will be queued while we're taking
        # these turns, after all.
        count = len(self._pending)
        # print "Taking", count, "turn(s) on", self.repr()
        for _ in range(count):
            try:
                self.takeTurn()
            except UserException as ue:
                print "Caught exception while taking turn:", ue.formatError()

        self.runCallbacks()


currentVat = ThreadLocalReference(Vat)


class scopedVat(object):

    def __init__(self, vat):
        self.vat = vat

    def __enter__(self):
        oldVat = currentVat.get()
        if oldVat is not None:
            raise RuntimeError("Implementation error: Attempted to nest vat")
        currentVat.set(self.vat)
        return self.vat

    def __exit__(self, *args):
        oldVat = currentVat.get()
        if oldVat is not self.vat:
            raise RuntimeError("Implementation error: Who touched my vat!?")
        currentVat.set(None)


class CurrentVatProxy(Object):

    # Copy documentation from Vat.
    __doc__ = Vat.__doc__

    def toString(self):
        vat = currentVat.get()
        return vat.toString()

    def callAtom(self, atom, args):
        vat = currentVat.get()
        return vat.callAtom(atom, args)

    def respondingAtoms(self):
        vat = currentVat.get()
        return vat.respondingAtoms()


class VatManager(object):
    """
    A collection of vats.
    """

    def __init__(self):
        self.vats = []

    def anyVatHasTurns(self):
        for vat in self.vats:
            if vat.hasTurns():
                return True
        return False
