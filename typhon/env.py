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

from rpython.rlib.debug import debug_print
from rpython.rlib.jit import elidable, hint, unroll_safe

from typhon.objects.slots import Binding, FinalSlot


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = Binding(FinalSlot(scope[key]))
    return rv


class Environment(object):
    """
    An execution context.

    Environments are fixed-size frames of bindings.
    """

    # _immutable_ = True
    _virtualizable_ = "frame[*]"

    depth = 0

    @unroll_safe
    def __init__(self, initialScope, parent, size):
        self = hint(self, access_directly=True, fresh_virtualizable=True)

        assert size >= 0, "Negative frame size not allowed!"
        self.size = size

        if parent is None:
            self.frame = [None] * size
        else:
            self.frame = parent.frame[:] + [None] * size
            self.depth = parent.depth

        for k, v in initialScope:
            self.createBinding(k, v)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def new(self, size):
        return Environment([], self, size)

    def createBinding(self, index, binding):
        # Commented out because binding replacement is not that weird and also
        # because the JIT doesn't permit doing this without making this
        # function dont_look_inside.
        # if self.frame[index] is not None:
        #     debug_print(u"Warning: Replacing binding %d" % index)

        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

        self.frame[index] = binding

    def createSlot(self, index, slot):
        self.createBinding(index, Binding(slot))

    @elidable
    def getBinding(self, index):
        # Elidability is based on bindings only being assigned once.
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

        # The promotion here is justified by a lack of ability for any node to
        # dynamically alter its frame index. If the node is green (and they're
        # always green), then the index is green as well. That said, the JIT
        # is currently good enough at figuring this out that no annotation is
        # currently needed.
        return self.frame[index]

    def getSlot(self, index):
        # Elidability is based on bindings not allowing reassignment of slots.
        binding = self.getBinding(index)
        return binding.call(u"get", [])

    def getValue(self, index):
        slot = self.getSlot(index)
        return slot.call(u"get", [])

    def putValue(self, index, value):
        slot = self.getSlot(index)
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
