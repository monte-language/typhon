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
from rpython.rlib.jit import elidable, elidable_promote

from typhon.objects.user import Audition, BusyObject, QuietObject
from typhon.smallcaps.abstract import AbstractInterpreter
from typhon.smallcaps.ops import (ASSIGN_GLOBAL, ASSIGN_FRAME, ASSIGN_LOCAL,
                                  BIND, BINDOBJECT, BINDFINALSLOT, BINDVARSLOT,
                                  SLOT_GLOBAL, SLOT_FRAME, SLOT_LOCAL,
                                  NOUN_GLOBAL, NOUN_FRAME, NOUN_LOCAL,
                                  BINDING_GLOBAL, BINDING_FRAME,
                                  BINDING_LOCAL, CALL, CALL_MAP,
                                  LITERAL)


class MethodStrategy(object):
    """
    A Strategy for storing method and matcher information.
    """

    _immutable_ = True

class _EmptyStrategy(MethodStrategy):
    """
    A Strategy for an object with neither methods nor matchers.
    """

    _immutable_ = True

    def lookupMethod(self, atom):
        return None

    def getAtoms(self):
        return []

    def getMatchers(self):
        return []

EmptyStrategy = _EmptyStrategy()

class FunctionStrategy(MethodStrategy):
    """
    A Strategy for an object with exactly one method and no matchers.
    """

    _immutable_ = True

    def __init__(self, atom, method):
        self.atom = atom
        self.method = method

    def lookupMethod(self, atom):
        if atom is self.atom:
            return self.method
        return None

    def getAtoms(self):
        return [self.atom]

    def getMatchers(self):
        return []

class FnordStrategy(MethodStrategy):
    """
    A Strategy for an object with two to five methods and no matchers.

    The Law of Fives.
    """

    _immutable_ = True

    def __init__(self, methods):
        # `methods` is still a dictionary here.
        self.methods = [(k, v) for (k, v) in methods.items()]

    @elidable_promote()
    def lookupMethod(self, atom):
        for (ourAtom, method) in self.methods:
            if ourAtom is atom:
                return method
        return None

    def getAtoms(self):
        return [atom for (atom, _) in self.methods]

    def getMatchers(self):
        return []

class JumboStrategy(MethodStrategy):
    """
    A Strategy for an object with many methods and no matchers.
    """

    _immutable_ = True

    def __init__(self, methods):
        # `methods` is still a dictionary here.
        self.methods = methods

    @elidable_promote()
    def lookupMethod(self, atom):
        return self.methods.get(atom, None)

    def getAtoms(self):
        return self.methods.keys()

    def getMatchers(self):
        return []

class GenericStrategy(MethodStrategy):
    """
    A Strategy for an object with some methods and some matchers.
    """

    _immutable_ = True
    _immutable_fields_ = "methods", "matchers[*]"

    def __init__(self, methods, matchers):
        self.methods = methods
        self.matchers = matchers

    @elidable_promote()
    def lookupMethod(self, atom):
        return self.methods.get(atom, None)

    def getAtoms(self):
        return self.methods.keys()

    def getMatchers(self):
        return self.matchers

def chooseStrategy(methods, matchers):
    if matchers:
        return GenericStrategy(methods, matchers)
    elif not methods:
        return EmptyStrategy
    elif len(methods) == 1:
        atom, method = methods.items()[0]
        return FunctionStrategy(atom, method)
    elif len(methods) <= 5:
        return FnordStrategy(methods)
    else:
        return JumboStrategy(methods)


class AuditorReport(object):
    """
    Artifact of an audition.
    """

    _immutable_ = True
    _immutable_fields_ = "stamps[*]",

    def __init__(self, stamps):
        self.stamps = stamps

    def getStamps(self):
        return self.stamps


def compareAuditorLists(this, that):
    from typhon.objects.equality import isSameEver
    for i, x in enumerate(this):
        if not isSameEver(x, that[i]):
            return False
    return True

def compareGuardMaps(this, that):
    from typhon.objects.equality import isSameEver
    for i, x in enumerate(this):
        if not isSameEver(x[1], that[i][1]):
            return False
    return True


