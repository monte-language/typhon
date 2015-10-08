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

from rpython.rlib.jit import promote, unroll_safe

from typhon.atoms import getAtom
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.data import StrObject
from typhon.objects.guards import anyGuard
from typhon.objects.slots import Binding, FinalBinding


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


def finalize(scope):
    from typhon.prelude import getGlobal
    # This is kind of stupid, but it does resolve the circularity in time.
    deepFrozen = getGlobal(u"DeepFrozen")
    if deepFrozen is None and u"DeepFrozen" in scope:
        deepFrozen = scope[u"DeepFrozen"]
    rv = {}
    for key in scope:
        o = scope[key]
        if deepFrozenStamp in o.stamps and deepFrozen is not None:
            g = deepFrozen
        else:
            g = anyGuard
        rv[key] = FinalBinding(scope[key], g)
    return rv


class Environment(object):
    """
    An execution context.

    Environments encapsulate and manage the value stack for SmallCaps. In
    addition, environments have two fixed-size frames of bindings, one for
    outer closed-over bindings and one for local names.
    """

    _immutable_fields_ = "frame[*]", "globals[*]"

    # The stack pointer. Always points to the *empty* cell above the top of
    # the stack.
    depth = 0

    # The handler stack pointer. Same rules as stack pointer.
    handlerDepth = 0

    def __init__(self, frame, globals, localSize, stackSize, handlerSize):
        assert localSize >= 0, "Negative local size not allowed!"
        assert stackSize >= 0, "Negative stack size not allowed!"
        assert handlerSize >= 0, "Negative handler stack size not allowed!"

        self.frame = frame
        self.globals = globals
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

    @unroll_safe
    def popSlice(self, size):
        depth = self.depth
        assert size <= depth, "Stack underflow!"
        # XXX should be handwritten loop per fijal and arigato. ~ C.
        rv = [self.pop() for _ in range(size)]
        rv.reverse()
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

    def getBindingGlobal(self, index):
        # The promotion here is justified by a lack of ability for any code
        # object to dynamically alter its frame index. If the code is green
        # (and they're always green), then the index is green as well.
        index = promote(index)
        assert index >= 0, "Global index was negative!?"
        assert index < len(self.globals), "Global index out-of-bounds (%d, %d)" % (index, len(self.globals))

        # Oh, and we can promote globals too.
        assert self.globals[index] is not None, "Global binding never defined?"
        return promote(self.globals[index])

    def getSlotGlobal(self, index):
        from typhon.objects.collections import EMPTY_MAP
        binding = self.getBindingGlobal(index)
        return binding.callAtom(GET_0, [], EMPTY_MAP)

    def getValueGlobal(self, index):
        from typhon.objects.collections import EMPTY_MAP
        # Specialize the relatively common case of FinalBindings.
        binding = self.getBindingGlobal(index)
        if isinstance(binding, FinalBinding):
            return binding.value
        slot = binding.callAtom(GET_0, [], EMPTY_MAP)
        return slot.callAtom(GET_0, [], EMPTY_MAP)

    def putValueGlobal(self, index, value):
        from typhon.objects.collections import EMPTY_MAP
        slot = self.getSlotGlobal(index)
        return slot.callAtom(PUT_1, [value], EMPTY_MAP)

    def getBindingFrame(self, index):
        # The promotion here is justified by a lack of ability for any code
        # object to dynamically alter its frame index. If the code is green
        # (and they're always green), then the index is green as well.
        index = promote(index)
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.frame), "Frame index out-of-bounds (%d, %d)" % (index, len(self.frame))

        assert self.frame[index] is not None, "Frame binding never defined?"
        return self.frame[index]

    def getSlotFrame(self, index):
        from typhon.objects.collections import EMPTY_MAP
        # Elidability is based on bindings not allowing reassignment of slots.
        binding = self.getBindingFrame(index)
        return binding.callAtom(GET_0, [], EMPTY_MAP)

    def getValueFrame(self, index):
        from typhon.objects.collections import EMPTY_MAP
        slot = self.getSlotFrame(index)
        return slot.callAtom(GET_0, [], EMPTY_MAP)

    def putValueFrame(self, index, value):
        from typhon.objects.collections import EMPTY_MAP
        slot = self.getSlotFrame(index)
        return slot.callAtom(PUT_1, [value], EMPTY_MAP)

    def createBindingLocal(self, index, binding):
        # Commented out because binding replacement is not that weird and also
        # because the JIT doesn't permit doing this without making this
        # function dont_look_inside.
        # if self.frame[index] is not None:
        #     debug_print(u"Warning: Replacing binding %d" % index)

        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.local), "Frame index out-of-bounds :c"

        self.local[index] = binding

    def createSlotLocal(self, index, slot, bindingGuard):
        self.createBindingLocal(index, Binding(slot, bindingGuard))

    def getBindingLocal(self, index):
        assert index >= 0, "Frame index was negative!?"
        assert index < len(self.local), "Frame index out-of-bounds :c"
        if self.local[index] is None:
            print "Warning: Use-before-define on local index", index
            print "Expect an imminent crash."
            from typhon.objects.refs import UnconnectedRef
            return UnconnectedRef(StrObject(
                u"Local index %d used before definition" % index))

        assert self.local[index] is not None, "Local binding use-before-define"
        return self.local[index]

    def getSlotLocal(self, index):
        from typhon.objects.collections import EMPTY_MAP
        # Elidability is based on bindings not allowing reassignment of slots.
        binding = self.getBindingLocal(index)
        return binding.callAtom(GET_0, [], EMPTY_MAP)

    def getValueLocal(self, index):
        from typhon.objects.collections import EMPTY_MAP
        slot = self.getSlotLocal(index)
        return slot.callAtom(GET_0, [], EMPTY_MAP)

    def putValueLocal(self, index, value):
        from typhon.objects.collections import EMPTY_MAP
        slot = self.getSlotLocal(index)
        return slot.callAtom(PUT_1, [value], EMPTY_MAP)

    def saveDepth(self):
        return self.depth, self.handlerDepth

    def restoreDepth(self, depthPair):
        depth, handlerDepth = depthPair
        # If these invariants are broken, then the stack can contain Nones, so
        # we'll guard against it here.
        assert depth <= self.depth, "Implementation error: Value stack UB"
        assert (handlerDepth <= self.handlerDepth,
                "Implementation error: Handler stack UB")
        self.depth = depth
        self.handlerDepth = handlerDepth
