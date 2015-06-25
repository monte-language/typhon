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
from rpython.rlib.rstruct.ieee import unpack_float

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.objects.auditors import auditedBy, deepFrozenStamp, selfless
from typhon.objects.collections import ConstList, ConstMap, unwrapList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import (DoubleObject, IntObject, StrObject,
                                 makeSourceSpan, unwrapInt, unwrapStr,
                                 unwrapChar)
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.equality import Equalizer
from typhon.objects.iteration import loop
from typhon.objects.guards import (anyGuard, FinalSlotGuardMaker,
                                   VarSlotGuardMaker)
from typhon.objects.help import Help
from typhon.objects.refs import RefOps, UnconnectedRef
from typhon.objects.root import Object, runnable
from typhon.objects.slots import Binding, FinalSlot, VarSlot
from typhon.objects.tests import UnitTest
from typhon.vats import currentVat

ASTYPE_0 = getAtom(u"asType", 0)
BROKEN_0 = getAtom(u"broken", 0)
CALLWITHPAIR_2 = getAtom(u"callWithPair", 2)
CALL_3 = getAtom(u"call", 3)
EJECT_2 = getAtom(u"eject", 2)
FAILURELIST_1 = getAtom(u"failureList", 1)
FROMBYTES_1 = getAtom(u"fromBytes", 1)
FROMCHARS_1 = getAtom(u"fromChars", 1)
FROMITERABLE_1 = getAtom(u"fromIterable", 1)
FROMPAIRS_1 = getAtom(u"fromPairs", 1)
FROMSTRING_1 = getAtom(u"fromString", 1)
FROMSTRING_2 = getAtom(u"fromString", 2)
MAKEFINALSLOT_2 = getAtom(u"makeFinalSlot", 2)
MAKEVARSLOT_2 = getAtom(u"makeVarSlot", 2)
MATCHMAKER_1 = getAtom(u"matchMaker", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)
SENDONLY_3 = getAtom(u"sendOnly", 3)
SEND_3 = getAtom(u"send", 3)
SUBSTITUTE_1 = getAtom(u"substitute", 1)
TOQUOTE_1 = getAtom(u"toQuote", 1)
TOSTRING_1 = getAtom(u"toString", 1)
VALUEMAKER_1 = getAtom(u"valueMaker", 1)


class TraceLn(Object):
    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<traceln>"

    def callAtom(self, atom, args):
        if atom.verb == u"run":
            debug_print("TRACE: [")
            for obj in args:
                debug_print("    ", obj.toQuote().encode("utf-8"))
            debug_print("]")
            return NullObject
        raise Refused(self, atom, args)


class MakeList(Object):
    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<makeList>"

    def callAtom(self, atom, args):
        if atom.verb == u"run":
            return ConstList(args)

        if atom is FROMITERABLE_1:
            return ConstList(self.fromIterable(args[0])[:])

        raise Refused(self, atom, args)

    def fromIterable(self, obj):
        rv = []
        iterator = obj.call(u"_makeIterator", [])
        ej = Ejector()
        while True:
            try:
                l = unwrapList(iterator.call(u"next", [ej]))
                if len(l) != 2:
                    raise userError(u"makeList.fromIterable/1: Invalid iterator")
                rv.append(l[1])
            except Ejecting as ex:
                if ex.ejector is ej:
                    ej.disable()
                    return rv
                raise

theMakeList = MakeList()


@runnable(FROMPAIRS_1, [deepFrozenStamp])
def makeMap(args):
    return ConstMap.fromPairs(args[0])

theMakeMap = makeMap()


@autohelp
class MakeDouble(Object):
    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<makeDouble>"

    def recv(self, atom, args):
        if atom is RUN_1:
            return DoubleObject(float(unwrapStr(args[0]).encode('utf-8')))

        if atom is FROMBYTES_1:
            data = unwrapList(args[0])
            x = unpack_float("".join([chr(unwrapInt(byte)) for byte in data]),
                             True)
            return DoubleObject(x)

        raise Refused(self, atom, args)


@autohelp
class MakeInt(Object):
    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<makeInt>"

    def recv(self, atom, args):
        if atom is RUN_1:
            return IntObject(int(unwrapStr(args[0]).encode('utf-8')))

        if atom is RUN_2:
            inp = unwrapStr(args[0])
            radix = unwrapInt(args[1])
            try:
                v = int(inp.encode("utf-8"), radix)
            except ValueError:
                raise userError(u"Invalid literal for base %d: %s" % (
                        radix, inp))
            return IntObject(v)

        if atom is FROMBYTES_1:
            data = unwrapList(args[0])
            x = unpack_float("".join([chr(unwrapInt(byte)) for byte in data]),
                             True)
            return DoubleObject(x)

        raise Refused(self, atom, args)


