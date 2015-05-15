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

from typhon.smallcaps.ops import (DUP, ROT, POP, SWAP, ASSIGN_FRAME,
                                  ASSIGN_GLOBAL, ASSIGN_LOCAL, BIND, BINDSLOT,
                                  SLOT_FRAME, SLOT_GLOBAL, SLOT_LOCAL,
                                  NOUN_FRAME, NOUN_GLOBAL, NOUN_LOCAL,
                                  BINDING_FRAME, BINDING_GLOBAL,
                                  BINDING_LOCAL, LIST_PATT, LITERAL,
                                  BINDOBJECT, SCOPE, EJECTOR, TRY, UNWIND,
                                  END_HANDLER, BRANCH, CALL, JUMP)


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
        # pc: depth, handlerDepth
        self.branches = {0: (0, 0)}

    def addBranch(self, pc, depth, handlerDepth):
        print "Adding a branch", pc
        self.branches.append((pc, depth, handlerDepth))

    def pop(self):
        self.currentDepth -= 1

    def push(self):
        self.currentDepth += 1
        if self.currentDepth > self.maxDepth:
            self.maxDepth = self.currentDepth

    def popHandler(self):
        self.currentHandlerDepth -= 1

    def pushHandler(self):
        self.currentHandlerDepth += 1
        if self.currentHandlerDepth > self.maxHandlerDepth:
            self.maxHandlerDepth = self.currentHandlerDepth

    def runInstruction(self, instruction, pc):
        index = self.code.indices[pc]

        if instruction in (DUP, SLOT_FRAME, SLOT_GLOBAL, SLOT_LOCAL,
                           NOUN_FRAME, NOUN_GLOBAL, NOUN_LOCAL, BINDING_FRAME,
                           BINDING_GLOBAL, BINDING_LOCAL, LITERAL, SCOPE):
            self.push()
            return pc + 1
        elif instruction in (ROT, SWAP):
            return pc + 1
        elif instruction in (POP, ASSIGN_FRAME, ASSIGN_GLOBAL, ASSIGN_LOCAL,
                             BIND, BINDSLOT):
            self.pop()
            return pc + 1
        elif instruction == LIST_PATT:
            self.pop()
            self.pop()
            self.currentDepth += index * 2
            return pc + 1
        elif instruction == BINDOBJECT:
            for i in range(self.code.scripts[index].numStamps):
                self.pop()
            for i in range(len(self.code.scripts[index].globalNames)):
                self.pop()
            for i in range(len(self.code.scripts[index].closureNames)):
                self.pop()
            self.currentDepth += 1
            return pc + 1
        elif instruction == EJECTOR:
            self.push()
            self.pushHandler()
            return pc + 1
        elif instruction in (TRY, UNWIND):
            self.pushHandler()
            return pc + 1
        elif instruction == END_HANDLER:
            self.popHandler()
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
        print "Completed all", len(self.branches), "branches"

    def completeBranch(self, pc, depth, handlerDepth):
        self.currentDepth = depth
        self.currentHandlerDepth = handlerDepth

        while pc < len(self.code.instructions):
            instruction = self.code.instructions[pc]
            # print ">", pc, self.code.dis(instruction,
            #                              self.code.indices[pc])
            pc = self.runInstruction(instruction, pc)
