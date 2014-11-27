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

from typhon.objects.slots import Binding, FinalSlot


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = FinalSlot(scope[key])
    return rv


class Environment(object):
    """
    An execution context.

    Environments are append-only mappings of nouns to slots. They may be
    nested to provide scoping.
    """

    _immutable_ = True

    def __init__(self, initialScope, parent):
        if parent is None:
            self._frame = {}
        else:
            self._frame = parent._frame.copy()
        self._frame.update(initialScope)

    def __enter__(self):
        return Environment({}, self)

    def __exit__(self, *args):
        pass

    def recordSlot(self, noun, value):
        self._frame[noun] = value

    def _find(self, noun):
        # XXX the compiler needs to have proven this operation's safety
        # beforehand, because the JIT will not. We should look into some sort
        # of safe append-only situation here that will let us construct
        # environment names and slots at the beginning of the frame.
        v = self._frame.get(noun, None)
        if v is None:
            from typhon.objects.data import StrObject
            from typhon.errors import UserException
            raise UserException(StrObject(u"Noun %s not in frame" % noun))
        return v

    def bindingFor(self, noun):
        """
        Create a binding object for a given name.
        """

        return Binding(self._find(noun))

    def final(self, noun, value):
        self.recordSlot(noun, FinalSlot(value))

    def update(self, noun, value):
        slot = self._find(noun)
        slot.recv(u"put", [value])

    def get(self, noun):
        slot = self._find(noun)
        return slot.recv(u"get", [])

    def freeze(self):
        """
        Return a copy of this environment with the scope flattened for easy
        lookup.

        Meant to generate closures for objects.
        """

        # Allow me to break the ice. My name is Freeze. Learn it well, for it
        # is the chilling sound of your doom.

        # But wait, what's this? It's okay, kids; freezing is no longer
        # necessary.
        return self
