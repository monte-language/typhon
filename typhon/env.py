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
from rpython.rlib.objectmodel import always_inline

from typhon.atoms import getAtom
from typhon.errors import userError
from typhon.objects.auditors import deepFrozenGuard, deepFrozenStamp
from typhon.objects.constants import NullObject
from typhon.objects.data import StrObject
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
from typhon.objects.slots import Binding, VarSlot, finalBinding, varBinding


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


@always_inline
def bindingToSlot(binding):
    if isinstance(binding, Binding):
        return binding.get()
    from typhon.objects.collections.maps import EMPTY_MAP
    return binding.callAtom(GET_0, [], EMPTY_MAP)


@always_inline
def bindingToValue(binding):
    from typhon.objects.collections.maps import EMPTY_MAP
    if isinstance(binding, Binding):
        slot = binding.get()
    else:
        slot = binding.callAtom(GET_0, [], EMPTY_MAP)
    return slot.callAtom(GET_0, [], EMPTY_MAP)


@always_inline
def assignValue(binding, value):
    from typhon.objects.collections.maps import EMPTY_MAP
    slot = binding.callAtom(GET_0, [], EMPTY_MAP)
    # Speed up VarSlots.
    if isinstance(slot, VarSlot):
        slot.put(value)
        return

    # Slowest path.
    slot.callAtom(PUT_1, [value], EMPTY_MAP)


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
        # return promote(self.globals[index])
        return self.globals[index]

    def getSlotGlobal(self, index):
        binding = self.getBindingGlobal(index)
        return bindingToSlot(binding)

    def getValueGlobal(self, index):
        binding = self.getBindingGlobal(index)
        return bindingToValue(binding)

    def putValueGlobal(self, index, value):
        binding = self.getBindingGlobal(index)
        assignValue(binding, value)

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
        binding = self.getBindingFrame(index)
        return bindingToSlot(binding)

    def getValueFrame(self, index):
        binding = self.getBindingFrame(index)
        return bindingToValue(binding)

    def putValueFrame(self, index, value):
        binding = self.getBindingFrame(index)
        assignValue(binding, value)

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
        binding = self.getBindingLocal(index)
        return bindingToSlot(binding)

    def getValueLocal(self, index):
        binding = self.getBindingLocal(index)
        return bindingToValue(binding)

    def putValueLocal(self, index, value):
        binding = self.getBindingLocal(index)
        assignValue(binding, value)

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

class SlotStrategy(NameStrategy):
    """
    A slot.
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


class FlavorEnv(object):
    """
    An environment for evaluating ASTs.
    """

    def __init__(self, mapping):
        self.mapping = mapping

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def new(self, shadows):
        copy = self.mapping.copy()
        for shadow in shadows:
            if shadow in copy:
                del copy[shadow]
        return FlavorEnv(copy)

    def closureOf(self, staticScope):
        d = {}
        for name in staticScope.namesUsed():
            d[name] = self.mapping[name]
        return FlavorEnv(d)

    def assign(self, name, value):
        self.mapping[name].assign(value)

    def binding(self, name, value):
        assert name not in self.mapping
        self.mapping[name] = BindingStrategy(value)

    def final(self, name, value):
        assert name not in self.mapping
        self.mapping[name] = AnyFinalStrategy(value)

    def finalGuarded(self, name, value, guard):
        assert name not in self.mapping
        self.mapping[name] = FinalStrategy(value, guard)

    def var(self, name, value):
        assert name not in self.mapping
        self.mapping[name] = AnyVarStrategy(value)

    def varGuarded(self, name, value, guard):
        assert name not in self.mapping
        self.mapping[name] = VarStrategy(value, guard)

    def getBinding(self, name):
        return self.mapping[name].getBinding()

    def getNoun(self, name):
        return self.mapping[name].getNoun()

    def getGuards(self):
        guards = {}
        for name, strategy in self.mapping.iteritems():
            guards[name] = strategy.getGuard()
        return guards

emptyEnv = FlavorEnv({})

def scopeToEnv(scope):
    d = {}
    for name, binding in scope.iteritems():
        d[name] = BindingStrategy(binding)
    return FlavorEnv(d)
