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
from typhon.objects.constants import wrapBool
from typhon.objects.data import StrObject, unwrapInt, unwrapStr
from typhon.objects.networking.endpoints import (MakeTCP4ClientEndpoint,
                                                 MakeTCP4ServerEndpoint)
from typhon.objects.refs import RefOps, UnconnectedRef
from typhon.objects.root import Object


BROKEN_0 = getAtom(u"broken", 0)
CALL_3 = getAtom(u"call", 3)
FAILURELIST_1 = getAtom(u"failureList", 1)
SENDONLY_3 = getAtom(u"sendOnly", 3)
SEND_3 = getAtom(u"send", 3)
TOQUOTE_1 = getAtom(u"toQuote", 1)
TOSTRING_1 = getAtom(u"toString", 1)


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

        if atom is SENDONLY_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            return self._vat.sendOnly(target, sendVerb, sendArgs)

        if atom is SEND_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            return self._vat.send(target, sendVerb, sendArgs)

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
