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
from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.env import Environment
from typhon.errors import Ejecting, UserException, userError
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import ConstMap, monteMap, unwrapMap
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, theThrower, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import anyGuard
from typhon.objects.slots import finalBinding, varBinding
from typhon.smallcaps import ops


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


def mkMirandaArgs():
    # XXX monteMap()
    _d = monteMap()
    _d[StrObject(u"FAIL")] = theThrower
    return ConstMap(_d)

MIRANDA_ARGS = mkMirandaArgs()


class SmallCaps(object):
    """
    A SmallCaps abstract bytecode interpreter.
    """

    _immutable_ = True
    _immutable_fields_ = "code", "env"

    def __init__(self, code, frame, globals):
        self.code = code
        self.env = Environment(frame, globals, self.code.localSize(),
                               promote(self.code.maxDepth),
                               promote(self.code.maxHandlerDepth))

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

    def pop(self):
        return self.env.pop()

    def popSlice(self, size):
        return self.env.popSlice(promote(size))

    def push(self, value):
        self.env.push(value)

    def peek(self):
        return self.env.peek()

    @unroll_safe
    def bindObject(self, scriptIndex):
        from typhon.objects.ejectors import theThrower
        script, closureLabels, globalLabels = self.code.script(scriptIndex)
        closure = self.env.gatherLabels(closureLabels)[:]
        globals = self.env.gatherLabels(globalLabels)[:]
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
        # Checkpoint the vat. This will, rarely, cause an exception to escape
        # from within us.
        self.vat.checkpoint()

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
        for i in range(index):
            # Yikes, the order of operations here is dangerous.
            d[self.pop()] = self.pop()
        self.push(ConstMap(d))

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
            self.env.putValueGlobal(index, value)
            return pc + 1
        elif instruction.asInt == ops.ASSIGN_FRAME.asInt:
            value = self.pop()
            self.env.putValueFrame(index, value)
            return pc + 1
        elif instruction.asInt == ops.ASSIGN_LOCAL.asInt:
            value = self.pop()
            self.env.putValueLocal(index, value)
            return pc + 1
        elif instruction.asInt == ops.BIND.asInt:
            binding = self.pop()
            self.env.createBindingLocal(index, binding)
            return pc + 1
        elif instruction.asInt == ops.BINDFINALSLOT.asInt:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.env.createBindingLocal(index, finalBinding(val, guard))
            return pc + 1
        elif instruction.asInt == ops.BINDVARSLOT.asInt:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.env.createBindingLocal(index, varBinding(val, guard))
            return pc + 1
        elif instruction.asInt == ops.SLOT_GLOBAL.asInt:
            self.push(self.env.getSlotGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.SLOT_FRAME.asInt:
            self.push(self.env.getSlotFrame(index))
            return pc + 1
        elif instruction.asInt == ops.SLOT_LOCAL.asInt:
            self.push(self.env.getSlotLocal(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_GLOBAL.asInt:
            self.push(self.env.getValueGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_FRAME.asInt:
            self.push(self.env.getValueFrame(index))
            return pc + 1
        elif instruction.asInt == ops.NOUN_LOCAL.asInt:
            self.push(self.env.getValueLocal(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_GLOBAL.asInt:
            self.push(self.env.getBindingGlobal(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_FRAME.asInt:
            self.push(self.env.getBindingFrame(index))
            return pc + 1
        elif instruction.asInt == ops.BINDING_LOCAL.asInt:
            self.push(self.env.getBindingLocal(index))
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
            # Look carefully at the order of operations. The handler captures
            # the depth of the stack, so it's important to create it *before*
            # pushing the ejector onto the stack. Otherwise, the handler
            # thinks that the stack started off with an extra level of depth.
            ej = Ejector()
            handler = Eject(self, ej, index)
            self.push(ej)
            self.env.pushHandler(handler)
            return pc + 1
        elif instruction.asInt == ops.TRY.asInt:
            self.env.pushHandler(Catch(self, index))
            return pc + 1
        elif instruction.asInt == ops.UNWIND.asInt:
            self.env.pushHandler(Unwind(self, index))
            return pc + 1
        elif instruction.asInt == ops.END_HANDLER.asInt:
            handler = self.env.popHandler()
            return handler.drop(self, pc, index)
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
        else:
            raise RuntimeError("Unknown instruction %s" %
                    instruction.repr.encode("utf-8"))

    # Second argument is how to get a code object from a machine object.
    @rvmprof.vmprof_execute_code("smallcaps", lambda self: self.code)
    @unroll_safe
    def run(self):
        jit_debug(self.code.profileName)
        # print ">" * 10
        pc = 0
        while pc < self.code.instSize():
            instruction = self.code.inst(promote(pc))
            try:
                pc = self.runInstruction(instruction, pc)
            except Ejecting as e:
                pc = self.unwindEjector(e)
            except UserException as ue:
                pc = self.unwindEx(ue)
        # If there is a final handler, drop it; it may cause exceptions to
        # propagate or perform some additional stack unwinding.
        if self.env.handlerDepth:
            finalHandler = self.env.popHandler()
            # Return value ignored here.
            finalHandler.drop(self, pc, pc)
        # print "<" * 10
        return 0

    @unroll_safe
    def unwindEjector(self, ex):
        while self.env.handlerDepth:
            handler = self.env.popHandler()
            rv = handler.eject(self, ex)
            if rv != -1:
                return rv
        raise ex

    @unroll_safe
    def unwindEx(self, ex):
        while self.env.handlerDepth:
            handler = self.env.popHandler()
            rv = handler.unwind(self, ex)
            if rv != -1:
                return rv
        raise ex


class Handler(object):

    def __repr__(self):
        return self.repr()

    def eject(self, machine, ex):
        return -1

    def unwind(self, machine, ex):
        return -1

    def drop(self, machine, pc, index):
        return pc + 1


class Eject(Handler):

    _immutable_ = True

    def __init__(self, machine, ejector, index):
        self.savedDepth = machine.env.saveDepth()
        self.ejector = ejector
        self.index = index

    def repr(self):
        return "Eject(%d)" % self.index

    def eject(self, machine, ex):
        if ex.ejector is self.ejector:
            machine.env.restoreDepth(self.savedDepth)
            machine.push(ex.value)
            return self.index
        else:
            return -1


class Catch(Handler):

    _immutable_ = True

    def __init__(self, machine, index):
        self.savedDepth = machine.env.saveDepth()
        self.index = index

    def repr(self):
        return "Catch(%d)" % self.index

    def unwind(self, machine, ex):
        machine.env.restoreDepth(self.savedDepth)
        # Push the caught value.
        machine.push(sealException(ex))
        # And the ejector.
        machine.push(NullObject)
        return self.index

    def drop(self, machine, pc, index):
        return index


class Unwind(Handler):

    _immutable_ = True

    def __init__(self, machine, index):
        self.savedDepth = machine.env.saveDepth()
        self.index = index

    def repr(self):
        return "Unwind(%d)" % self.index

    def eject(self, machine, ex):
        machine.env.restoreDepth(self.savedDepth)
        machine.env.pushHandler(Rethrower(ex))
        return self.index

    def unwind(self, machine, ex):
        machine.env.restoreDepth(self.savedDepth)
        machine.env.pushHandler(Rethrower(ex))
        return self.index

    def drop(self, machine, pc, index):
        machine.env.pushHandler(Returner(index))
        # As you were, then.
        return pc + 1


class Rethrower(Handler):

    _immutable_ = True

    @specialize.argtype(1)
    def __init__(self, ex):
        self.ex = ex

    def repr(self):
        return "Rethrower"

    def drop(self, machine, pc, index):
        raise self.ex


class Returner(Handler):

    _immutable_ = True

    def __init__(self, index):
        self.index = index

    def repr(self):
        return "Returner"

    def drop(self, machine, pc, index):
        return index
