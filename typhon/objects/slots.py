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
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.collections import ConstList
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object

_UNCALL_0 = getAtom(u"_uncall", 0)
GET_0 = getAtom(u"get", 0)
GETGUARD_0 = getAtom(u"getGuard", 0)
PUT_1 = getAtom(u"put", 1)


@autohelp
class Binding(Object):
    """
    A slot and a guard describing the nature of the slot.
    """

    _immutable_ = True
    stamps = [selfless, transparentStamp]

    def __init__(self, slot, guard):
        self.slot = slot
        self.guard = guard

    def toString(self):
        return u"<binding for %s>" % self.slot.toString()

    def recv(self, atom, args):
        if atom is GET_0:
            return self.slot

        if atom is GETGUARD_0:
            return self.guard

        if atom is _UNCALL_0:
            from typhon.scopes.safe import theSlotBinder
            return ConstList([
                ConstList([theSlotBinder, StrObject(u"run"),
                           ConstList([self.guard])]),
                StrObject(u"run"),
                ConstList([self.slot, NullObject])])

        raise Refused(self, atom, args)


@autohelp
class FinalBinding(Object):
    """
    A binding with a final slot.

    This object is equivalent to a standard Typhon binding and Typhon final
    slot, but is more memory- and CPU-efficient.
    """

    _immutable_ = True
    stamps = [selfless, transparentStamp]

    def __init__(self, value, guard):
        self.value = value
        self.guard = guard

    def toString(self):
        return u"<final binding for %s>" % self.value.toString()

    def recv(self, atom, args):
        if atom is GET_0:
            return FinalSlot(self.value, self.guard)

        if atom is GETGUARD_0:
            from typhon.objects.guards import FinalSlotGuard
            return FinalSlotGuard(self.guard)

        if atom is _UNCALL_0:
            from typhon.objects.guards import FinalSlotGuard
            from typhon.scopes.safe import theSlotBinder
            return ConstList([
                ConstList([theSlotBinder, StrObject(u"run"),
                           ConstList([FinalSlotGuard(self.guard)])]),
                StrObject(u"run"),
                ConstList([FinalSlot(self.value, self.guard), NullObject])])

        raise Refused(self, atom, args)


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


class FinalSlot(Slot):

    _immutable_fields_ = "_obj", "_guard"
    stamps = [selfless, transparentStamp]

    def __init__(self, obj, guard):
        self._obj = obj
        self._guard = guard

    def toString(self):
        return u"<FinalSlot(%s)>" % self._obj.toString()

    def get(self):
        return self._obj

    def put(self, value):
        raise userError(u"Can't put into a FinalSlot!")

    def recv(self, atom, args):
        if atom is _UNCALL_0:
            from typhon.scopes.safe import theFinalSlotMaker
            return ConstList([theFinalSlotMaker, StrObject(u"run"),
                              ConstList([self._obj, self._guard, NullObject])])
        return Slot.recv(self, atom, args)


class VarSlot(Slot):
    _immutable_fields_ = "_guard",

    def __init__(self, obj, guard):
        self._obj = obj
        self._guard = guard

    def toString(self):
        return u"<VarSlot(%s, %s)>" % (self._obj.toString(),
                                       self._guard.toString())

    def get(self):
        return self._obj

    def put(self, value):
        from typhon.scopes.safe import Throw
        if self._guard is NullObject:
            self._obj = value
        else:
            self._obj = self._guard.call(u"coerce", [value, Throw()])
        return NullObject
