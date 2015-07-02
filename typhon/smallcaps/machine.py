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

from rpython.rlib.jit import elidable_promote, jit_debug, promote, unroll_safe
from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.env import Environment
from typhon.errors import Ejecting, SmallCapsFailure, UserException, userError
from typhon.objects.collections import unwrapList
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.exceptions import SealedException
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard
from typhon.objects.slots import FinalSlot, VarSlot
from typhon.profile import csp
from typhon.smallcaps.ops import *


GET_0 = getAtom(u"get", 0)
PUT_1 = getAtom(u"put", 1)


class SmallCaps(object):
    """
    A SmallCaps abstract bytecode interpreter.
    """

    _immutable_ = True
    _immutable_fields_ = "code", "env"

    def __init__(self, code, frame, globals):
        self.code = code
        self.env = Environment(frame, globals, self.code.localSize(),
                               promote(self.code.maxDepth + 20),
                               promote(self.code.maxHandlerDepth + 5))

    @staticmethod
    def withDictScope(code, scope):
        try:
            frame = [scope[key] for key in code.frame]
            globals = [scope[key] for key in code.globals]
        except KeyError:
            missing = []
            for key in code.frame:
                if key not in scope:
                    missing.append(key)
            for key in code.globals:
                if key not in scope:
                    missing.append(key)
            message = u"Keys not in scope: %s" % u", ".join(missing)
            raise userError(message)
        return SmallCaps(code, frame, globals)

    def pop(self):
        return self.env.pop()

    def push(self, value):
        self.env.push(value)

    def peek(self):
        return self.env.peek()

    @unroll_safe
    def bindObject(self, index):
        script = self.code.script(index)
        auditors = [self.pop() for _ in range(script.numAuditors)]
        globals = [self.pop() for _ in range(promote(len(script.globalNames)))]
        globals.reverse()
        closure = [self.pop() for _ in range(promote(len(script.closureNames)))]
        closure.reverse()
        obj = script.makeObject(closure, globals, auditors)
        self.push(obj)

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
    def call(self, index):
        atom = self.code.atom(index)
        args = [self.pop() for _ in range(atom.arity)]
        args.reverse()
        target = self.pop()

        # We used to add the call trail for tracebacks here, but it's been
        # moved to t.o.root. Happy bug hunting! ~ C.
        with csp.startCall(target, atom):
            self.push(target.callAtom(atom, args))

    def runInstruction(self, instruction, pc):
        index = self.code.index(pc)
        jit_debug(reverseOps[instruction], index, pc)

        if instruction == DUP:
            self.push(self.peek())
            return pc + 1
        elif instruction == ROT:
            z = self.pop()
            y = self.pop()
            x = self.pop()
            self.push(y)
            self.push(z)
            self.push(x)
            return pc + 1
        elif instruction == POP:
            self.pop()
            return pc + 1
        elif instruction == SWAP:
            y = self.pop()
            x = self.pop()
            self.push(y)
            self.push(x)
            return pc + 1
        elif instruction == ASSIGN_GLOBAL:
            value = self.pop()
            self.env.putValueGlobal(index, value)
            return pc + 1
        elif instruction == ASSIGN_FRAME:
            value = self.pop()
            self.env.putValueFrame(index, value)
            return pc + 1
        elif instruction == ASSIGN_LOCAL:
            value = self.pop()
            self.env.putValueLocal(index, value)
            return pc + 1
        elif instruction == BIND:
            binding = self.pop()
            self.env.createBindingLocal(index, binding)
            return pc + 1
        elif instruction == BINDFINALSLOT:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.env.createSlotLocal(index, FinalSlot(val, guard),
                                     FinalSlotGuard(guard))
            return pc + 1
        elif instruction == BINDVARSLOT:
            guard = self.pop()
            ej = self.pop()
            specimen = self.pop()
            val = guard.call(u"coerce", [specimen, ej])
            self.env.createSlotLocal(index, VarSlot(val, guard),
                                     VarSlotGuard(guard))
            return pc + 1
        elif instruction == SLOT_GLOBAL:
            self.push(self.env.getSlotGlobal(index))
            return pc + 1
        elif instruction == SLOT_FRAME:
            self.push(self.env.getSlotFrame(index))
            return pc + 1
        elif instruction == SLOT_LOCAL:
            self.push(self.env.getSlotLocal(index))
            return pc + 1
        elif instruction == NOUN_GLOBAL:
            self.push(self.env.getValueGlobal(index))
            return pc + 1
        elif instruction == NOUN_FRAME:
            self.push(self.env.getValueFrame(index))
            return pc + 1
        elif instruction == NOUN_LOCAL:
            self.push(self.env.getValueLocal(index))
            return pc + 1
        elif instruction == BINDING_GLOBAL:
            self.push(self.env.getBindingGlobal(index))
            return pc + 1
        elif instruction == BINDING_FRAME:
            self.push(self.env.getBindingFrame(index))
            return pc + 1
        elif instruction == BINDING_LOCAL:
            self.push(self.env.getBindingLocal(index))
            return pc + 1
        elif instruction == LIST_PATT:
            self.listPattern(index)
            return pc + 1
        elif instruction == LITERAL:
            self.push(self.code.literal(index))
            return pc + 1
        elif instruction == BINDOBJECT:
            self.bindObject(index)
            return pc + 1
        elif instruction == EJECTOR:
            # Look carefully at the order of operations. The handler captures
            # the depth of the stack, so it's important to create it *before*
            # pushing the ejector onto the stack. Otherwise, the handler
            # thinks that the stack started off with an extra level of depth.
            ej = Ejector()
            handler = Eject(self, ej, index)
            self.push(ej)
            self.env.pushHandler(handler)
            return pc + 1
        elif instruction == TRY:
            self.env.pushHandler(Catch(self, index))
            return pc + 1
        elif instruction == UNWIND:
            self.env.pushHandler(Unwind(self, index))
            return pc + 1
        elif instruction == END_HANDLER:
            handler = self.env.popHandler()
            return handler.drop(self, pc, index)
        elif instruction == BRANCH:
            cond = unwrapBool(self.pop())
            if cond:
                return pc + 1
            else:
                return index
        elif instruction == CALL:
            self.call(index)
            return pc + 1
        elif instruction == JUMP:
            return index
        else:
            raise RuntimeError("Unknown instruction %d" % instruction)

    @unroll_safe
    def run(self):
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
            except SmallCapsFailure as scf:
                # Print out a reasonably informative summary of our state and
                # then die.
                print "Invariant failed in SmallCaps!"
                print "PC:", pc
                if self.env.handlerStack:
                    print "Top of handler stack:", self.env.handlerStack[-1]
                else:
                    print "No handlers on handler stack"
                if self.env.valueStack:
                    print "Top of value stack:", self.env.valueStack[-1]
                else:
                    print "No values on values stack"
                print self.code.disassemble()
                raise RuntimeError("Ending the program")
        # If there is a final handler, drop it; it may cause exceptions to
        # propagate or perform some additional stack unwinding.
        if self.env.handlerDepth:
            finalHandler = self.env.popHandler()
            # Return value ignored here.
            finalHandler.drop(self, pc, pc)
        # print "<" * 10

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
        payload = ex.getPayload()
        if not isinstance(payload, SealedException):
            # Sealed exceptions should not be nested. This is currently the
            # only call site for SealedException, so this comment should serve
            # as a good warning. ~ C.
            payload = SealedException(payload, ex.trail)
        machine.push(payload)
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
