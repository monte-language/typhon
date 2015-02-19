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

from rpython.rlib.jit import elidable_promote, jit_debug, promote, unroll_safe
from rpython.rlib.objectmodel import specialize

from typhon.env import Environment
from typhon.errors import Ejecting, UserException
from typhon.objects.collections import unwrapList
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.slots import Binding, FinalSlot

(
    DUP, ROT, POP, SWAP,
    ASSIGN_FRAME, ASSIGN_LOCAL, BIND, BINDSLOT,
    SLOT_FRAME, SLOT_LOCAL, NOUN_FRAME, NOUN_LOCAL,
    BINDING_FRAME, BINDING_LOCAL,
    LIST_PATT,
    LITERAL,
    BINDOBJECT, SCOPE,
    EJECTOR, TRY, UNWIND, END_HANDLER,
    BRANCH, CALL, JUMP,
) = range(25)

ops = {
    "DUP": DUP,
    "ROT": ROT,
    "POP": POP,
    "SWAP": SWAP,
    "ASSIGN_FRAME": ASSIGN_FRAME,
    "ASSIGN_LOCAL": ASSIGN_LOCAL,
    "BIND": BIND,
    "BINDSLOT": BINDSLOT,
    "SLOT_FRAME": SLOT_FRAME,
    "SLOT_LOCAL": SLOT_LOCAL,
    "NOUN_FRAME": NOUN_FRAME,
    "NOUN_LOCAL": NOUN_LOCAL,
    "BINDING_FRAME": BINDING_FRAME,
    "BINDING_LOCAL": BINDING_LOCAL,
    "LIST_PATT": LIST_PATT,
    "LITERAL": LITERAL,
    "BINDOBJECT": BINDOBJECT,
    "SCOPE": SCOPE,
    "EJECTOR": EJECTOR,
    "TRY": TRY,
    "UNWIND": UNWIND,
    "END_HANDLER": END_HANDLER,
    "BRANCH": BRANCH,
    "CALL": CALL,
    "JUMP": JUMP,
}


reverseOps = {v:k for k, v in ops.iteritems()}


class Code(object):
    """
    SmallCaps code object.
    """

    _immutable_ = True
    _immutable_fields_ = ("instructions[*]", "indices[*]", "atoms[*]",
                          "frame[*]", "literals[*]", "locals[*]",
                          "scripts[*]",
                          "maxDepth", "maxHandlerDepth")

    def __init__(self, instructions, atoms, literals, frame, locals, scripts):
        # Copy all of the lists on construction, to satisfy RPython's need for
        # these lists to be immutable.
        self.instructions = [pair[0] for pair in instructions]
        self.indices = [pair[1] for pair in instructions]
        self.atoms = atoms[:]
        self.literals = literals[:]
        self.frame = frame[:]
        self.locals = locals[:]
        self.scripts = scripts[:]

    @elidable_promote()
    def instSize(self):
        return len(self.instructions)

    @elidable_promote()
    def localSize(self):
        return len(self.locals)

    @elidable_promote()
    def inst(self, i):
        return self.instructions[i]

    @elidable_promote()
    def index(self, i):
        return self.indices[i]

    @elidable_promote()
    def atom(self, i):
        return self.atoms[i]

    @elidable_promote()
    def literal(self, i):
        return self.literals[i]

    @elidable_promote()
    def frameAt(self, i):
        return self.frame[i]

    @elidable_promote()
    def script(self, i):
        return self.scripts[i]

    def dis(self, instruction, index):
        base = "%s %d" % (reverseOps[instruction], index)
        if instruction == CALL:
            base += " (%s)" % self.atoms[index].repr()
        # XXX enabling this requires the JIT to be able to traverse a lot of
        # otherwise-unsafe code. You're free to try to fix it, but you've been
        # warned.
        # elif instruction == LITERAL:
        #     base += " (%s)" % self.literals[index].toString().encode("utf-8")
        elif instruction in (NOUN_FRAME, ASSIGN_FRAME, SLOT_FRAME,
                BINDING_FRAME):
            base += " (%s)" % self.frame[index].encode("utf-8")
        elif instruction in (NOUN_LOCAL, ASSIGN_LOCAL, SLOT_LOCAL,
                BINDING_LOCAL, BIND, BINDSLOT):
            base += " (%s)" % self.locals[index].encode("utf-8")
        return base

    def disAt(self, index):
        instruction = self.instructions[index]
        index = self.indices[index]
        return self.dis(instruction, index)

    def disassemble(self):
        rv = []
        for i, instruction in enumerate(self.instructions):
            index = self.indices[i]
            rv.append("%d: %s" % (i, self.dis(instruction, index)))
        return "\n".join(rv)

    def figureMaxDepth(self):
        ai = AbstractInterpreter(self)
        ai.run()
        self.maxDepth = ai.maxDepth
        self.maxHandlerDepth = ai.maxHandlerDepth


