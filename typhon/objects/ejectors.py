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
from typhon.errors import Ejecting, UserException, userError
from typhon.metrics import globalRecorder
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.root import Object, audited

recorder = globalRecorder()
usageRate = recorder.getRateFor("Ejector usage")

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

    def __init__(self, label=None):
        self._label = label

    def toString(self):
        template = u"<ejector at %s%s>"
        return template % (self._label, u" (inert)" if self.active else u"")

    @method("Void")
    def run(self):
        self.fire()

    @method("Void", "Any", _verb="run")
    def _run(self, payload):
        self.fire(payload)

    def fire(self, payload=NullObject):
        if self.active:
            self.disable()
            raise Ejecting(self, payload)
        else:
            raise userError(u"Inactive ejector from %s was fired" %
                            self._label)

    def fireString(self, message):
        return self.fire(StrObject(message))

    @method.py("Void")
    def disable(self):
        self.active = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        # usageRate.observe(not self.active)
        self.disable()


def throw(ej, payload):
    if ej is None or ej is NullObject:
        raise UserException(payload)
    if isinstance(ej, Ejector):
        ej.fire(payload)
    else:
        ej.call(u"run", [payload])
    raise userError(u"Ejector did not exit")

def throwStr(ej, s):
    """
    The correct way to throw to an ejector with a string.
    """

    from typhon.objects.data import wrapStr
    throw(ej, wrapStr(s))

@autohelp
@audited.DF
class Throw(Object):

    def toString(self):
        return u"throw"

    @method("Void", "Any")
    def run(self, payload):
        raise UserException(payload)

    @method("Void", "Any", "Any")
    def eject(self, ej, payload):
        throw(ej, payload)

theThrower = Throw()
