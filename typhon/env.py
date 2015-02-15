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

from rpython.rlib.jit import hint, promote, unroll_safe

from typhon.objects.slots import Binding, FinalSlot


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = Binding(FinalSlot(scope[key]))
    return rv


class Environment(object):
    """
    An execution context.

    Environments encapsulate and manage the value stack for SmallCaps. In
    addition, environments have two fixed-size frames of bindings, one for
    outer closed-over bindings and one for local names.
    """

    # Note that we could eventually virtualize the handler stack, but it
    # causes far too many virtualizable escapes.
    _virtualizable_ = (
        "local[*]",
        "frame[*]",
        "valueStack[*]", "depth",
    )

    # The stack pointer. Always points to the *empty* cell above the top of
    # the stack.
    depth = 0

    # The handler stack pointer. Same rules as stack pointer.
    handlerDepth = 0

    def __init__(self, frame, localSize, stackSize, handlerSize):
        self = hint(self, access_directly=True, fresh_virtualizable=True)

        assert localSize >= 0, "Negative local size not allowed!"
        assert stackSize >= 0, "Negative stack size not allowed!"
        assert handlerSize >= 0, "Negative handler stack size not allowed!"

        self.frame = frame
        self.local = [None] * localSize
        # Plus one extra empty cell to ease stack pointer math.
        self.stackSize = stackSize + 1
        self.valueStack = [None] * self.stackSize
        self.handlerSize = handlerSize + 1
        self.handlerStack = [None] * self.handlerSize

    def push(self, obj):
        i = self.depth
        assert i >= 0, "Stack underflow!"
        assert i < self.stackSize, "Stack overflow!"
        self.valueStack[i] = obj
        self.depth += 1

    def pop(self):
        self.depth -= 1
        i = self.depth
        assert i >= 0, "Stack underflow!"
        assert i < self.stackSize, "Stack overflow!"
        rv = self.valueStack[i]
        self.valueStack[i] = None
        return rv

    def peek(self):
        i = self.depth - 1
        assert i >= 0, "Stack underflow!"
        assert i < self.stackSize, "Stack overflow!"
        return self.valueStack[i]

    def pushHandler(self, handler):
        i = self.handlerDepth
        assert i >= 0, "Stack underflow!"
        assert i < self.handlerSize, "Stack overflow!"
        self.handlerStack[i] = handler
        self.handlerDepth += 1

    def popHandler(self):
        self.handlerDepth -= 1
        i = self.handlerDepth
        assert i >= 0, "Stack underflow!"
        assert i < self.handlerSize, "Stack overflow!"
        rv = self.handlerStack[i]
        self.handlerStack[i] = None
        return rv

    def createBindingFrame(self, index, binding):
        # Commented out because binding replacement is not that weird and also
        # because the JIT doesn't permit doing this without making this
        # function dont_look_inside.
        # if self.frame[index] is not None:
        #     debug_print(u"Warning: Replacing binding %d" % index)

        index = promote(index)
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

        self.frame[index] = binding

    def createSlotFrame(self, index, slot):
        self.createBindingFrame(index, Binding(slot))

    def getBindingFrame(self, index):
        # The promotion here is justified by a lack of ability for any code
        # object to dynamically alter its frame index. If the code is green
        # (and they're always green), then the index is green as well.
        index = promote(index)
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds :c"

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
