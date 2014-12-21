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
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throw
from typhon.objects.root import Object


COERCE_2 = getAtom(u"coerce", 2)
GET_0 = getAtom(u"get", 0)
MAKESLOT_1 = getAtom(u"makeSlot", 1)
PUT_1 = getAtom(u"put", 1)

def predGuard(f):
    """
    A guard which has no additional behavior other than to apply a
    single-argument predicate check to its specimens.

    Predicate guards include slot creation methods.
    """

    name = f.__name__

    class PredicateSlot(Object):

        def __init__(self, initial):
            self._slot = initial

        def toString(self):
            return u"<predicateSlot(%s)>" % name.decode("utf-8")

        def recv(self, atom, args):
            # get/0: Obtain the contents of the slot.
            if atom is GET_0:
                return self._slot

            # put/1: Change the contents of the slot.
            if atom is PUT_1:
                value = args[0]
                if f(value):
                    self._slot = value
                else:
                    raise Exception("Coercion failed")
                return NullObject

            raise Refused(self, atom, args)

    class PredicateGuard(Object):

        _immutable_ = True

        def toString(self):
            return u"<predicateGuard(%s)>" % name.decode("utf-8")

        def recv(self, atom, args):
            # coerce/2: Coercion of specimens.
            if atom is COERCE_2:
                specimen = args[0]
                ejector = args[1]
                if f(specimen):
                    return specimen

                # Failed; we should bail using the ejector.
                throw(ejector, StrObject(u"Failed to coerce specimen"))

            # makeSlot/1: Creation of slots with this guard.
            if atom is MAKESLOT_1:
                initial = args[0]
                return PredicateSlot(initial)

            raise Refused(self, atom, args)

    return PredicateGuard
