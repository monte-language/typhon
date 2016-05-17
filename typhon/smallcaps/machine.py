# Copyright (C) 2015 Google Inc. All rights reserved.
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

from rpython.rlib import rvmprof
from rpython.rlib.jit import jit_debug, promote, unroll_safe
from rpython.rlib.objectmodel import always_inline, specialize

from typhon.atoms import getAtom
from typhon.errors import Ejecting, UserException, userError
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import ConstMap, monteMap, unwrapMap
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import anyGuard
from typhon.objects.slots import Binding, VarSlot, finalBinding, varBinding
from typhon.smallcaps import ops


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


def mkMirandaArgs():
    # XXX monteMap()
    _d = monteMap()
    _d[StrObject(u"FAIL")] = theThrower
    return ConstMap(_d)

MIRANDA_ARGS = mkMirandaArgs()


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


class SmallCaps(object):
    """
    A SmallCaps abstract bytecode interpreter.
    """

    _immutable_fields_ = "code", "frame[*]", "globals[*]"

    # The stack pointer. Always points to the *empty* cell above the top of
    # the stack.
    depth = 0

    # The "next" exceptions. One slot for Ejecting-type and one for
    # UserException-type exceptions. These are captured at the beginning of
    # the finally-block in try-finally constructs, and reraised at the end of
    # the block.
    nextException = None
    nextEjecting = None

    def __init__(self, code, frame, globals):
        self.code = code
        self.frame = frame
        self.globals = globals

        self.local = [None] * code.localSize()

        # Plus one extra empty cell to ease stack pointer math.
        self.stackSize = self.code.maxDepth + 1
        self.valueStack = [None] * self.stackSize

        self.ejectors = [None] * code.ejectorSize

        # For vat checkpointing.
        from typhon.vats import currentVat
        self.vat = currentVat.get()

    @staticmethod
    def withDictScope(code, scope):
        try:
            frame = [scope[key] for key in code.frame]
            globals = [scope[key] for key in code.globals]
        except KeyError:
            missing = []
            for key in code.frame:
                if key not in scope:
                    missing.append(u"%s (local)" % key)
            for key in code.globals:
                if key not in scope:
                    missing.append(u"%s (global)" % key)
            message = u"Keys not in scope: %s" % u", ".join(missing)
            raise userError(message)
        return SmallCaps(code, frame, globals)

    def push(self, obj):
        i = self.depth
        self.valueStack[i] = obj
        self.depth += 1

    def pop(self):
        self.depth -= 1
        i = self.depth
        rv = self.valueStack[i]
        self.valueStack[i] = None
        return rv

    @unroll_safe
    def popSlice(self, size):
        # XXX should be handwritten loop per fijal and arigato. ~ C.
        rv = [self.pop() for _ in range(size)]
        rv.reverse()
        return rv

    def peek(self):
        i = self.depth - 1
        return self.valueStack[i]

    def getBindingGlobal(self, index):
        # The promotion here is justified by a lack of ability for any code
        # object to dynamically alter its frame index. If the code is green
        # (and they're always green), then the index is green as well.
        index = promote(index)

        # Oh, and we can promote globals too.
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

        self.local[index] = binding

    def createSlotLocal(self, index, slot, bindingGuard):
        self.createBindingLocal(index, Binding(slot, bindingGuard))

    def getBindingLocal(self, index):
        if self.local[index] is None:
            print "Warning: Use-before-define on local index", index
            print "Expect an imminent crash."
            from typhon.objects.refs import UnconnectedRef
            return UnconnectedRef(StrObject(
                u"Local index %d used before definition" % index))

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

    def gatherLabels(self, labels):
        """
        Collect some labeled stuff.
        """

        rv = []
        for label in labels:
            frameType, frameIndex = label
            if frameType == "LOCAL":
                frame = self.local
            elif frameType == "FRAME":
                frame = self.frame
            elif frameType == "GLOBAL":
                frame = self.globals
            elif frameType is None:
                rv.append(None)
                continue
            else:
                assert False, "impossible"
            rv.append(frame[frameIndex])
        return rv

    @unroll_safe
    def bindObject(self, scriptIndex):
        from typhon.objects.ejectors import theThrower
        script, closureLabels, globalLabels = self.code.script(scriptIndex)
        closure = self.gatherLabels(closureLabels)[:]
        globals = self.gatherLabels(globalLabels)[:]
        auditors = self.popSlice(script.numAuditors)
        obj = script.makeObject(closure, globals, auditors)
        # Not a typo. The first copy is the actual return value from creating
        # the object expression; the second copy is given to the slot
        # constructor.
        self.push(obj)
        self.push(obj)
        self.push(theThrower)
        if auditors[0] is NullObject:
            self.push(anyGuard)
        else:
            self.push(auditors[0])

    @unroll_safe
    def listPattern(self, size):
        ej = self.pop()
        xs = unwrapList(self.pop(), ej)
        if len(xs) != size:
            throw(ej, StrObject(u"Failed list pattern (needed %d, got %d)" %
                                (size, len(xs))))
        while size:
            size -= 1
            self.push(xs[size])
            self.push(ej)

    @unroll_safe
    @specialize.arg(2)
    def call(self, index, withMap):
        atom = self.code.atom(index)

        if withMap:
            # Grab the named args.
            namedArgs = self.pop()
            assert isinstance(namedArgs, ConstMap), "No polymorphism in namedArgs"
            # Avoid _or() if possible; it is slow and JIT-opaque. ~ C.
            namedArgs = namedArgs._or(MIRANDA_ARGS)
        else:
            namedArgs = MIRANDA_ARGS

        args = self.popSlice(atom.arity)
        target = self.pop()

        # We used to add the call trail for tracebacks here, but it's been
        # moved to t.o.root. Happy bug hunting! ~ C.
        rv = target.callAtom(atom, args, namedArgs)
        if rv is None:
            print "A call to", target.__class__.__name__, "with atom", \
                  atom.repr, "returned None"
            raise RuntimeError("Implementation error")
        self.push(rv)

    @unroll_safe
    def buildMap(self, index):
        # XXX monteMap()
        d = monteMap()
        while index:
            index -= 1
            # Yikes, the order of operations here is dangerous.
            d[self.pop()] = self.pop()
        self.push(ConstMap(d))

    def ejector(self, index):
        # Look carefully at the order of operations. The handler captures
        # the depth of the stack, so it's important to create it *before*
        # pushing the ejector onto the stack. Otherwise, the handler
        # thinks that the stack started off with an extra level of depth.
        ej = Ejector()
        self.ejectors[index] = ej
        self.push(ej)

    def ejDisable(self, index):
        # The ejector should not be missing here, since we didn't ever unwind
        # it. This relies on the bytecode generation being correct.
        assert self.ejectors[index] is not None
        self.ejectors[index].disable()
        self.ejectors[index] = None

    def reraise(self):
        # Prefer raising exceptions to propagating ejectors.
        if self.nextException is not None:
            ex = self.nextException
            self.nextException = None
            self.nextEjecting = None
            raise ex
        if self.nextEjecting is not None:
            ex = self.nextEjecting
            self.nextEjecting = None
            raise ex

    def runInstruction(self, instruction, pc):
        index = self.code.index(pc)
        # jit_debug(self.code.disAt(pc))

        if instruction.asInt == ops.DUP.asInt:
            self.push(self.peek())
            return pc + 1
        elif instruction.asInt == ops.ROT.asInt:
            z = self.pop()
            y = self.pop()
            x = self.pop()
            self.push(y)
            self.push(z)
            self.push(x)
            return pc + 1
        elif instruction.asInt == ops.POP.asInt:
            self.pop()
            return pc + 1
        elif instruction.asInt == ops.SWAP.asInt:
            y = self.pop()
            x = self.pop()
            self.push(y)
            self.push(x)
            return pc + 1
        elif instruction.asInt == ops.ASSIGN_GLOBAL.asInt:
            value = self.pop()
            self.putValueGlobal(index, value)
            return pc + 1
        elif instruction.asInt == ops.ASSIGN_FRAME.asInt:
            value = self.pop()
            self.putValueFrame(index, value)
            return pc + 1
        elif instruction.asInt == ops.ASSIGN_LOCAL.asInt:
            value = self.pop()
            self.putValueLocal(index, value)
            return pc + 1
        elif instruction.asInt == ops.BIND.asInt:
            binding = self.pop()
            self.createBindingLocal(index, binding)
            return pc + 1
        elif instruction.asInt == ops.BINDFINALSLOT.asInt:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.createBindingLocal(index, finalBinding(val, guard))
            return pc + 1
        elif instruction.asInt == ops.BINDVARSLOT.asInt:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.createBindingLocal(index, varBinding(val, guard))
            return pc + 1
        elif instruction.asInt == ops.BINDANYFINAL.asInt:
            val = self.pop()
            self.createBindingLocal(index, finalBinding(val, anyGuard))
            return pc + 1
        elif instruction.asInt == ops.BINDANYVAR.asInt:
            val = self.pop()
            self.createBindingLocal(index, varBinding(val, anyGuard))
            return pc + 1
        elif instruction.asInt == ops.SLOT_GLOBAL.asInt:
            self.push(self.getSlotGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.SLOT_FRAME.asInt:
            self.push(self.getSlotFrame(index))
            return pc + 1
        elif instruction.asInt == ops.SLOT_LOCAL.asInt:
            self.push(self.getSlotLocal(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_GLOBAL.asInt:
            self.push(self.getValueGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_FRAME.asInt:
            self.push(self.getValueFrame(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_LOCAL.asInt:
            self.push(self.getValueLocal(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_GLOBAL.asInt:
            self.push(self.getBindingGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_FRAME.asInt:
            self.push(self.getBindingFrame(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_LOCAL.asInt:
            self.push(self.getBindingLocal(index))
            return pc + 1
        elif instruction.asInt == ops.LIST_PATT.asInt:
            self.listPattern(index)
            return pc + 1
        elif instruction.asInt == ops.LITERAL.asInt:
            self.push(self.code.literal(index))
            return pc + 1
        elif instruction.asInt == ops.BINDOBJECT.asInt:
            self.bindObject(index)
            return pc + 1
        elif instruction.asInt == ops.EJECTOR.asInt:
            self.ejector(index)
            return pc + 1
        elif instruction.asInt == ops.EJ_DISABLE.asInt:
            self.ejDisable(index)
            return pc + 1
        elif instruction.asInt == ops.RERAISE.asInt:
            self.reraise()
            return pc + 1
        elif instruction.asInt == ops.BRANCH.asInt:
            cond = unwrapBool(self.pop())
            if cond:
                return pc + 1
            else:
                return index
        elif instruction.asInt == ops.CALL.asInt:
            self.call(index, withMap=False)
            return pc + 1
        elif instruction.asInt == ops.CALL_MAP.asInt:
            self.call(index, withMap=True)
            return pc + 1
        elif instruction.asInt == ops.BUILD_MAP.asInt:
            self.buildMap(index)
            return pc + 1
        elif instruction.asInt == ops.NAMEDARG_EXTRACT.asInt:
            k = self.pop()
            d = unwrapMap(self.pop())
            if k not in d:
                raise userError(u"Named arg %s missing in call" % (
                    k.toString(),))
            self.push(d[k])
            return pc + 1
        elif instruction.asInt == ops.NAMEDARG_EXTRACT_OPTIONAL.asInt:
            k = self.pop()
            d = unwrapMap(self.pop())
            if k not in d:
                self.push(NullObject)
                return pc + 1
            self.push(d[k])
            return index
        elif instruction.asInt == ops.JUMP.asInt:
            return index
        elif instruction.asInt == ops.CHECKPOINT.asInt:
            # Checkpoint the vat to the given number of points.
            self.vat.checkpoint(points=index)
            return pc + 1
        else:
            raise RuntimeError("Unknown instruction %s" %
                    instruction.repr.encode("utf-8"))

    # Second argument is how to get a code object from a machine object.
    @rvmprof.vmprof_execute_code("smallcaps", lambda self: self.code)
    @unroll_safe
    def run(self):
        jit_debug(self.code.profileName)
        pc = 0
        instSize = self.code.instSize()
        while pc < instSize:
            instruction = self.code.inst(promote(pc))
            try:
                pc = self.runInstruction(instruction, pc)
            except Ejecting as e:
                pc = self.unwindEjector(e, pc)
            except UserException as ue:
                pc = self.unwindEx(ue, pc)

    def clampStack(self, pc):
        "Clamp the stack to be at the expected depth, after unwinding."
        self.stackSize = self.code.stackDepth[pc] + 1

    @unroll_safe
    def unwindEjector(self, ex, pc):
        "Find the handler for an ejector, or reraise if no handler exists."
        while True:
            if not self.code.canCatch(pc):
                raise ex
            et, i, pc = self.code.catchAt(pc)
            if et.asInt == ops.ET_FINALLY.asInt:
                self.nextEjecting = ex
                self.clampStack(pc)
                return pc
            elif et.asInt == ops.ET_TRY.asInt:
                continue
            elif et.asInt == ops.ET_ESCAPE.asInt:
                # NB: This cannot possibly succeed twice (since we assign None
                # this time around), so we've baked in the single-fire
                # semantics. ~ C.
                if self.ejectors[i] is ex.ejector:
                    self.ejectors[i] = None
                    self.clampStack(pc)
                    self.push(ex.value)
                    return pc
            else:
                assert False, "Impossible"

    @unroll_safe
    def unwindEx(self, ex, pc):
        "Find the handler for an ejector, or reraise if no handler exists."
        while True:
            if not self.code.canCatch(pc):
                raise ex
            et, _, pc = self.code.catchAt(pc)
            if et.asInt == ops.ET_FINALLY.asInt:
                if self.nextException is None:
                    self.nextException = ex
                else:
                    self.nextException.chain(ex)
                self.clampStack(pc)
                return pc
            elif et.asInt == ops.ET_TRY.asInt:
                self.clampStack(pc)
                # Push the caught value.
                self.push(sealException(ex))
                # And the ejector.
                self.push(NullObject)
                return pc
            elif et.asInt == ops.ET_ESCAPE.asInt:
                continue
            else:
                assert False, "Impossible"
