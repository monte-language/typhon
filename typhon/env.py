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
from typhon.errors import userError
from typhon.objects.auditors import deepFrozenGuard, deepFrozenStamp
from typhon.objects.constants import NullObject
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.slots import (Binding, FinalSlot, VarSlot, finalBinding,
                                  varBinding)


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


class NameStrategy(object):
    """
    A strategy for handling a name.
    """

class AnyFinalStrategy(NameStrategy):
    """
    A final noun guarded either by Any or no guard.
    """

    _immutable_ = True

    def __init__(self, value):
        self.value = value

    def assign(self, value):
        raise userError(u"Tried to assign to final slot")

    def getBinding(self):
        return finalBinding(self.value, anyGuard)

    def getGuard(self):
        return FinalSlotGuard(anyGuard)

    def getNoun(self):
        return self.value

    def getSlot(self):
        return FinalSlot(self.value, anyGuard)

class FinalStrategy(NameStrategy):
    """
    A final noun.
    """

    _immutable_ = True

    def __init__(self, value, guard):
        self.value = value
        self.guard = guard

    def assign(self, value):
        raise userError(u"Tried to assign to final slot")

    def getBinding(self):
        return finalBinding(self.value, self.guard)

    def getGuard(self):
        return FinalSlotGuard(self.guard)

    def getNoun(self):
        return self.value

    def getSlot(self):
        return FinalSlot(self.value, self.guard)

class AnyVarStrategy(NameStrategy):
    """
    A var noun guarded either by Any or no guard.
    """

    def __init__(self, value):
        self.value = value

    def assign(self, value):
        self.value = value

    def getBinding(self):
        return varBinding(self.value, anyGuard)

    def getGuard(self):
        return VarSlotGuard(anyGuard)

    def getNoun(self):
        return self.value

    def getSlot(self):
        return VarSlot(self.value, anyGuard)

class VarStrategy(NameStrategy):
    """
    A var noun.
    """

    _immutable_ = True
    _immutable_fields_ = "guard",

    def __init__(self, value, guard):
        self.value = value
        self.guard = guard

    def assign(self, value):
        self.value = self.guard.call(u"coerce", [value, NullObject])

    def getBinding(self):
        return varBinding(self.value, self.guard)

    def getGuard(self):
        return VarSlotGuard(self.guard)

    def getNoun(self):
        return self.value

    def getSlot(self):
        return VarSlot(self.value, self.guard)

class AnySlotStrategy(NameStrategy):
    """
    A slot with no slot guard.
    """

    _immutable_ = True

    def __init__(self, slot):
        self.slot = slot

    def assign(self, value):
        self.slot.call(u"put", [value])

    def getBinding(self):
        return Binding(self.slot, anyGuard)

    def getGuard(self):
        return anyGuard

    def getNoun(self):
        return self.slot.call(u"get", [])

    def getSlot(self):
        return self.slot

class SlotStrategy(NameStrategy):
    """
    A slot.
    """

    _immutable_ = True

    def __init__(self, slot, guard):
        self.slot = slot
        self.guard = guard

    def assign(self, value):
        self.slot.call(u"put", [value])

    def getBinding(self):
        return Binding(self.slot, self.guard)

    def getGuard(self):
        return self.guard

    def getNoun(self):
        return self.slot.call(u"get", [])

    def getSlot(self):
        return self.slot

class BindingStrategy(NameStrategy):
    """
    A binding.
    """

    _immutable_ = True

    def __init__(self, binding):
        self.binding = binding

    def assign(self, value):
        slot = self.binding.call(u"get", [])
        slot.call(u"put", [value])

    def getBinding(self):
        return self.binding

    def getGuard(self):
        return self.binding.call(u"getGuard", [])

    def getNoun(self):
        slot = self.binding.call(u"get", [])
        return slot.call(u"get", [])

    def getSlot(self):
        return self.binding.call(u"get", [])


def finalize(scope):
    rv = {}
    for key in scope:
        o = scope[key]
        if deepFrozenStamp in o.auditorStamps():
            g = deepFrozenGuard
        else:
            g = anyGuard
        rv[key] = finalBinding(o, g)
    return rv


class Environment(object):
    """
    An execution context.

    Environments encapsulate and manage the value stack for SmallCaps. In
    addition, environments have two fixed-size frames of bindings, one for
    outer closed-over bindings and one for local names.
    """

    _immutable_ = True
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

        if frame:
            self.frame = [BindingStrategy(binding) for binding in frame]
        else:
            self.frame = None
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

    def getGlobal(self, index):
        return self.globals[promote(index)]

    def getBindingGlobal(self, index):
        return self.getGlobal(index).getBinding()

    def getSlotGlobal(self, index):
        return self.getGlobal(index).getSlot()

    def getValueGlobal(self, index):
        return self.getGlobal(index).getNoun()

    def putValueGlobal(self, index, value):
        self.getGlobal(index).assign(value)

    def getFrame(self, index):
        return self.frame[promote(index)]

    def getBindingFrame(self, index):
        return self.getFrame(index).getBinding()

    def getSlotFrame(self, index):
        return self.getFrame(index).getSlot()

    def getValueFrame(self, index):
        return self.getFrame(index).getNoun()

    def putValueFrame(self, index, value):
        self.getFrame(index).assign(value)

    def createBindingLocal(self, index, binding):
        self.local[index] = BindingStrategy(binding)

    def createSlotLocal(self, index, slot, bindingGuard):
        if bindingGuard is anyGuard:
            self.local[index] = AnySlotStrategy(slot)
        else:
            self.local[index] = SlotStrategy(slot, bindingGuard)

    def getLocal(self, index):
        return self.local[promote(index)]

    def getBindingLocal(self, index):
        return self.getLocal(index).getBinding()

    def getSlotLocal(self, index):
        return self.getLocal(index).getSlot()

    def getValueLocal(self, index):
        return self.getLocal(index).getNoun()

    def putValueLocal(self, index, value):
        self.getLocal(index).assign(value)

    def saveDepth(self):
        return self.depth, self.handlerDepth

    def restoreDepth(self, depthPair):
        depth, handlerDepth = depthPair
        # If these invariants are broken, then the stack can contain Nones, so
        # we'll guard against it here.
        assert depth <= self.depth, "Implementation error: Value stack UB"
        assert handlerDepth <= self.handlerDepth, "Implementation error: Handler stack UB"
        self.depth = depth
        self.handlerDepth = handlerDepth
