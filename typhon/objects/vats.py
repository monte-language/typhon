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
from typhon.errors import Refused
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import StrObject, unwrapInt, unwrapStr
from typhon.objects.refs import UnconnectedRef, RefOps, makePromise
from typhon.objects.root import Object


BROKEN_0 = getAtom(u"broken", 0)
CALL_3 = getAtom(u"call", 3)
FAILURELIST_1 = getAtom(u"failureList", 1)
SEND_3 = getAtom(u"send", 3)
TOSTRING_1 = getAtom(u"toString", 1)


class Vat(Object):
    """
    Turn management and object isolation.
    """

    def __init__(self, reactor):
        # XXX should define a lock here
        # XXX should lock all accesses of _pending
        self._pending = []

        self._reactor = reactor

    def repr(self):
        return "<vat (%d pending)>" % (len(self._pending),)

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
        result = target.call(atom.verb, args)
        if resolver is not None:
            resolver.resolve(result)


class MObject(Object):
    """
    Miscellaneous vat management and quoting services.
    """

    def __init__(self, vat):
        self._vat = vat

    def repr(self):
        return "<M>"

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

        if atom is TOSTRING_1:
            return StrObject(args[0].toString())

        raise Refused(atom, args)


class BooleanFlow(Object):

    def __init__(self, vat):
        self._vat = vat

    def repr(self):
        return "<booleanFlow>"

    def recv(self, atom, args):
        if atom is BROKEN_0:
            # broken/*: Create an UnconnectedRef.
            return self.broken()

        if atom is FAILURELIST_1:
            length = unwrapInt(args[0])
            refs = [self.broken()] * length
            return ConstList([wrapBool(False)] + refs)

        raise Refused(atom, args)

    def broken(self):
        return UnconnectedRef(StrObject(u"Boolean flow expression failed"),
                self._vat)


def vatScope(vat):
    return {
        u"M": MObject(vat),
        u"Ref": RefOps(vat),
        u"__booleanFlow": BooleanFlow(vat),
    }
