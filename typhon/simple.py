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

from rpython.rlib.debug import debug_print

from typhon.atoms import getAtom
from typhon.errors import Refused, UserException
from typhon.objects.collections import (ConstList, ConstMap, ConstSet,
                                        unwrapList)
from typhon.objects.constants import BoolObject, NullObject, wrapBool
from typhon.objects.data import (CharObject, DoubleObject, IntObject,
                                 StrObject, unwrapInt, unwrapStr)
from typhon.objects.ejectors import throw
from typhon.objects.equality import Equalizer
from typhon.objects.guards import predGuard
from typhon.objects.iteration import loop
from typhon.objects.networking.endpoints import (makeTCP4ClientEndpoint,
                                                 makeTCP4ServerEndpoint)
from typhon.objects.refs import RefOps, UnconnectedRef
from typhon.objects.root import Object, runnable
from typhon.objects.slots import Binding, FinalSlot, VarSlot
from typhon.objects.tests import UnitTest
from typhon.vats import currentVat


BROKEN_0 = getAtom(u"broken", 0)
CALL_3 = getAtom(u"call", 3)
EJECT_2 = getAtom(u"eject", 2)
FAILURELIST_1 = getAtom(u"failureList", 1)
FROMPAIRS_1 = getAtom(u"fromPairs", 1)
MATCHMAKER_1 = getAtom(u"matchMaker", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
SENDONLY_3 = getAtom(u"sendOnly", 3)
SEND_3 = getAtom(u"send", 3)
SUBSTITUTE_1 = getAtom(u"substitute", 1)
TOQUOTE_1 = getAtom(u"toQuote", 1)
TOSTRING_1 = getAtom(u"toString", 1)
VALUEMAKER_1 = getAtom(u"valueMaker", 1)


@predGuard
def boolGuard(specimen):
    return isinstance(specimen, BoolObject)


@predGuard
def charGuard(specimen):
    return isinstance(specimen, CharObject)


@predGuard
def doubleGuard(specimen):
    return isinstance(specimen, DoubleObject)


@predGuard
def intGuard(specimen):
    return isinstance(specimen, IntObject)


@predGuard
def strGuard(specimen):
    return isinstance(specimen, StrObject)


@predGuard
def listGuard(specimen):
    return isinstance(specimen, ConstList)


@predGuard
def mapGuard(specimen):
    return isinstance(specimen, ConstMap)


@predGuard
def setGuard(specimen):
    return isinstance(specimen, ConstSet)


class TraceLn(Object):
    def toString(self):
        return u"<traceln>"

    def callAtom(self, atom, args):
        if atom.verb == u"run":
            reprs = [obj.toQuote() for obj in args]
            debug_print(u"TRACE:", reprs)
            return NullObject
        raise Refused(self, atom, args)


class MakeList(Object):
    def toString(self):
        return u"<makeList>"

    def callAtom(self, atom, args):
        if atom.verb == u"run":
            return ConstList(args)
        raise Refused(self, atom, args)


@runnable(FROMPAIRS_1)
def makeMap(args):
    return ConstMap.fromPairs(args[0])


class Throw(Object):

    def toString(self):
        return u"<throw>"

    def recv(self, atom, args):
        if atom is RUN_1:
            raise UserException(args[0])

        if atom is EJECT_2:
            return throw(args[0], args[1])

        raise Refused(self, atom, args)


@runnable(RUN_2)
def slotToBinding(args):
    # XXX don't really care much about this right now
    specimen = args[0]
    # ej = args[1]
    return Binding(specimen)


# XXX could probably move to prelude now?
class BooleanFlow(Object):

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
        return UnconnectedRef(u"Boolean flow expression failed")


class MObject(Object):
    """
    Miscellaneous vat management and quoting services.
    """

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
            vat = currentVat.get()
            return vat.sendOnly(target, sendVerb, sendArgs)

        if atom is SEND_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            vat = currentVat.get()
            return vat.send(target, sendVerb, sendArgs)

        if atom is TOQUOTE_1:
            return StrObject(args[0].toQuote())

        if atom is TOSTRING_1:
            return StrObject(args[0].toString())

        raise Refused(self, atom, args)


@runnable(RUN_1)
def makeVarSlot(args):
    return VarSlot(args[0])


@runnable(RUN_1)
def makeFinalSlot(args):
    return FinalSlot(args[0])


def simpleScope():
    return {
        u"null": NullObject,

        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"Bool": boolGuard(),
        u"Char": charGuard(),
        u"Double": doubleGuard(),
        u"Int": intGuard(),
        u"List": listGuard(),
        u"Map": mapGuard(),
        u"Set": setGuard(),
        u"Str": strGuard(),

        u"M": MObject(),
        u"Ref": RefOps(),
        u"__booleanFlow": BooleanFlow(),
        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": MakeList(),
        u"__makeMap": makeMap(),
        u"__slotToBinding": slotToBinding(),
        u"_makeFinalSlot": makeFinalSlot(),
        u"_makeVarSlot": makeVarSlot(),
        u"throw": Throw(),
        u"trace": TraceLn(),
        u"traceln": TraceLn(),

        u"unittest": UnitTest(),

        u"makeTCP4ClientEndpoint": makeTCP4ClientEndpoint(),
        u"makeTCP4ServerEndpoint": makeTCP4ServerEndpoint(),
    }
