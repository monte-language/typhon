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

    Environments have two fixed-size frames of bindings, one for outer
    closed-over bindings and one for local names.
    """

    _virtualizable_ = "frame[*]", "local[*]"

    depth = 0

    @unroll_safe
    def __init__(self, initialScope, frameSize, localSize):
        self = hint(self, access_directly=True, fresh_virtualizable=True)

        assert frameSize >= 0, "Negative frame size not allowed!"
        assert localSize >= 0, "Negative local size not allowed!"

        self.frame = [None] * frameSize
        self.local = [None] * localSize

        for k, v in initialScope:
            self.createBindingFrame(k, v)

    def createBindingFrame(self, index, binding):
        # Commented out because binding replacement is not that weird and also
        # because the JIT doesn't permit doing this without making this
        # function dont_look_inside.
        # if self.frame[index] is not None:
        #     debug_print(u"Warning: Replacing binding %d" % index)

        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

        self.frame[index] = binding

    def createSlotFrame(self, index, slot):
        self.createBindingFrame(index, Binding(slot))

    def getBindingFrame(self, index):
        # Elidability is based on bindings only being assigned once.
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

        # The promotion here is justified by a lack of ability for any node to
        # dynamically alter its frame index. If the node is green (and they're
        # always green), then the index is green as well. That said, the JIT
        # is currently good enough at figuring this out that no annotation is
        # currently needed.
        return self.frame[index]

    def getSlotFrame(self, index):
        # Elidability is based on bindings not allowing reassignment of slots.
        binding = self.getBindingFrame(index)
        return binding.call(u"get", [])

    def getValueFrame(self, index):
        slot = self.getSlotFrame(index)
        return slot.call(u"get", [])

    def putValueFrame(self, index, value):
        slot = self.getSlotFrame(index)
        return slot.call(u"put", [value])

    def createBindingLocal(self, index, binding):
        # Commented out because binding replacement is not that weird and also
        # because the JIT doesn't permit doing this without making this
        # function dont_look_inside.
        # if self.frame[index] is not None:
        #     debug_print(u"Warning: Replacing binding %d" % index)

        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.local), "Frame index out-of-bounds :c"

        self.local[index] = binding

    def createSlotLocal(self, index, slot):
        self.createBindingLocal(index, Binding(slot))

    def getBindingLocal(self, index):
        # Elidability is based on bindings only being assigned once.
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.local), "Frame index out-of-bounds :c"

        # The promotion here is justified by a lack of ability for any node to
        # dynamically alter its frame index. If the node is green (and they're
        # always green), then the index is green as well. That said, the JIT
        # is currently good enough at figuring this out that no annotation is
        # currently needed.
        return self.local[index]

    def getSlotLocal(self, index):
        # Elidability is based on bindings not allowing reassignment of slots.
        binding = self.getBindingLocal(index)
        return binding.call(u"get", [])

    def getValueLocal(self, index):
        slot = self.getSlotLocal(index)
        return slot.call(u"get", [])

    def putValueLocal(self, index, value):
        slot = self.getSlotLocal(index)
        return slot.call(u"put", [value])
