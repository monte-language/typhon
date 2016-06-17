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
from typhon.autohelp import autohelp, method
from typhon.errors import Refused, WrongType, userError
from typhon.objects.auditors import (auditedBy, deepFrozenGuard,
                                     deepFrozenStamp, selfless)
from typhon.objects.collections.helpers import asSet, emptySet
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import EMPTY_MAP, ConstMap
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import (StrObject, Infinity, NaN, makeSourceSpan,
                                 unwrapStr)
from typhon.objects.ejectors import throw, theThrower
from typhon.objects.equality import Equalizer
from typhon.objects.exceptions import SealedException
from typhon.objects.iteration import loop
from typhon.objects.guards import (BindingGuard, FinalSlotGuardMaker,
                                   VarSlotGuardMaker, anyGuard, sameGuardMaker,
                                   subrangeGuardMaker)
from typhon.objects.makers import (theMakeBytes, theMakeDouble, theMakeInt,
                                   theMakeList, theMakeMap, theMakeStr)
from typhon.objects.printers import toString
from typhon.objects.refs import Promise, RefOps, resolution
from typhon.objects.root import Object, audited
from typhon.objects.slots import Binding, FinalSlot, VarSlot, finalize
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

    Call `.exception(problem)` to print a problem to stderr, including
    a formatted traceback.
    """

    def toString(self):
        return u"<traceln>"

    def writeLine(self, line):
        debug_print(line.encode("utf-8"))

    def writeTraceLine(self, line):
        debug_print("TRACE: [%s]" % line.encode("utf-8"))

    @method("Void", "Any")
    def exception(self, problem):
        if isinstance(problem, SealedException):
            self.writeLine(u"Problem: %s" % problem.value.toString())
            for crumb in problem.trail:
                self.writeLine(crumb)
        else:
            self.writeLine(u"Problem: %s" % problem.toString())

    @method("Void", "*Any")
    def run(self, args):
        guts = u", ".join([obj.toQuote() for obj in args])
        self.writeTraceLine(guts)


@autohelp
@audited.DF
class SlotBinder(Object):
    """
    Implementation of bind-pattern syntax for forward declarations.
    """

    @method("Any", "Any")
    def run(self, thing):
        return SpecializedSlotBinder(thing)

    @method("Any", "Any", "Any", _verb="run")
    def _run(self, specimen, ej):
        return Binding(specimen, anyGuard)

theSlotBinder = SlotBinder()


@autohelp
class SpecializedSlotBinder(Object):

    _immutable_fields_ = "guard",

    def __init__(self, guard):
        self.guard = guard

    def auditorStamps(self):
        if self.guard.auditedBy(deepFrozenStamp):
            return asSet([deepFrozenStamp])
        else:
            return emptySet

    @method("Any", "Any", "Any")
    def run(self, specimen, ej):
        return Binding(specimen, self.guard)


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

    @method("Any")
    def asType(self):
        return theFinalSlotGuardMaker

    @method("Any", "Any", "Any", "Any")
    def run(self, guard, specimen, ej):
        if guard != NullObject:
            val = guard.call(u"coerce", [specimen, ej])
            g = guard
        else:
            val = specimen
            g = anyGuard
        return FinalSlot(val, g)

theFinalSlotMaker = FinalSlotMaker()


@autohelp
@audited.DF
class VarSlotMaker(Object):
    """
    A maker of var slots.
    """

    @method("Any")
    def asType(self):
        return theVarSlotGuardMaker

    @method("Any", "Any", "Any", "Any")
    def run(self, guard, specimen, ej):
        if guard != NullObject:
            val = guard.call(u"coerce", [specimen, ej])
            g = guard
        else:
            val = specimen
            g = anyGuard
        return VarSlot(val, g)


@autohelp
@audited.DF
class NearGuard(Object):
    """
    A guard over references to near values.

    This guard admits any near value, as well as any resolved reference to any
    near value.

    This guard is unretractable.
    """

    def toString(self):
        return u"Near"

    @method("Any", "Any", "Any")
    def coerce(self, specimen, ej):
        specimen = resolution(specimen)
        if isinstance(specimen, Promise):
            msg = u"Specimen is in non-near state %s" % specimen.state().repr
            throw(ej, StrObject(msg))
        return specimen


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
        u"Near": NearGuard(),
        u"Same": sameGuardMaker,
        u"Selfless": selfless,
        u"SubrangeGuard": subrangeGuardMaker,

        u"M": MObject(),
        u"Ref": RefOps(),
        u"_auditedBy": auditedBy(),
        u"_equalizer": Equalizer(),
        u"_loop": loop(),
        u"_makeBytes": theMakeBytes,
        u"_makeDouble": theMakeDouble,
        u"_makeFinalSlot": theFinalSlotMaker,
        u"_makeInt": theMakeInt,
        u"_makeList": theMakeList,
        u"_makeMap": theMakeMap,
        u"_makeSourceSpan": makeSourceSpan,
        u"_makeStr": theMakeStr,
        u"_makeString": theMakeStr,
        u"_makeVarSlot": VarSlotMaker(),
        u"_slotToBinding": theSlotBinder,
        u"throw": theThrower,

        u"trace": TraceLn(),
        u"traceln": TraceLn(),
    })
