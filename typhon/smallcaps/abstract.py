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

    suspended = False

    def __init__(self, code):
        self.code = code
        # pc: depth, handlerDepth
        self.branches = {}

    def addBranch(self, pc):
        # print "Adding a branch", pc
        self.branches[pc] = self.currentDepth, self.currentHandlerDepth

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
        elif instruction in (ROT, SWAP):
            pass
        elif instruction in (POP, ASSIGN_FRAME, ASSIGN_GLOBAL, ASSIGN_LOCAL,
                             BIND, BINDSLOT):
            self.pop()
        elif instruction == LIST_PATT:
            self.pop()
            self.pop()
            self.currentDepth += index * 2
        elif instruction == BINDOBJECT:
            for i in range(self.code.scripts[index].numStamps):
                self.pop()
            for i in range(len(self.code.scripts[index].globalNames)):
                self.pop()
            for i in range(len(self.code.scripts[index].closureNames)):
                self.pop()
            self.currentDepth += 1
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
        elif instruction == CALL:
            arity = self.code.atoms[index].arity
            for i in range(arity):
                self.pop()
        elif instruction == JUMP:
            self.addBranch(index)
            self.suspended = True
            # print "Suspending at pc", pc
        else:
            raise RuntimeError("Unknown instruction %d" % instruction)

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
