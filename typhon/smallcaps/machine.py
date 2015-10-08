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
from rpython.rlib.jit import elidable_promote, jit_debug, promote, unroll_safe
from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.env import Environment
from typhon.errors import Ejecting, UserException, userError
from typhon.objects.collections import (EMPTY_MAP, ConstMap, monteDict,
                                        unwrapList, unwrapMap)
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.exceptions import sealException
from typhon.objects.guards import FinalSlotGuard, VarSlotGuard, anyGuard
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
        from typhon.scopes.safe import theThrower
        script = self.code.script(scriptIndex)
        auditors = self.popSlice(script.numAuditors)
        globals = self.popSlice(len(script.globalNames))
        closure = self.popSlice(len(script.closureNames))
        obj = script.makeObject(closure, globals, auditors)
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
    def call(self, index, withMap):
        atom = self.code.atom(index)
        if withMap:
            namedArgs = self.pop()
        else:
            namedArgs = EMPTY_MAP
        args = self.popSlice(atom.arity)
        target = self.pop()

        # We used to add the call trail for tracebacks here, but it's been
        # moved to t.o.root. Happy bug hunting! ~ C.
        with csp.startCall(target, atom):
            rv = target.callAtom(atom, args, namedArgs)
            if rv is None:
                print "A call to", target.__class__.__name__, "with atom", \
                      atom.repr, "returned None"
                raise RuntimeError("Implementation error")
            self.push(rv)

    @unroll_safe
    def buildMap(self, index):
        d = monteDict()
        for i in range(index):
            # Yikes, the order of operations here is dangerous.
            d[self.pop()] = self.pop()
        self.push(ConstMap(d))

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
            self.call(index, False)
            return pc + 1
        elif instruction == CALL_MAP:
            self.call(index, True)
            return pc + 1
        elif instruction == BUILD_MAP:
            self.buildMap(index)
            return pc + 1
        elif instruction == NAMEDARG_EXTRACT:
            k = self.pop()
            d = unwrapMap(self.pop())
            if k not in d:
                raise userError(u"Named arg %s missing in call" % (
                    k.toString(),))
            self.push(d[k])
            return pc + 1
        elif instruction == NAMEDARG_EXTRACT_OPTIONAL:
            k = self.pop()
            d = unwrapMap(self.pop())
            if k not in d:
                self.push(NullObject)
                return pc + 1
            self.push(d[k])
            return index
        elif instruction == JUMP:
            return index
        else:
            raise RuntimeError("Unknown instruction %d" % instruction)

    # Second argument is how to get a code object from a machine object.
    @rvmprof.vmprof_execute_code("smallcaps", lambda self: self.code)
    @unroll_safe
    def run(self):
        # print ">" * 10
        pc = 0
        while pc < self.code.instSize():
            instruction = self.code.inst(promote(pc))
            try:
                # print ">", pc, self.code.dis(instruction,
                #                              self.code.indices[pc])
                # jit_debug("Before run")
                pc = self.runInstruction(instruction, pc)
                # jit_debug("After run")
                # print "Stack:", self.env.valueStack[:self.env.depth]
                # if self.env.handlerDepth:
                #     print "Handlers:", self.env.handlerStack[:self.env.handlerDepth]
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