@autohelp
class MakeString(Object):
    stamps = [deepFrozenStamp]

    def toString(self):
        return u"<makeString>"

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            # XXX handle twineishness
            return args[0]

        if atom is FROMSTRING_2:
            # XXX handle twineishness
            return args[0]

        if atom is FROMCHARS_1:
            data = unwrapList(args[0])
            return StrObject(u"".join([unwrapChar(c) for c in data]))

        raise Refused(self, atom, args)


@autohelp
class Throw(Object):

    stamps = [deepFrozenStamp]

    def toString(self):
        return u"throw"

    def recv(self, atom, args):
        if atom is RUN_1:
            raise UserException(args[0])

        if atom is EJECT_2:
            return throw(args[0], args[1])

        raise Refused(self, atom, args)


@autohelp
class SlotBinder(Object):
    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is RUN_1:
            return SpecializedSlotBinder(args[0])
        if atom is RUN_2:
            return Binding(args[0], anyGuard)
        raise Refused(self, atom, args)

theSlotBinder = SlotBinder()


@autohelp
class SpecializedSlotBinder(Object):
    def __init__(self, guard):
        self.guard = guard
        if deepFrozenStamp in guard.stamps:
            self.stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is RUN_2:
            return Binding(args[0], self.guard)
        raise Refused(self, atom, args)


@autohelp
class MObject(Object):
    """
    Miscellaneous vat management and quoting services.
    """

    stamps = [deepFrozenStamp]

    def toString(self):
        return u"M"

    def recv(self, atom, args):
        if atom is CALLWITHPAIR_2:
            target = args[0]
            pair = unwrapList(args[1])
            if len(pair) != 2:
                raise userError(u"callWithPair/2 requires a pair!")
            sendVerb = unwrapStr(pair[0])
            sendArgs = unwrapList(pair[1])
            return target.call(sendVerb, sendArgs)

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
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            return vat.sendOnly(target, sendAtom, sendArgs)

        if atom is SEND_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            return vat.send(target, sendAtom, sendArgs)

        if atom is TOQUOTE_1:
            return StrObject(args[0].toQuote())

        if atom is TOSTRING_1:
            return StrObject(args[0].toString())

        raise Refused(self, atom, args)

theFinalSlotGuardMaker = FinalSlotGuardMaker()
theVarSlotGuardMaker = VarSlotGuardMaker()


@autohelp
class FinalSlotMaker(Object):
    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is RUN_3:
            guard, specimen, ej = args[0], args[1], args[2]
            if guard != NullObject:
                val = guard.coerce(specimen, ej)
                g = guard
            else:
                val = specimen
                g = anyGuard
            return FinalSlot(val, g)
        if atom is ASTYPE_0:
            return theFinalSlotGuardMaker
        raise Refused(self, atom, args)

theFinalSlotMaker = FinalSlotMaker()


@autohelp
class VarSlotMaker(Object):
    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is RUN_3:
            guard, specimen, ej = args[0], args[1], args[2]
            if guard != NullObject:
                val = guard.coerce(specimen, ej)
                g = guard
            else:
                val = specimen
                g = anyGuard
            return VarSlot(val, g)
        if atom is ASTYPE_0:
            return theVarSlotGuardMaker
        raise Refused(self, atom, args)


# Prebuild, since building on-the-fly floats from strings doesn't work in
# RPython.
Infinity = DoubleObject(float("inf"))
NaN = DoubleObject(float("nan"))


def safeScope():
    return {
        u"null": NullObject,
        u"any": anyGuard,
        u"Any": anyGuard,
        u"Infinity": Infinity,
        u"NaN": NaN,
        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"M": MObject(),
        u"Ref": RefOps(),
        u"Selfless": selfless,
        u"__auditedBy": auditedBy(),
        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": theMakeList,
        u"__makeMap": theMakeMap,
        u"__makeInt": MakeInt(),
        u"__makeDouble": MakeDouble(),
        u"__makeString": MakeString(),
        u"__makeSourceSpan": makeSourceSpan,
        u"__slotToBinding": theSlotBinder,
        u"_makeFinalSlot": theFinalSlotMaker,
        u"_makeVarSlot": VarSlotMaker(),
        u"help": Help(),
        u"throw": Throw(),

        u"trace": TraceLn(),
        u"traceln": TraceLn(),

        u"unittest": UnitTest(),
    }
