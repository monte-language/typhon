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

from collections import OrderedDict

from typhon.smallcaps.ops import (DUP, POP, SWAP, ASSIGN_FRAME, ASSIGN_LOCAL,
                                  BIND, BINDSLOT, SLOT_FRAME, SLOT_LOCAL,
                                  NOUN_FRAME, NOUN_LOCAL, BINDING_FRAME,
                                  BINDING_LOCAL, LITERAL, EJECTOR, TRY,
                                  UNWIND, END_HANDLER, BRANCH, JUMP)


def peephole(code):
    PeepholeOptimizer(code).run()
    code.figureMaxDepth()


class Action(object):
    def __init__(self, repr):
        self.repr = repr

    def __repr__(self):
        return self.repr

KEEP = Action("Keep")
REMOVE = Action("Remove")

templates = [
    # DUP POP ->
    ([DUP, POP], [REMOVE, REMOVE]),
    # LITERAL POP ->
    ([LITERAL, POP], [REMOVE, REMOVE]),
    # <load> POP ->
    ([SLOT_FRAME, POP], [REMOVE, REMOVE]),
    ([SLOT_LOCAL, POP], [REMOVE, REMOVE]),
    ([NOUN_FRAME, POP], [REMOVE, REMOVE]),
    ([NOUN_LOCAL, POP], [REMOVE, REMOVE]),
    ([BINDING_FRAME, POP], [REMOVE, REMOVE]),
    ([BINDING_LOCAL, POP], [REMOVE, REMOVE]),
    # DUP SWAP -> DUP
    ([DUP, SWAP], [KEEP, REMOVE]),
    # DUP <assign> POP -> <assign>
    ([DUP, ASSIGN_FRAME, POP], [REMOVE, KEEP, REMOVE]),
    ([DUP, ASSIGN_LOCAL, POP], [REMOVE, KEEP, REMOVE]),
    ([DUP, BIND, POP], [REMOVE, KEEP, REMOVE]),
    ([DUP, BINDSLOT, POP], [REMOVE, KEEP, REMOVE]),
]


class PeepholeOptimizer(object):
    """
    An abstract interpreter that applies peephole optimizations to bytecode.
    """

    _immutable_fields_ = "code"

    pc = 0

    def __init__(self, code):
        self.code = code
        # start: end
        self.branches = {}

    def match(self, template):
        if len(template) + self.pc >= self.code.instSize():
            return False

        if self.crossesBranch(len(template)):
            return False

        # RPython enumerate() doesn't support start kwarg.
        for i, opcode in enumerate(template):
            if opcode != self.code.inst(i + self.pc):
                return False
        return True

    def rewrite(self, actions):
        # We have to go backwards so that we don't invalidate the indices.
        # RPython enumerate() doesn't support start kwarg. Also RPython
        # doesn't support list().
        sequence = [x for x in enumerate(actions)]
        sequence.reverse()
        for i, action in sequence:
            if action is KEEP:
                continue
            elif action is REMOVE:
                self.removeInst(i + self.pc)

    def crossesBranch(self, size):
        top = self.pc
        bottom = top + size
        for start, end in self.branches.items():
            if top < start < bottom:
                return True
            if top < end < bottom:
                return True
        return False

    def addBranch(self):
        start = self.pc
        instruction = self.code.inst(start)
        if instruction in (EJECTOR, TRY, UNWIND, BRANCH, JUMP, END_HANDLER):
            end = self.code.index(start)
            self.branches[start] = end

    def adjustBranches(self, pc):
        for start, end in self.branches.items():
            if pc < start:
                del self.branches[start]
                self.branches[start - 1] = end - 1
            elif pc < end:
                self.branches[start] = end - 1

    def rewriteBranches(self):
        for start, end in self.branches.items():
            self.code.indices[start] = end

    def removeInst(self, pc):
        del self.code.instructions[pc]
        del self.code.indices[pc]
        self.adjustBranches(pc)

    def pruneLocals(self):
        # The frame generally cannot be altered because it is shared between
        # many methods and isn't rebuildable. Locals, on the other hand, are
        # fair game. This optimization doesn't kick in very often, but it's
        # not that expensive, I think.
        localSize = 0
        newLocalMap = OrderedDict()
        newLocal = []

        for pc, instruction in enumerate(self.code.instructions):
            if instruction in (ASSIGN_LOCAL, BIND, BINDSLOT, SLOT_LOCAL,
                                 NOUN_LOCAL, BINDING_LOCAL):
                index = self.code.index(pc)
                if index not in newLocalMap:
                    newLocal.append(self.code.locals[index])
                    newLocalMap[index] = localSize
                    localSize += 1
                self.code.indices[pc] = newLocalMap[index]

        self.code.locals = newLocal

    def run(self):
        self.pc = 0
        while self.pc < self.code.instSize():
            self.addBranch()
            self.pc += 1

        self.pc = 0
        while self.pc < self.code.instSize():
            changed = False
            for template, action in templates:
                if self.match(template):
                    self.rewrite(action)
                    changed = True
            if changed:
                self.pc -= 1
            else:
                self.pc += 1

        self.rewriteBranches()
        self.pruneLocals()
