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
from typhon.errors import Ejecting, Refused, UserException
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object

DISABLE_0 = getAtom(u"disable", 0)
RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)

@autohelp
class Ejector(Object):
    """
    An ejector.

    When fired, this object will prematurely end computation and return
    control to the object that created it.
    """

    # To catch and handle an ejector, catch ``Ejecting`` and perform an
    # identity comparison on the ``ejector`` attribute with the desired
    # ejector to handle. If a different ejector was caught, the catcher must
    # reraise it.

    active = True

    def toString(self):
        return u"<ejector>" if self.active else u"<ejector (inert)>"

    def recv(self, atom, args):
        if atom is RUN_0:
            self.fire()

        if atom is RUN_1:
            self.fire(args[0])

        if atom is DISABLE_0:
            self.disable()
            return NullObject

        raise Refused(self, atom, args)

    def fire(self, payload=NullObject):
        if self.active:
            raise Ejecting(self, payload)

    def fireString(self, message):
        return self.fire(StrObject(message))

    def disable(self):
        self.active = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.disable()


def throw(ej, payload):
    if ej is None or ej is NullObject:
        raise UserException(payload)
    if isinstance(ej, Ejector):
        ej.fire(payload)
    else:
        ej.call(u"run", [payload])
    raise UserException(StrObject(u"Ejector did not exit"))
