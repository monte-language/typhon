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
from typhon.env import finalize
from typhon.errors import Refused, WrongType, userError
from typhon.objects.auditors import (auditedBy, deepFrozenGuard,
                                     deepFrozenStamp, selfless)
from typhon.objects.collections.lists import (ConstList, listFromIterable,
                                              unwrapList)
from typhon.objects.collections.maps import EMPTY_MAP, ConstMap
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import (BytesObject, DoubleObject, IntObject,
                                 StrObject, bytesToString, makeSourceSpan,
                                 unwrapBytes, unwrapInt, unwrapStr,
                                 unwrapChar)
from typhon.objects.ejectors import throw, theThrower
from typhon.objects.equality import Equalizer
from typhon.objects.iteration import loop
from typhon.objects.guards import (BindingGuard, FinalSlotGuardMaker,
                                   VarSlotGuardMaker, anyGuard, sameGuardMaker,
                                   subrangeGuardMaker)
from typhon.objects.printers import toString
from typhon.objects.refs import Promise, RefOps, resolution
from typhon.objects.root import Object, audited, runnable
from typhon.objects.slots import Binding, FinalSlot, VarSlot
from typhon.vats import currentVat

ASTYPE_0 = getAtom(u"asType", 0)
BROKEN_0 = getAtom(u"broken", 0)
CALLWITHPAIR_2 = getAtom(u"callWithPair", 2)
CALLWITHPAIR_3 = getAtom(u"callWithPair", 3)
CALL_3 = getAtom(u"call", 3)
CALLWITHMESSAGE_2 = getAtom(u"callWithMessage", 2)
CALL_4 = getAtom(u"call", 4)
COERCE_2 = getAtom(u"coerce", 2)
FAILURELIST_1 = getAtom(u"failureList", 1)
FROMBYTES_1 = getAtom(u"fromBytes", 1)
FROMBYTES_2 = getAtom(u"fromBytes", 2)
FROMCHARS_1 = getAtom(u"fromChars", 1)
FROMINTS_1 = getAtom(u"fromInts", 1)
FROMITERABLE_1 = getAtom(u"fromIterable", 1)
FROMPAIRS_1 = getAtom(u"fromPairs", 1)
FROMSTRING_1 = getAtom(u"fromString", 1)
FROMSTRING_2 = getAtom(u"fromString", 2)
MAKEFINALSLOT_2 = getAtom(u"makeFinalSlot", 2)
MAKEVARSLOT_2 = getAtom(u"makeVarSlot", 2)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)
SENDONLY_3 = getAtom(u"sendOnly", 3)
SEND_3 = getAtom(u"send", 3)
SENDONLY_4 = getAtom(u"sendOnly", 4)
SEND_4 = getAtom(u"send", 4)
TOQUOTE_1 = getAtom(u"toQuote", 1)
TOSTRING_1 = getAtom(u"toString", 1)


@autohelp
@audited.DF
class TraceLn(Object):
    """
    Write a line to the trace log.

    This object is a Typhon standard runtime `traceln`. It prints prefixed
    lines to stderr.
    """

    def toString(self):
        return u"<traceln>"

    def recv(self, atom, args):
        if atom.verb == u"run":
            guts = u", ".join([obj.toQuote() for obj in args])
            debug_print("TRACE: [%s]" % guts.encode("utf-8"))
            return NullObject
        raise Refused(self, atom, args)


@autohelp
@audited.DF
class MakeList(Object):
    """
    A maker of `List`s.
    """

    def toString(self):
        return u"<makeList>"

    def recv(self, atom, args):
        if atom.verb == u"run":
            return ConstList(args)

        if atom is FROMITERABLE_1:
            return ConstList(listFromIterable(args[0])[:])

        raise Refused(self, atom, args)

theMakeList = MakeList()


@runnable(FROMPAIRS_1, [deepFrozenStamp])
def makeMap(pairs):
    """
    Given a `List[Pair]`, produce a `Map`.
    """

    return ConstMap.fromPairs(pairs)

