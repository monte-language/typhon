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

from typhon.autohelp import autohelp, method
from typhon.objects.collections.lists import wrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object, audited


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

    @method.py("Any")
    def get(self):
        return self.slot

    @method("Any")
    def getGuard(self):
        return self.guard

    def getValue(self):
        return self.slot.get()

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        from typhon.scopes.safe import theSlotBinder
        return [wrapList([theSlotBinder, StrObject(u"run"),
                         wrapList([self.guard])]),
                StrObject(u"run"),
                wrapList([self.slot, NullObject]),
                EMPTY_MAP]


def finalBinding(value, guard):
    from typhon.objects.guards import FinalSlotGuard
    return Binding(FinalSlot(value, guard), FinalSlotGuard(guard))

def varBinding(value, guard):
    from typhon.objects.guards import VarSlotGuard
    return Binding(VarSlot(value, guard), VarSlotGuard(guard))

def finalize(scope):
    from typhon.objects.auditors import deepFrozenGuard, deepFrozenStamp
    from typhon.objects.guards import anyGuard
    rv = {}
    for key in scope:
        o = scope[key]
        if deepFrozenStamp in o.auditorStamps():
            g = deepFrozenGuard
        else:
            g = anyGuard
        rv[key] = finalBinding(o, g)
    return rv


@autohelp
@audited.Transparent
class FinalSlot(Object):

    _immutable_fields_ = "_obj", "_guard"

    def __init__(self, obj, guard):
        self._obj = obj
        self._guard = guard

    def printOn(self, out):
        out.call(u"print", [StrObject(u"<FinalSlot(")])
        out.call(u"print", [self._obj])
        out.call(u"print", [StrObject(u")>")])

    @method("Any")
    def getGuard(self):
        return self._guard

    @method("Any")
    def get(self):
        return self._obj

    @method("List")
    def _uncall(self):
        from typhon.scopes.safe import theFinalSlotMaker
        from typhon.objects.collections.maps import EMPTY_MAP
        return [theFinalSlotMaker, StrObject(u"run"),
                wrapList([self._obj, self._guard, NullObject]),
                EMPTY_MAP]


@autohelp
class VarSlot(Object):

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

    @method("Any")
    def getGuard(self):
        return self._guard

    @method("Any")
    def get(self):
        return self._obj

    @method.py("Void", "Any")
    def put(self, value):
        from typhon.objects.ejectors import theThrower
        if self._guard is NullObject:
            self._obj = value
        else:
            self._obj = self._guard.call(u"coerce", [value, theThrower])
