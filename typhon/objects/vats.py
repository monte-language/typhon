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

from typhon.errors import Refused
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject
from typhon.objects.refs import UnconnectedRef, RefOps, makePromise
from typhon.objects.root import Object


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

    def recv(self, verb, args):
        raise Refused(verb, args)

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
        target, verb, args = message
        result = target.recv(verb, args)
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

    def recv(self, verb, args):
        if verb == u"send" and len(args) == 3:
            target = args[0]
            sendVerb = args[1]
            sendArgs = args[2]
            if isinstance(sendVerb, StrObject):
                if isinstance(sendArgs, ConstList):
                    # Signed, sealed, delivered, I'm yours.
                    package = target, sendVerb._s, unwrapList(sendArgs)
                    return self._vat.send(package)
        raise Refused(verb, args)


class BooleanFlow(Object):

    def __init__(self, vat):
        self._vat = vat

    def repr(self):
        return "<booleanFlow>"

    def recv(self, verb, args):
        if verb == u"broken":
            # broken/*: Create an UnconnectedRef.
            return self.broken()

        if verb == u"failureList" and len(args) == 1:
            length = args[0]
            if isinstance(length, IntObject):
                i = length.getInt()
                refs = [self.broken()] * i
                return ConstList([wrapBool(False)] + refs)
        raise Refused(verb, args)

    def broken(self):
        return UnconnectedRef(StrObject(u"Boolean flow expression failed"),
                self._vat)


def vatScope(vat):
    return {
        u"M": MObject(vat),
        u"Ref": RefOps(vat),
        u"__booleanFlow": BooleanFlow(vat),
    }
