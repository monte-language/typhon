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
from typhon.errors import Refused, UserException
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import StrObject, unwrapInt, unwrapStr
from typhon.objects.networking.endpoints import (MakeTCP4ClientEndpoint,
                                                 MakeTCP4ServerEndpoint)
from typhon.objects.refs import (Promise, RefOps, UnconnectedRef, makePromise,
                                 resolution)
from typhon.objects.root import Object


BROKEN_0 = getAtom(u"broken", 0)
CALL_3 = getAtom(u"call", 3)
FAILURELIST_1 = getAtom(u"failureList", 1)
SEND_3 = getAtom(u"send", 3)
TOQUOTE_1 = getAtom(u"toQuote", 1)
TOSTRING_1 = getAtom(u"toString", 1)


# XXX Vat really shouldn't be an object!
class Vat(Object):
    """
    Turn management and object isolation.
    """

    def __init__(self, reactor):
        self._callbacks = []

        # XXX should define a lock here
        # XXX should lock all accesses of _pending
        self._pending = []

        self._reactor = reactor

    def toString(self):
        return u"<vat (%d pending)>" % (len(self._pending),)

    def send(self, message):
        promise, resolver = makePromise(self)
        self._pending.append((resolver, message))
        return promise

    def sendOnly(self, message):
        self._pending.append((None, message))
        return NullObject

    def hasTurns(self):
        return len(self._pending) != 0

    def takeTurn(self):
        resolver, message = self._pending.pop(0)
        target, atom, args = message

        # Ensure that the target is resolved.
        target = resolution(target)
        if isinstance(target, Promise):
            if not target.isResolved():
                # Not resolved! Put it back on the turn list.
                # print target, "is not quite resolved yet, so I'm deferring"
                self._pending.append((resolver, (target, atom, args)))
                return

        result = target.call(atom.verb, args)
        if resolver is not None:
            resolver.resolve(result)

    def afterTurn(self, callback):
        """
        After the current turn, run this callback.

        The callback must guarantee that it will *not* take turns on the vat!
        """

        self._callbacks.append(callback)

    def runCallbacks(self):
        for callback in self._callbacks:
            callback()
        self._callbacks = []

    def takeSomeTurns(self, recorder):
        # Limit the number of continuous turns to keep network latency low.
        count = min(3, len(self._pending))
        # print "Taking", count, "turn(s) on", self.toString()
        for _ in range(count):
            try:
                recorder.record("Time spent in vats", self.takeTurn)
            except UserException as ue:
                print "Caught exception while taking turn:", ue.formatError()

        self.runCallbacks()


class MObject(Object):
    """
    Miscellaneous vat management and quoting services.
    """

    def __init__(self, vat):
        self._vat = vat

    def toString(self):
        return u"<M>"

    def recv(self, atom, args):
        if atom is CALL_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            return target.call(sendVerb, sendArgs)

        if atom is SEND_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            atom = getAtom(sendVerb, len(sendArgs))
            package = target, atom, sendArgs
            return self._vat.send(package)

        if atom is TOQUOTE_1:
            return StrObject(args[0].toQuote())

        if atom is TOSTRING_1:
            return StrObject(args[0].toString())

        raise Refused(self, atom, args)


class BooleanFlow(Object):

    def __init__(self, vat):
        self._vat = vat

    def toString(self):
        return u"<booleanFlow>"

    def recv(self, atom, args):
        if atom is BROKEN_0:
            # broken/*: Create an UnconnectedRef.
            return self.broken()

        if atom is FAILURELIST_1:
            length = unwrapInt(args[0])
            refs = [self.broken()] * length
            return ConstList([wrapBool(False)] + refs)

        raise Refused(self, atom, args)

    def broken(self):
        return UnconnectedRef(u"Boolean flow expression failed", self._vat)


def vatScope(vat):
    return {
        u"M": MObject(vat),
        u"Ref": RefOps(vat),
        u"__booleanFlow": BooleanFlow(vat),
        u"makeTCP4ClientEndpoint": MakeTCP4ClientEndpoint(vat),
        u"makeTCP4ServerEndpoint": MakeTCP4ServerEndpoint(vat),
    }
