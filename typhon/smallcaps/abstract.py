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
                                  ASSIGN_GLOBAL, ASSIGN_LOCAL, BIND,
                                  BINDFINALSLOT, BINDVARSLOT,
                                  SLOT_FRAME, SLOT_GLOBAL, SLOT_LOCAL,
                                  NOUN_FRAME, NOUN_GLOBAL, NOUN_LOCAL,
                                  BINDING_FRAME, BINDING_GLOBAL,
                                  BINDING_LOCAL, LIST_PATT, LITERAL,
                                  BINDOBJECT, SCOPE, EJECTOR, TRY, UNWIND,
                                  END_HANDLER, BRANCH, CALL, CALL_MAP,
                                  BUILD_MAP, JUMP, NAMEDARG_EXTRACT,
                                  NAMEDARG_EXTRACT_OPTIONAL)


class AbstractInterpreter(object):
    """
    An abstract interpreter for precalculating facts about code.
    """

    _immutable_fields_ = "code",

    currentDepth = 0
    currentHandlerDepth = 0
    maxDepth = 0
    minDepth = 0
    maxHandlerDepth = 0

    suspended = False

    def __init__(self, code):
        self.code = code
        # pc: depth, handlerDepth
        self.branches = {}

    def addBranch(self, pc):
        # print "Adding a branch", pc
        self.branches[pc] = self.currentDepth, self.currentHandlerDepth

    def pop(self, count=1):
        self.currentDepth -= count
        if self.currentDepth < self.minDepth:
            self.minDepth = self.currentDepth

    def push(self, count=1):
        self.currentDepth += count
        if self.currentDepth > self.maxDepth:
            self.maxDepth = self.currentDepth

    def popHandler(self):
        self.currentHandlerDepth -= 1

    def pushHandler(self):
        self.currentHandlerDepth += 1
        if self.currentHandlerDepth > self.maxHandlerDepth:
            self.maxHandlerDepth = self.currentHandlerDepth

    def getDepth(self):
        depth = self.maxDepth
        if self.minDepth < 0:
            depth -= self.minDepth
        return depth, self.maxHandlerDepth

    def runInstruction(self, instruction, pc):
        index = self.code.indices[pc]

        if instruction in (DUP, SLOT_FRAME, SLOT_GLOBAL, SLOT_LOCAL,
                           NOUN_FRAME, NOUN_GLOBAL, NOUN_LOCAL, BINDING_FRAME,
                           BINDING_GLOBAL, BINDING_LOCAL, LITERAL, SCOPE):
            self.push()
        elif instruction in (ROT, SWAP):
            pass
        elif instruction in (POP, ASSIGN_FRAME, ASSIGN_GLOBAL, ASSIGN_LOCAL,
                             BIND):
            self.pop()
        elif instruction in (BINDFINALSLOT, BINDVARSLOT):
            self.pop(3)
        elif instruction == LIST_PATT:
            self.pop(2)
            self.push(index * 2)
        elif instruction == BINDOBJECT:
            self.pop(self.code.scripts[index].numAuditors)
            self.pop(self.code.scripts[index].globalSize)
            self.pop(self.code.scripts[index].closureSize)
            self.push()
            self.push()
            self.push()
            self.push()
        elif instruction == EJECTOR:
            self.push()
            self.pushHandler()
        elif instruction in (TRY, UNWIND):
            self.pushHandler()
        elif instruction == END_HANDLER:
            self.popHandler()
        elif instruction == BRANCH:
            self.pop()
            self.addBranch(index)
        elif instruction == BUILD_MAP:
            self.pop(index * 2)
            self.push()
        elif instruction == NAMEDARG_EXTRACT:
            self.pop(2)
            self.push()
        elif instruction == NAMEDARG_EXTRACT_OPTIONAL:
            self.pop(2)
            self.push()
            self.addBranch(index)
        elif instruction == CALL:
            self.pop(self.code.atoms[index].arity + 1)
            self.push()
        elif instruction == CALL_MAP:
            self.pop(self.code.atoms[index].arity + 2)
            self.push()
        elif instruction == JUMP:
            self.addBranch(index)
            self.suspended = True
            # print "Suspending at pc", pc
        else:
            raise RuntimeError("Unknown instruction %s" %
                    instruction.repr.encode("utf-8"))

    def run(self):
        for pc, instruction in enumerate(self.code.instructions):
            if self.suspended and pc in self.branches:
                # print "Unsuspending at pc", pc
                depth, handlerDepth = self.branches[pc]
                self.currentDepth = max(self.currentDepth, depth)
                self.currentHandlerDepth = max(self.currentHandlerDepth,
                                               handlerDepth)
                self.suspended = False

                self.runInstruction(instruction, pc)
            elif not self.suspended:
                self.runInstruction(instruction, pc)
        # print "Completed all", len(self.branches), "branches"
