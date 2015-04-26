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
        elif instruction == ASSIGN_GLOBAL:
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
        elif instruction == SLOT_GLOBAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == SLOT_LOCAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == NOUN_FRAME:
            self.currentDepth += 1
            return pc + 1
        elif instruction == NOUN_GLOBAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == NOUN_LOCAL:
            self.currentDepth += 1
            return pc + 1
        elif instruction == BINDING_FRAME:
            self.currentDepth += 1
            return pc + 1
        elif instruction == BINDING_GLOBAL:
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
        elif instruction == SCOPE:
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
