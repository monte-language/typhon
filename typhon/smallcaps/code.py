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
from rpython.rlib.jit import elidable, elidable_promote, look_inside_iff

from typhon.objects.user import Audition, BusyObject, QuietObject
from typhon.smallcaps.abstract import AbstractInterpreter
from typhon.smallcaps.ops import (ASSIGN_GLOBAL, ASSIGN_FRAME, ASSIGN_LOCAL,
                                  BIND, BINDFINALSLOT, BINDVARSLOT,
                                  SLOT_GLOBAL, SLOT_FRAME, SLOT_LOCAL,
                                  NOUN_GLOBAL, NOUN_FRAME, NOUN_LOCAL,
                                  BINDING_GLOBAL, BINDING_FRAME,
                                  BINDING_LOCAL, CALL, CALL_MAP)


class CodeScript(object):
    """
    A single compiled script object.
    """

    _immutable_ = True
    _immutable_fields_ = ("displayName", "objectAst", "numAuditors", "doc",
                          "fqn", "methods", "methodDocs", "matchers[*]",
                          "closureNames", "globalNames")

    def __init__(self, displayName, objectAst, numAuditors, doc, fqn, methods,
                 methodDocs, matchers, closureNames, globalNames):
        self.displayName = displayName
        self.objectAst = objectAst
        self.numAuditors = numAuditors
        self.doc = doc
        self.fqn = fqn
        self.methods = methods
        self.methodDocs = methodDocs
        self.matchers = matchers[:]
        self.closureNames = closureNames
        self.closureSize = len(closureNames)
        self.globalNames = globalNames
        self.globalSize = len(globalNames)

        self.auditions = {}

    def makeObject(self, closure, globals, auditors):
        if self.closureSize:
            obj = BusyObject(self, globals, closure, auditors)
        else:
            obj = QuietObject(self, globals, auditors)
        return obj

    # Picking 3 for the common case of:
    # `as DeepFrozen implements Selfless, Transparent`
    @look_inside_iff(lambda self, auditors, guards: len(auditors) <= 3)
    def audit(self, auditors, guards):
        with Audition(self.fqn, self.objectAst, guards, self.auditions) as audition:
            for a in auditors:
                audition.ask(a)
        return audition.approvers

    @elidable
    def selfIndex(self):
        """
        The index at which this codescript's objects should reference
        themselves, or -1 if the objects are not self-referential.
        """

        return self.closureNames.get(self.displayName, -1)

    @elidable_promote()
    def lookupMethod(self, atom):
        return self.methods.get(atom, None)

    @elidable
    def getMatchers(self):
        return self.matchers


class Code(object):
    """
    SmallCaps code object.

    I wish. It's machine code.
    """

    _immutable_ = True
    _immutable_fields_ = ("fqn", "methodName",
                          "instructions[*]?", "indices[*]?",
                          "atoms[*]", "globals[*]", "frame[*]", "literals[*]",
                          "locals[*]", "scripts[*]", "maxDepth",
                          "maxHandlerDepth")

    def __init__(self, fqn, methodName, instructions, atoms, literals,
                 globals, frame, locals, scripts):
        self.fqn = fqn
        self.methodName = methodName
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
        base = "%s %d" % (instruction.repr.encode("utf-8"), index)
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
            name, depth = self.locals[index]
            base += " (%s (%s))" % (name.encode("utf-8"), depth.repr)
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

    def profileName(self):
        try:
            filename, objname = self.fqn.encode("utf-8").split('$', 1)
        except ValueError:
            filename = "<unknown>"
            objname = self.fqn.encode("utf-8")
        method = self.methodName.encode("utf-8")
        return "mt:%s.%s:1:%s" % (objname, method, filename)

rvmprof.register_code_object_class(Code, Code.profileName)
