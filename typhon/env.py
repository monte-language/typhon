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

from typhon.errors import userError
from typhon.objects.slots import Binding, FinalSlot


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = Binding(FinalSlot(scope[key]))
    return rv


class Environment(object):
    """
    An execution context.

    Environments are append-only mappings of nouns to slots. They may be
    nested to provide scoping.
    """

    _immutable_ = True

    def __init__(self, initialScope, parent, size):
        self.size = size

        if parent is None:
            self._mapping = {}
            self.frame = [None] * size
        else:
            self._mapping = parent._mapping.copy()
            self.frame = parent.frame[:] + [None] * size

        for k, v in initialScope.items():
            self.createBinding(k, v)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def new(self, size):
        return Environment({}, self, size)

    def createBinding(self, noun, binding):
        if noun in self._mapping:
            # raise userError(
            #     u"Noun %s already in frame; cannot make new binding" % noun)
            print u"Warning: Replacing binding %s" % noun

        offset = len(self.frame)
        self._mapping[noun] = offset
        self.frame.append(binding)

    def createSlot(self, noun, slot):
        self.createBinding(noun, Binding(slot))

    def findKey(self, noun):
        offset = self._mapping.get(noun, -1)
        if offset == -1:
            raise userError(u"Noun %s not in frame" % noun)
        return offset

    def getBinding(self, noun):
        return self.frame[self.findKey(noun)]

    def getSlot(self, noun):
        binding = self.getBinding(noun)
        return binding.call(u"get", [])

    def getValue(self, noun):
        slot = self.getSlot(noun)
        return slot.call(u"get", [])

    def putValue(self, noun, value):
        slot = self.getSlot(noun)
        return slot.call(u"put", [value])

    def freeze(self):
        """
        Return a copy of this environment with the scope flattened for easy
        lookup.

        Meant to generate closures for objects.
        """

        # Allow me to break the ice. My name is Freeze. Learn it well, for it
        # is the chilling sound of your doom.
        return self.new(0)
