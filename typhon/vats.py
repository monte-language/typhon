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
from typhon.objects.data import StrObject, unwrapStr


RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
SEED_1 = getAtom(u"seed", 1)
SPROUT_1 = getAtom(u"sprout", 1)


@autohelp
class Vat(Object):
    """
    Turn management and object isolation.
    """

    name = u"pa"

    def __init__(self, manager, uv_loop, name=None):
        self._manager = manager
        self.uv_loop = uv_loop

        if name is not None:
            self.name = name

        self._callbacks = []

        self._pendingLock = allocate_lock()
        self._pending = []

    def toString(self):
        return u"<vat(%s, %d turns pending)>" % (self.name, len(self._pending))

    def recv(self, atom, args):
        from typhon.objects.collections import EMPTY_MAP
        if atom is SEED_1:
            f = args[0]
            if not f.auditedBy(deepFrozenStamp):
                print "seed/1: Warning: Seeded receiver is not DeepFrozen"
                print "seed/1: Warning: This is gonna be an error soon!"
            from typhon.objects.refs import LocalVatRef
            return LocalVatRef(self.send(f, RUN_0, [], EMPTY_MAP), self)

        if atom is SPROUT_1:
            name = unwrapStr(args[0])
            vat = Vat(self._manager, self.uv_loop, name)
            self._manager.vats.append(vat)
            return vat

        raise Refused(self, atom, args)

    def send(self, target, atom, args, namedArgs):
        from typhon.objects.refs import makePromise
        promise, resolver = makePromise()
        with self._pendingLock:
            self._pending.append((resolver, target, atom, args, namedArgs))
            # print "Planning to send", target, atom, args
        return promise

    def sendOnly(self, target, atom, args, namedArgs):
        with self._pendingLock:
            self._pending.append((None, target, atom, args, namedArgs))
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
            resolver, target, atom, args, namedArgs = self._pending.pop(0)

        # If the target is a promise, then we should send to it instead of
        # calling. Try to resolve it as much as possible first, though.
        target = resolution(target)

        # print "Taking turn:", self, resolver, target, atom, args
        if resolver is None:
            try:
                # callOnly/sendOnly.
                if isinstance(target, Promise):
                    target.sendOnly(atom, args, namedArgs)
                else:
                    # Oh, that's right; we don't do callOnly since it's silly.
                    target.callAtom(atom, args, namedArgs)
            except UserException as ue:
                print "Uncaught exception while taking turn:", ue.formatError()

        else:
            from typhon.objects.collections import ConstMap, monteDict
            from typhon.objects.refs import Smash
            _d = monteDict()
            _d[StrObject(u"FAIL")] = Smash(resolver)
            MIRANDA_ARGS = ConstMap(_d)
            namedArgs = namedArgs._or(MIRANDA_ARGS)
            try:
                # call/send.
                if isinstance(target, Promise):
                    result = target.send(atom, args, namedArgs)
                else:
                    result = target.callAtom(atom, args, namedArgs)
                # Resolver may be invoked from the code in this turn, so
                # strict=False to skip this if already resolved.
                resolver.resolve(result, strict=False)
            except UserException, ue:
                from typhon.objects.exceptions import sealException
                resolver.smash(sealException(ue))

    def takeSomeTurns(self):
        # Limit the number of continuous turns to keep network latency low.
        # It's possible that more turns will be queued while we're taking
        # these turns, after all.
        count = len(self._pending)
        # print "Taking", count, "turn(s) on", self.repr()
        for _ in range(count):
            self.takeTurn()


currentVat = ThreadLocalReference(Vat)


def testingVat():
    return Vat(None, None, name="testing")


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

    def callAtom(self, atom, args, namedArgsMap):
        vat = currentVat.get()
        return vat.callAtom(atom, args, namedArgsMap)

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
