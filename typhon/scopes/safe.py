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
from typhon.errors import WrongType, userError
from typhon.objects.auditors import (auditedBy, deepFrozenGuard,
                                     deepFrozenStamp, selfless)
from typhon.objects.collections.helpers import asSet, emptySet
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import ConstMap
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import Infinity, NaN, makeSourceSpan, unwrapStr
from typhon.objects.ejectors import throwStr, theThrower
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

    def writeTracePreamble(self):
        vat = currentVat.get()
        self.writeLine(u"TRACE: From vat " + vat.name)

    def writeTraceLine(self, line):
        self.writeLine(u" ~ " + line)

    @method("Void", "Any")
    def exception(self, problem):
        """
        Print an exception to the debug log.
        """

        self.writeTracePreamble()

        if isinstance(problem, SealedException):
            ue = problem.ue
            self.writeTraceLine(u"Problem: " + ue.getPayload().toString())
            for crumb in ue.formatTrail():
                self.writeTraceLine(crumb)
        else:
            self.writeTraceLine(u"Problem (unsealed): " + problem.toString())

    @method("Void", "*Any")
    def run(self, args):
        self.writeTracePreamble()

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

    @method("Any", "Any", "List")
    def callWithMessage(self, target, message):
        """
        Pass a message of `[verb :Str, args :List, namedArgs :Map]` to an
        object.
        """

        if len(message) != 3:
            raise userError(
                u"callWithPair/2 requires a [verb, args, namedArgs] triple")
        verb = unwrapStr(message[0])
        args = unwrapList(message[1])
        namedArgs = resolution(message[2])
        if not isinstance(namedArgs, ConstMap):
            raise WrongType(u"namedArgs must be a ConstMap")
        return target.call(verb, args, namedArgs)

    @method("Any", "Any", "Str", "List", "Any")
    def call(self, target, verb, args, namedArgs):
        """
        Pass a message to an object.
        """

        if not isinstance(namedArgs, ConstMap):
            raise WrongType(u"namedArgs must be a ConstMap")
        return target.call(verb, args, namedArgs)

    @method("Void", "Any", "Str", "List", "Any")
    def sendOnly(self, target, verb, args, namedArgs):
        """
        Send a message to an object.

        The message will be delivered on some subsequent turn.
        """

        namedArgs = resolution(namedArgs)
        if not isinstance(namedArgs, ConstMap):
            raise WrongType(u"namedArgs must be a ConstMap")
        # Signed, sealed, delivered, I'm yours.
        sendAtom = getAtom(verb, len(args))
        vat = currentVat.get()
        vat.sendOnly(target, sendAtom, args, namedArgs)

    @method("Any", "Any", "Str", "List", "Any")
    def send(self, target, verb, args, namedArgs):
        """
        Send a message to an object, returning a promise for the message
        delivery.

        The promise will be fulfilled after successful delivery, or smashed
        upon error.

        The message will be delivered on some subsequent turn.
        """

        namedArgs = resolution(namedArgs)
        if not isinstance(namedArgs, ConstMap):
            raise WrongType(u"namedArgs must be a ConstMap")
        # Signed, sealed, delivered, I'm yours.
        sendAtom = getAtom(verb, len(args))
        vat = currentVat.get()
        return vat.send(target, sendAtom, args, namedArgs)

    @method("Str", "Any")
    def toQuote(self, obj):
        """
        Convert an object to a quoted string representation.
        """

        return obj.toQuote()

    @method("Str", "Any", _verb="toString")
    def _toString(self, obj):
        """
        Convert an object to an unquoted string representation.
        """

        return toString(obj)

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

theVarSlotMaker = VarSlotMaker()


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
            throwStr(ej, msg)
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
        u"FinalSlot": theFinalSlotGuardMaker,
        u"Near": NearGuard(),
        u"Same": sameGuardMaker,
        u"Selfless": selfless,
        u"SubrangeGuard": subrangeGuardMaker,
        u"VarSlot": theVarSlotGuardMaker,

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
        u"_makeVarSlot": theVarSlotMaker,
        u"_slotToBinding": theSlotBinder,
        u"throw": theThrower,

        u"trace": TraceLn(),
        u"traceln": TraceLn(),
    })
