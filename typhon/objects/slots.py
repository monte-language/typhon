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
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.collections.lists import ConstList
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object, audited

_UNCALL_0 = getAtom(u"_uncall", 0)
GET_0 = getAtom(u"get", 0)
GETGUARD_0 = getAtom(u"getGuard", 0)
PUT_1 = getAtom(u"put", 1)


@autohelp
@audited.Transparent
class Binding(Object):
    """
    A slot and a guard describing the nature of the slot.
    """

    _immutable_fields_ = "slot", "guard"

    def __init__(self, slot, guard):
        self.slot = slot
        self.guard = guard

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"<binding ")])
        printer.call(u"print", [self.slot])
        printer.call(u"print", [StrObject(u" :")])
        printer.call(u"print", [self.guard])
        printer.call(u"print", [StrObject(u">")])

    def get(self):
        return self.slot

    def getValue(self):
        return self.slot.get()

    def recv(self, atom, args):
        if atom is GET_0:
            return self.get()

        if atom is GETGUARD_0:
            return self.guard

        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            from typhon.scopes.safe import theSlotBinder
            return ConstList([
                ConstList([theSlotBinder, StrObject(u"run"),
                           ConstList([self.guard])]),
                StrObject(u"run"),
                ConstList([self.slot, NullObject]),
                EMPTY_MAP])

        raise Refused(self, atom, args)


def finalBinding(value, guard):
    from typhon.objects.guards import FinalSlotGuard
    return Binding(FinalSlot(value, guard), FinalSlotGuard(guard))

def varBinding(value, guard):
    from typhon.objects.guards import VarSlotGuard
    return Binding(VarSlot(value, guard), VarSlotGuard(guard))


@autohelp
class Slot(Object):
    """
    A storage space.
    """

    _immutable_fields_ = '_guard',

    def recv(self, atom, args):
        if atom is GET_0:
            return self.get()

        if atom is GETGUARD_0:
            return self._guard

        if atom is PUT_1:
            return self.put(args[0])

        raise Refused(self, atom, args)


@audited.Transparent
class FinalSlot(Slot):

    _immutable_fields_ = "_obj", "_guard"

    def __init__(self, obj, guard):
        self._obj = obj
        self._guard = guard

    def printOn(self, out):
        out.call(u"print", [StrObject(u"<FinalSlot(")])
        out.call(u"print", [self._obj])
        out.call(u"print", [StrObject(u")>")])

    def get(self):
        return self._obj

    def put(self, value):
        raise userError(u"Can't put into a FinalSlot!")

    def recv(self, atom, args):
        if atom is _UNCALL_0:
            from typhon.scopes.safe import theFinalSlotMaker
            from typhon.objects.collections.maps import EMPTY_MAP
            return ConstList([theFinalSlotMaker, StrObject(u"run"),
                              ConstList([self._obj, self._guard, NullObject]),
                              EMPTY_MAP])
        return Slot.recv(self, atom, args)


class VarSlot(Slot):
    _immutable_fields_ = "_guard",

    def __init__(self, obj, guard):
        self._obj = obj
        self._guard = guard

    def printOn(self, out):
        out.call(u"print", [StrObject(u"<VarSlot(")])
        out.call(u"print", [self._obj])
        out.call(u"print", [StrObject(u", ")])
        out.call(u"print", [self._guard])
        out.call(u"print", [StrObject(u")>")])

    def get(self):
        return self._obj

    def put(self, value):
        from typhon.objects.ejectors import theThrower
        if self._guard is NullObject:
            self._obj = value
        else:
            self._obj = self._guard.call(u"coerce", [value, theThrower])
        return NullObject
