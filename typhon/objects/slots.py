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
from typhon.objects.constants import NullObject
from typhon.objects.root import Object


class Binding(Object):
    """
    A slot and a guard describing the nature of the slot.
    """

    def __init__(self, slot):
        self.slot = slot

    def recv(self, verb, args):
        if verb == u"get" and len(args) == 0:
            return self.slot
        raise Refused(verb, args)


class Slot(Object):
    """
    A storage space.
    """

    def repr(self):
        return "<slot>"

    def recv(self, verb, args):
        if verb == u"get" and len(args) == 0:
            return self.get()
        if verb == u"put" and len(args) == 1:
            return self.put(args[0])
        raise Refused(verb, args)


class FinalSlot(Slot):

    _immutable_ = True

    def __init__(self, obj):
        self._obj = obj

    def get(self):
        return self._obj

    def put(self, value):
        raise RuntimeError("Can't put into a FinalSlot!")


class VarSlot(Slot):

    def __init__(self, obj):
        self._obj = obj

    def get(self):
        return self._obj

    def put(self, value):
        self._obj = value
        return NullObject