class SmallCaps(object):
    """
    A SmallCaps abstract bytecode interpreter.
    """

    _immutable_ = True
    _immutable_fields_ = "code", "env"

    def __init__(self, code, frame):
        self.code = code
        self.env = Environment(frame, self.code.localSize(),
                               promote(self.code.maxDepth),
                               promote(self.code.maxHandlerDepth))

    @staticmethod
    def withDictScope(code, scope):
        frame = [scope[key] for key in code.frame]
        return SmallCaps(code, frame)

    def pop(self):
        return self.env.pop()

    def push(self, value):
        self.env.push(value)

    def peek(self):
        return self.env.peek()

    @unroll_safe
    def bindObject(self, index):
        script = self.code.script(index)
        closure = [self.pop() for _ in script.closureNames]
        closure.reverse()
        obj = script.makeObject(closure)
        # Make sure that the object has access to itself, if necessary.
        obj.patchSelf(Binding(FinalSlot(obj)))
        self.push(obj)

    @unroll_safe
    def listPattern(self, size):
        ej = self.pop()
        xs = unwrapList(self.pop(), ej)
        if len(xs) < size:
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

        try:
            self.push(target.callAtom(atom, args))
        except UserException as ue:
            argString = u", ".join([arg.toQuote() for arg in args])
            atomRepr = atom.repr().decode("utf-8")
            ue.trail.append(u"In %s.%s [%s]:" % (target.toString(),
                                                 atomRepr, argString))
            raise

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
        elif instruction == ASSIGN_FRAME:
            value = self.pop()
            slot = self.env.putValueFrame(index, value)
            return pc + 1
        elif instruction == ASSIGN_LOCAL:
            value = self.pop()
            slot = self.env.putValueLocal(index, value)
            return pc + 1
        elif instruction == BIND:
            binding = self.pop()
            self.env.createBindingLocal(index, binding)
            return pc + 1
        elif instruction == BINDSLOT:
            slot = self.pop()
            self.env.createSlotLocal(index, slot)
            return pc + 1
        elif instruction == SLOT_FRAME:
            self.push(self.env.getSlotFrame(index))
            return pc + 1
        elif instruction == SLOT_LOCAL:
            self.push(self.env.getSlotLocal(index))
            return pc + 1
        elif instruction == NOUN_FRAME:
            self.push(self.env.getValueFrame(index))
            return pc + 1
        elif instruction == NOUN_LOCAL:
            self.push(self.env.getValueLocal(index))
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
            ej = Ejector()
            self.push(ej)
            self.env.pushHandler(Eject(self, ej, index))
            return pc + 1
        elif instruction == TRY:
            self.env.pushHandler(Catch(self, index))
            return pc + 1
        elif instruction == UNWIND:
            self.env.pushHandler(Unwind(self, index))
            return pc + 1
        elif instruction == END_HANDLER:
            handler = self.env.popHandler()
            handler.drop(self, index)
            return pc + 1
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
                # print ">", pc, self.code.dis(instruction,
                #                              self.code.indices[pc])
                jit_debug("Before run")
                pc = self.runInstruction(instruction, pc)
                jit_debug("After run")
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
            finalHandler.drop(self, pc)
        # print "<" * 10

    def unwindEjector(self, ex):
        while self.env.handlerDepth:
            handler = self.env.popHandler()
            rv = handler.eject(self, ex)
            if rv != -1:
                return rv
        raise ex

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

    def drop(self, machine, index):
        pass


class Eject(Handler):

    def __init__(self, machine, ejector, index):
        self.valueDepth = machine.env.depth
        self.handlerDepth = machine.env.handlerDepth
        self.ejector = ejector
        self.index = index

    def repr(self):
        return "Eject(%d)" % self.index

    def eject(self, machine, ex):
        if ex.ejector is self.ejector:
            machine.env.depth = self.valueDepth
            machine.env.handlerDepth = self.handlerDepth
            machine.push(ex.value)
            return self.index
        else:
            return -1


class Catch(Handler):

    def __init__(self, machine, index):
        self.valueDepth = machine.env.depth
        self.handlerDepth = machine.env.handlerDepth
        self.index = index

    def repr(self):
        return "Catch(%d)" % self.index

    def unwind(self, machine, ex):
        machine.env.depth = self.valueDepth
        machine.env.handlerDepth = self.handlerDepth
        # Push the caught value.
        machine.push(StrObject(u"Uninformative exception"))
        # And the ejector.
        machine.push(NullObject)
        return self.index


