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

from rpython.rlib.rthread import ThreadLocalReference, allocate_lock

from typhon import log
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, UserException, userError
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.root import Object
from typhon.objects.data import StrObject


RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
SEED_1 = getAtom(u"seed", 1)
SPROUT_2 = getAtom(u"sprout", 2)


class VatCheckpointed(Exception):
    """The raising vat decided to abort its current turn.

    "Arrakis teaches the attitude of the knife — chopping off what's incomplete
    and saying: ‘Now it's complete because it's ended here.’"
    """


@autohelp
class Vat(Object):
    """
    Turn management and object isolation.
    """

    name = u"pa"

    def __init__(self, manager, uv_loop, name=None, checkpoints=0):
        assert checkpoints != 0, "No, you can't create a zero-checkpoint vat"
        self.checkpoints = checkpoints

        self._manager = manager
        self.uv_loop = uv_loop

        if name is not None:
            self.name = name

        self._callbacks = []

        self._pendingLock = allocate_lock()
        self._pending = []

    def log(self, message, tags=[]):
        log.log(["vat"] + tags, u"Vat %s: %s" % (self.name, message))

    def toString(self):
        if self.checkpoints >= 0:
            checkpoints = u"%d checkpoints left" % self.checkpoints
        else:
            checkpoints = u"immortal"
        return u"<vat(%s, %s, %d turns pending)>" % (self.name, checkpoints,
                                                     len(self._pending))

    @method("Any", "Any")
    def seed(self, f):
        from typhon.objects.collections.maps import EMPTY_MAP
        if not f.auditedBy(deepFrozenStamp):
            self.log(u"seed/1: Warning: Seeded receiver is not DeepFrozen")
            self.log(u"seed/1: Warning: This is gonna be an error soon!")
        from typhon.objects.refs import packLocalRef
        return packLocalRef(self.send(f, RUN_0, [], EMPTY_MAP), self,
                            currentVat.get())

    @method("Any", "Str", "Int")
    def sprout(self, name, checkpoints):
        vat = Vat(self._manager, self.uv_loop, name,
                  checkpoints=checkpoints)
        self._manager.vats.append(vat)
        return vat

    def checkpoint(self, points=1):
        # If we're immortal, then pass. Otherwise, if we can perform the
        # deduction, then do it; if we can't, then error out.
        if self.checkpoints < 0:
            # Immortal.
            pass
        elif self.checkpoints >= points:
            # This can leave us with, at worst, zero points, which will render
            # us non-immortal and guaranteed to raise on the next checkpoint.
            self.checkpoints -= points
        else:
            raise VatCheckpointed("Out of checkpoints")

    def send(self, target, atom, args, namedArgs):
        from typhon.objects.refs import makePromise
        promise, resolver = makePromise()
        with self._pendingLock:
            self._pending.append((resolver, target, atom, args, namedArgs))
            self.log(u"Planning to send: %s<-%s(%s) (resolver: yes)" %
                     (target.toQuote(), atom.verb,
                      u", ".join([arg.toQuote() for arg in args])))
        return promise

    def sendOnly(self, target, atom, args, namedArgs):
        with self._pendingLock:
            self._pending.append((None, target, atom, args, namedArgs))
            self.log(u"Planning to send: %s<-%s(%s) (resolver: no)" %
                     (target.toQuote(), atom.verb,
                      u", ".join([arg.toQuote() for arg in args])))

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

        self.log(u"Taking turn: %s<-%s(%s) (resolver: %s)" %
                 (target.toQuote(), atom.verb,
                  u", ".join([arg.toQuote() for arg in args]),
                  u"yes" if resolver is not None else u"no"))
        if resolver is None:
            try:
                # callOnly/sendOnly.
                if isinstance(target, Promise):
                    target.sendOnly(atom, args, namedArgs)
                else:
                    # Oh, that's right; we don't do callOnly since it's silly.
                    target.callAtom(atom, args, namedArgs)
            except UserException as ue:
                self.log(u"Uncaught user exception while taking turn"
                         u" (and no resolver): %s" %
                         ue.formatError().decode("utf-8"),
                         tags=["serious"])
            except VatCheckpointed:
                self.log(u"Ran out of checkpoints while taking turn",
                         tags=["serious"])
            except Ejecting:
                self.log(u"Ejector tried to escape vat turn boundary",
                         tags=["serious"])

        else:
            from typhon.objects.collections.maps import ConstMap, monteMap
            from typhon.objects.exceptions import sealException
            from typhon.objects.refs import Smash

            # XXX monteMap()
            mirandaArgs = monteMap()
            mirandaArgs[StrObject(u"FAIL")] = Smash(resolver)
            namedArgs = ConstMap(namedArgs._or(mirandaArgs))
            try:
                # call/send.
                if isinstance(target, Promise):
                    result = target.send(atom, args, namedArgs)
                else:
                    result = target.callAtom(atom, args, namedArgs)
                # Resolver may be invoked from the code in this turn, so
                # strict=False to skip this if already resolved.
                resolver.resolve(result, strict=False)
            except UserException as ue:
                resolver.smash(sealException(ue))
            except VatCheckpointed:
                self.log(u"Ran out of checkpoints while taking turn; breaking resolver",
                         tags=["serious"])
                resolver.smash(sealException(userError(u"Vat ran out of checkpoints")))
            except Ejecting:
                self.log(u"Ejector tried to escape vat turn boundary",
                         tags=["serious"])
                resolver.smash(sealException(userError(u"Ejector tried to escape from vat")))

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
    return Vat(None, None, name="testing", checkpoints=1000)


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
