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
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throw
from typhon.objects.root import Object


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

        def repr(self):
            return "<predicateSlot>"

        def recv(self, verb, args):
            # get/0: Obtain the contents of the slot.
            if verb == u"get" and len(args) == 0:
                return self._slot

            # put/1: Change the contents of the slot.
            if verb == u"put" and len(args) == 1:
                value = args[0]
                if f(value):
                    self._slot = value
                else:
                    raise Exception("Coercion failed")
                return NullObject

            raise Refused(verb, args)

    class PredicateGuard(Object):

        _immutable_ = True

        def repr(self):
            return "<predicateGuard(%s)>" % name

        def recv(self, verb, args):
            # coerce/2: Coercion of specimens.
            if verb == u"coerce" and len(args) == 2:
                specimen = args[0]
                ejector = args[1]
                if f(specimen):
                    return specimen

                # Failed; we should bail using the ejector.
                throw(ejector, StrObject(u"Failed to coerce specimen"))

            # makeSlot/1: Creation of slots with this guard.
            if verb == u"makeSlot" and len(args) == 1:
                initial = args[0]
                return PredicateSlot(initial)

            raise Refused(verb, args)

    return PredicateGuard