class Unwind(Handler):

    def __init__(self, machine, index):
        self.valueDepth = machine.env.depth
        self.handlerDepth = machine.env.handlerDepth
        self.index = index

    def repr(self):
        return "Unwind(%d)" % self.index

    def eject(self, machine, ex):
        rv = self.carryOn(machine)
        machine.env.pushHandler(Rethrower(ex))
        return rv

    def unwind(self, machine, ex):
        rv = self.carryOn(machine)
        machine.env.pushHandler(Rethrower(ex))
        return rv

    def carryOn(self, machine):
        machine.env.depth = self.valueDepth
        machine.env.handlerDepth = self.handlerDepth
        return self.index

    def drop(self, machine, index):
        machine.env.pushHandler(Returner(index))


class Rethrower(Handler):

    @specialize.argtype(1)
    def __init__(self, ex):
        self.ex = ex

    def repr(self):
        return "Rethrower"

    def drop(self, machine, index):
        raise self.ex


class Returner(Handler):

    def __init__(self, index):
        self.index = index

    def repr(self):
        return "Returner"

    def drop(self, machine, index):
        machine.pc = index


class AbstractInterpreter(object):
    """
    An abstract interpreter for precalculating facts about code.
    """

    _immutable_fields_ = "code"

    currentDepth = 0
    currentHandlerDepth = 0
    maxDepth = 0
    maxHandlerDepth = 0
    underflow = 0

    def __init__(self, code):
        self.code = code
        # pc, depth, handlerDepth
        self.branches = [(0, 0, 0)]

    def checkMaxDepth(self):
        if self.currentDepth + self.underflow > self.maxDepth:
            self.maxDepth = self.currentDepth + self.underflow
        if self.currentHandlerDepth > self.maxHandlerDepth:
            self.maxHandlerDepth = self.currentHandlerDepth

    def addBranch(self, pc, depth, handlerDepth):
        self.branches.append((pc, depth, handlerDepth))

    def pop(self):
        # Overestimates but that's fine.
        if self.currentDepth == 0:
            self.underflow += 1

    def runInstruction(self, instruction, pc):
        index = self.code.indices[pc]

        if instruction == DUP:
            self.currentDepth += 1
            return pc + 1
        elif instruction == ROT:
            return pc + 1
        elif instruction == POP:
            self.pop()
            return pc + 1
        elif instruction == SWAP:
            return pc + 1
        elif instruction == ASSIGN_FRAME:
            self.pop()
            return pc + 1
        elif instruction == ASSIGN_LOCAL:
            self.pop()
            return pc + 1
        elif instruction == BIND:
            self.pop()
            return pc + 1
        elif instruction == BINDSLOT:
            self.pop()
            return pc + 1
        elif instruction == SLOT_FRAME:
            self.currentDepth += 1
            return pc + 1
        elif instruction == SLOT_LOCAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == NOUN_FRAME:
            self.currentDepth += 1
            return pc + 1
        elif instruction == NOUN_LOCAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == BINDING_FRAME:
            self.currentDepth += 1
            return pc + 1
        elif instruction == BINDING_LOCAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == LIST_PATT:
            self.pop()
            self.pop()
            self.currentDepth += index * 2
            return pc + 1
        elif instruction == LITERAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == BINDOBJECT:
            for i in range(len(self.code.scripts[index].closureNames)):
                self.pop()
            self.currentDepth += 1
            return pc + 1
        elif instruction == EJECTOR:
            self.currentDepth += 1
            self.currentHandlerDepth += 1
            return pc + 1
        elif instruction == TRY:
            self.currentHandlerDepth += 1
            return pc + 1
        elif instruction == UNWIND:
            self.currentHandlerDepth += 1
            return pc + 1
        elif instruction == END_HANDLER:
            self.currentHandlerDepth -= 1
            return pc + 1
        elif instruction == BRANCH:
            self.pop()
            self.addBranch(index, self.currentDepth, self.currentHandlerDepth)
            return pc + 1
        elif instruction == CALL:
            arity = self.code.atoms[index].arity
            for i in range(arity):
                self.pop()
            return pc + 1
        elif instruction == JUMP:
            return index
        else:
            raise RuntimeError("Unknown instruction %d" % instruction)

    def run(self):
        i = 0
        while i < len(self.branches):
            pc, depth, handlerDepth = self.branches[i]
            self.completeBranch(pc, depth, handlerDepth)
            i += 1

    def completeBranch(self, pc, depth, handlerDepth):
        self.currentDepth = depth
        self.currentHandlerDepth = handlerDepth

        while pc < len(self.code.instructions):
            instruction = self.code.instructions[pc]
            # print ">", pc, self.code.dis(instruction,
            #                              self.code.indices[pc])
            pc = self.runInstruction(instruction, pc)
            self.checkMaxDepth()