class CodeScript(object):
    """
    A single compiled script object.
    """

    _immutable_ = True
    _immutable_fields_ = ("strategy", "displayName", "objectAst",
                          "numAuditors", "doc", "fqn", "methodDocs",
                          "closureNames", "globalNames")

    def __init__(self, displayName, objectAst, numAuditors, doc, fqn, methods,
                 methodDocs, matchers, closureNames, globalNames):
        self.strategy = chooseStrategy(methods, matchers)

        self.displayName = displayName
        self.objectAst = objectAst
        self.numAuditors = numAuditors
        self.doc = doc
        self.fqn = fqn
        self.methodDocs = methodDocs
        self.closureNames = closureNames
        self.closureSize = len(closureNames)
        self.globalNames = globalNames
        self.globalSize = len(globalNames)

        self.reportCabinet = []

    def makeObject(self, closure, globals, auditors):
        if self.closureSize:
            obj = BusyObject(self, globals, closure, auditors)
        else:
            obj = QuietObject(self, globals, auditors)
        return obj

    def getReport(self, auditors, guards):
        for auditorList, guardFile in self.reportCabinet:
            if compareAuditorLists(auditors, auditorList):
                guardItems = guards.items()
                for guardMap, report in guardFile:
                    if compareGuardMaps(guardItems, guardMap):
                        return report
        return None

    def putReport(self, auditors, guards, report):
        guardItems = guards.items()
        for auditorList, guardFile in self.reportCabinet:
            if compareAuditorLists(auditors, auditorList):
                guardFile.append((guardItems, report))
                break
        else:
            self.reportCabinet.append((auditors, [(guardItems, report)]))

    def createReport(self, auditors, guards):
        with Audition(self.fqn, self.objectAst, guards) as audition:
            for a in auditors:
                audition.ask(a)
        return audition.prepareReport(auditors)

    def audit(self, auditors, guards):
        """
        Hold an audition and return a report of the results.

        Auditions are cached for quality assurance and training purposes.
        """

        report = self.getReport(auditors, guards)
        if report is None:
            report = self.createReport(auditors, guards)
            self.putReport(auditors, guards, report)
        return report

    @elidable
    def selfIndex(self):
        """
        The index at which this codescript's objects should reference
        themselves, or -1 if the objects are not self-referential.
        """

        return self.closureNames.get(self.displayName, -1)


class Code(object):
    """
    SmallCaps code object.

    I wish. It's machine code.
    """

    _immutable_ = True
    _immutable_fields_ = ("fqn", "methodName", "profileName",
                          "instructions[*]?", "indices[*]?",
                          "atoms[*]", "globals[*]", "frame[*]", "literals[*]",
                          "locals[*]", "scripts[*]", "maxDepth",
                          "maxHandlerDepth", "startingDepth")

    def __init__(self, fqn, methodName, instructions, atoms, literals,
                 globals, frame, locals, scripts, startingDepth):
        self.fqn = fqn
        self.methodName = methodName
        self.profileName = self._profileName()
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
        self.startingDepth = startingDepth

        # Arrays for tracking expected stack depth
        self.stackDepth = [0] * len(instructions)
        self.handlerDepth = [0] * len(instructions)

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

    def dis(self, instruction, index, stackDepth, handlerDepth):
        base = u"S:%d H:%d | %s %d" % (stackDepth, handlerDepth,
                                       instruction.repr, index)
        if instruction == CALL or instruction == CALL_MAP:
            base += u" (%s)" % self.atoms[index].repr.decode("utf-8")
        elif instruction == LITERAL:
            base += u" (%s)" % self.literals[index].toQuote()
        elif instruction == BINDOBJECT:
            base += u" (%s)" % self.scripts[index][0].fqn
        elif instruction in (NOUN_GLOBAL, ASSIGN_GLOBAL, SLOT_GLOBAL,
                             BINDING_GLOBAL):
            base += u" (%s)" % self.globals[index]
        elif instruction in (NOUN_FRAME, ASSIGN_FRAME, SLOT_FRAME,
                             BINDING_FRAME):
            base += u" (%s)" % self.frame[index]
        elif instruction in (NOUN_LOCAL, ASSIGN_LOCAL, SLOT_LOCAL,
                             BINDING_LOCAL, BIND, BINDFINALSLOT,
                             BINDVARSLOT):
            name, slotType = self.locals[index]
            base += u" (%s (%s))" % (name, slotType.repr())
        return base

    @elidable
    def disAt(self, pc):
        instruction = self.instructions[pc]
        index = self.indices[pc]
        stackDepth = self.stackDepth[pc]
        handlerDepth = self.handlerDepth[pc]
        return self.dis(instruction, index, stackDepth, handlerDepth)

    def disassemble(self):
        rv = [u"Code for %s: S:%d" % (self.profileName.decode("utf-8"),
                                      self.startingDepth)]
        for i in range(len(self.instructions)):
            rv.append(u"%d: %s" % (i, self.disAt(i)))
        return u"\n".join(rv)

    def figureMaxDepth(self):
        ai = AbstractInterpreter(self)
        ai.run()
        maxDepth, self.maxHandlerDepth = ai.getDepth()
        self.maxDepth = max(maxDepth, self.startingDepth)

    @elidable
    def _profileName(self):
        try:
            filename, objname = self.fqn.encode("utf-8").split('$', 1)
        except ValueError:
            filename = "<unknown>"
            objname = self.fqn.encode("utf-8")
        method = self.methodName.encode("utf-8")
        return "mt:%s.%s:1:%s" % (objname, method, filename)

rvmprof.register_code_object_class(Code, lambda code: code.profileName)