theMakeMap = makeMap()


@autohelp
@audited.DF
class MakeDouble(Object):
    """
    A maker of `Double`s.
    """

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
@audited.DF
class MakeInt(Object):
    """
    A maker of `Int`s.
    """

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
            return IntObject(int(unwrapBytes(args[0])))

        if atom is FROMBYTES_2:
            bs = unwrapBytes(args[0])
            radix = unwrapInt(args[1])
            try:
                v = int(bs, radix)
            except ValueError:
                raise userError(u"Invalid literal for base %d: %s" % (
                        radix, bytesToString(bs)))
            return IntObject(v)

        raise Refused(self, atom, args)


@autohelp
@audited.DF
class MakeString(Object):
    """
    A maker of `Str`s.
    """

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
@audited.DF
class MakeBytes(Object):
    """
    A maker of `Bytes`.
    """

    def toString(self):
        return u"<makeBytes>"

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            return BytesObject("".join([chr(ord(c))
                                        for c in unwrapStr(args[0])]))

        if atom is FROMINTS_1:
            data = unwrapList(args[0])
            return BytesObject("".join([chr(unwrapInt(i)) for i in data]))

        raise Refused(self, atom, args)


@autohelp
@audited.DF
class SlotBinder(Object):
    """
    Implementation of bind-pattern syntax for forward declarations.
    """

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

    def auditorStamps(self):
        if self.guard.auditedBy(deepFrozenStamp):
            return [deepFrozenStamp]
        else:
            return []

    def recv(self, atom, args):
        if atom is RUN_2:
            return Binding(args[0], self.guard)
        raise Refused(self, atom, args)


@autohelp
@audited.DF
class MObject(Object):
    """
    Miscellaneous vat management and quoting services.
    """

    def toString(self):
        return u"M"

    def recv(self, atom, args):
        if atom is CALLWITHPAIR_2 or atom is CALLWITHPAIR_3:
            target = args[0]
            pair = unwrapList(args[1])
            if len(pair) not in (2, 3):
                raise userError(u"callWithPair/2 requires a pair!")
            if len(pair) == 3:
                namedArgs = pair[2]
            else:
                namedArgs = EMPTY_MAP
            sendVerb = unwrapStr(pair[0])
            sendArgs = unwrapList(pair[1])
            rv = target.call(sendVerb, sendArgs, namedArgs)
            if rv is None:
                print "callWithPair/2: Returned None:", \
                      target.__class__.__name__, sendVerb.encode("utf-8")
                raise RuntimeError("Implementation error")
            return rv

        if atom is CALL_3 or atom is CALL_4:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            if len(args) == 3:
                namedArgs = EMPTY_MAP
            else:
                namedArgs = args[3]
            rv = target.call(sendVerb, sendArgs, namedArgs)
            if rv is None:
                print "call/3: Returned None:", target.__class__.__name__, \
                      sendVerb.encode("utf-8")
                raise RuntimeError("Implementation error")
            return rv

        if atom is SENDONLY_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            vat.sendOnly(target, sendAtom, sendArgs, EMPTY_MAP)
            return NullObject

        if atom is SEND_3:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            # Signed, sealed, delivered, I'm yours.
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            return vat.send(target, sendAtom, sendArgs, EMPTY_MAP)

        if atom is CALLWITHMESSAGE_2:
            target = args[0]
            msg = unwrapList(args[1])
            if len(msg) != 3:
                raise userError(
                    u"callWithPair/2 requires a [verb, args, namedArgs] triple")
            sendVerb = unwrapStr(msg[0])
            sendArgs = unwrapList(msg[1])
            sendNamedArgs = resolution(msg[2])
            if not isinstance(sendNamedArgs, ConstMap):
                raise WrongType(u"namedArgs must be a ConstMap")
            rv = target.call(sendVerb, sendArgs, sendNamedArgs)
            if rv is None:
                print "callWithPair/2: Returned None:", \
                      target.__class__.__name__, sendVerb.encode("utf-8")
                raise RuntimeError("Implementation error")
            return rv

        if atom is CALL_4:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            sendNamedArgs = resolution(args[3])
            if not isinstance(sendNamedArgs, ConstMap):
                raise WrongType(u"namedArgs must be a ConstMap")
            rv = target.call(sendVerb, sendArgs, sendNamedArgs)
            if rv is None:
                print "call/3: Returned None:", target.__class__.__name__, \
                      sendVerb.encode("utf-8")
                raise RuntimeError("Implementation error")
            return rv

        if atom is SENDONLY_4:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            sendNamedArgs = resolution(args[3])
            if not isinstance(sendNamedArgs, ConstMap):
                raise WrongType(u"namedArgs must be a ConstMap")
            # Signed, sealed, delivered, I'm yours.
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            return vat.sendOnly(target, sendAtom, sendArgs, sendNamedArgs)

        if atom is SEND_4:
            target = args[0]
            sendVerb = unwrapStr(args[1])
            sendArgs = unwrapList(args[2])
            sendNamedArgs = resolution(args[3])
            if not isinstance(sendNamedArgs, ConstMap):
                raise WrongType(u"namedArgs must be a ConstMap")
            # Signed, sealed, delivered, I'm yours.
            sendAtom = getAtom(sendVerb, len(sendArgs))
            vat = currentVat.get()
            return vat.send(target, sendAtom, sendArgs, sendNamedArgs)

        if atom is TOQUOTE_1:
            return StrObject(args[0].toQuote())

        if atom is TOSTRING_1:
            return StrObject(toString(args[0]))

        raise Refused(self, atom, args)

