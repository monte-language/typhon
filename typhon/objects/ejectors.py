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

from typhon.errors import Ejecting, Refused, UserException
from typhon.objects.constants import NullObject
from typhon.objects.root import Object


class Ejector(Object):
    """
    An ejector.

    To catch and handle an ejector, catch ``Ejecting`` and perform an identity
    comparison on the ``ejector`` attribute with the desired ejector to
    handle. If a different ejector was caught, the catcher must reraise it.
    """

    active = True

    def repr(self):
        return "<ejector>" if self.active else "<ejector (inert)>"

    def recv(self, verb, args):
        if verb == u"run":
            if self.active:
                if args:
                    self.fire(args[0])
                else:
                    self.fire()

        if verb == u"disable":
            self.disable()
            return NullObject

        raise Refused(verb, args)

    def fire(self, payload=NullObject):
        raise Ejecting(self, payload)

    def disable(self):
        self.active = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.disable()


def throw(ej, payload):
    if ej is None:
        ej = NullObject
    if isinstance(ej, Ejector):
        ej.fire(payload)
    raise UserException(payload)
