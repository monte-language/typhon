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

from rpython.rlib.jit import elidable_promote

from typhon.smallcaps.abstract import AbstractInterpreter
from typhon.smallcaps.ops import (reverseOps, ASSIGN_GLOBAL, ASSIGN_FRAME,
                                  ASSIGN_LOCAL, BIND, BINDFINALSLOT,
                                  BINDVARSLOT, SLOT_GLOBAL, SLOT_FRAME,
                                  SLOT_LOCAL, NOUN_GLOBAL, NOUN_FRAME,
                                  NOUN_LOCAL, BINDING_GLOBAL, BINDING_FRAME,
                                  BINDING_LOCAL, CALL, CALL_MAP)


class Code(object):
    """
    SmallCaps code object.
    """

    _immutable_ = True
    _immutable_fields_ = ("instructions[*]?", "indices[*]?", "atoms[*]",
                          "globals[*]", "frame[*]", "literals[*]",
                          "locals[*]", "scripts[*]",
                          "maxDepth", "maxHandlerDepth")

    def __init__(self, instructions, atoms, literals, globals, frame, locals,
                 scripts):
        # Copy all of the lists on construction, to satisfy RPython's need for
        # these lists to be immutable.
        self.instructions = [pair[0] for pair in instructions]
        self.indices = [pair[1] for pair in instructions]
        self.atoms = atoms[:]
        self.literals = literals[:]
        self.globals = globals[:]
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
        if instruction == CALL or instruction == CALL_MAP:
            base += " (%s)" % self.atoms[index].repr
        # XXX enabling this requires the JIT to be able to traverse a lot of
        # otherwise-unsafe code. You're free to try to fix it, but you've been
        # warned.
        # elif instruction == LITERAL:
        #     base += " (%s)" % self.literals[index].toString().encode("utf-8")
        elif instruction in (NOUN_GLOBAL, ASSIGN_GLOBAL, SLOT_GLOBAL,
                             BINDING_GLOBAL):
            base += " (%s)" % self.globals[index].encode("utf-8")
        elif instruction in (NOUN_FRAME, ASSIGN_FRAME, SLOT_FRAME,
                             BINDING_FRAME):
            base += " (%s)" % self.frame[index].encode("utf-8")
        elif instruction in (NOUN_LOCAL, ASSIGN_LOCAL, SLOT_LOCAL,
                             BINDING_LOCAL, BIND, BINDFINALSLOT,
                             BINDVARSLOT):
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
        self.maxDepth, self.maxHandlerDepth = ai.getDepth()