theFinalSlotGuardMaker = FinalSlotGuardMaker()
theVarSlotGuardMaker = VarSlotGuardMaker()


@autohelp
@audited.DF
class FinalSlotMaker(Object):
    """
    A maker of final slots.
    """

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
@audited.DF
class VarSlotMaker(Object):
    """
    A maker of var slots.
    """

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


@runnable(COERCE_2, _stamps=[deepFrozenStamp])
def nearGuard(specimen, ej):
    """
    A guard over references to near values.

    This guard admits any near value, as well as any resolved reference to any
    near value.

    This guard is unretractable.
    """

    specimen = resolution(specimen)
    if isinstance(specimen, Promise):
        msg = u"Specimen is in non-near state %s" % specimen.state().repr
        throw(ej, StrObject(msg))
    return specimen


# Prebuild, since building on-the-fly floats from strings doesn't work in
# RPython.
Infinity = DoubleObject(float("inf"))
NaN = DoubleObject(float("nan"))

def safeScope():
    return finalize({
        u"null": NullObject,
        u"Infinity": Infinity,
        u"NaN": NaN,
        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"Any": anyGuard,
        u"Binding": BindingGuard(),
        u"DeepFrozen": deepFrozenGuard,
        u"Near": nearGuard(),
        u"Same": sameGuardMaker,
        u"Selfless": selfless,
        u"SubrangeGuard": subrangeGuardMaker,

        u"M": MObject(),
        u"Ref": RefOps(),
        u"_auditedBy": auditedBy(),
        u"_equalizer": Equalizer(),
        u"_loop": loop(),
        u"_makeBytes": MakeBytes(),
        u"_makeDouble": MakeDouble(),
        u"_makeFinalSlot": theFinalSlotMaker,
        u"_makeInt": MakeInt(),
        u"_makeList": theMakeList,
        u"_makeMap": theMakeMap,
        u"_makeSourceSpan": makeSourceSpan,
        u"_makeString": MakeString(),
        u"_makeVarSlot": VarSlotMaker(),
        u"_slotToBinding": theSlotBinder,
        u"throw": theThrower,

        u"trace": TraceLn(),
        u"traceln": TraceLn(),
    })
