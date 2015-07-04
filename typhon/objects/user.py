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

from rpython.rlib.jit import unroll_safe

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.objects.constants import NullObject, unwrapBool
from typhon.objects.collections import ConstList
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.ejectors import Ejector
from typhon.objects.guards import FinalSlotGuard, anyGuard
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.objects.slots import Binding, FinalSlot
from typhon.prelude import getGlobal
from typhon.smallcaps.machine import SmallCaps

# XXX AuditionStamp, Audition guard

ASK_1 = getAtom(u"ask", 1)
GETGUARD_1 = getAtom(u"getGuard", 1)
GETOBJECTEXPR_0 = getAtom(u"getObjectExpr", 0)
GETFQN_0 = getAtom(u"getFQN", 0)


@autohelp
class AstInflator(Object):
    def recv(self, atom, args):
        if atom.verb == u"run" and atom.arity >= 1:
            astBuilder = getGlobal(u"astBuilder")
            if astBuilder is NullObject:
                raise userError(u"node builder not yet installed, AST not available")
            nodeName = unwrapStr(args[0])
            # XXX Preserve spans
            return astBuilder.call(nodeName, args[1:] + [NullObject])
        raise Refused(self, atom, args)


@autohelp
class Audition(Object):

    def __init__(self, fqn, ast, guards, cache):
        self.fqn = fqn
        self.ast = ast
        self.guards = guards
        self.cache = None

        self.active = True
        self.approvers = []
        self.askedLog = []
        self.guardLog = []

    def ask(self, auditor):
        if not self.active:
            raise userError(u"audition is out of scope")

        doCaching = False
        cached = False

        if doCaching:
            if auditor in self.cache:
                answer, asked, guards = self.cache[auditor]
                for name, value in guards:
                    # We remember what the binding guards for the previous
                    # invocation were.
                    if self.guards[name] != value:
                        # If any of them have changed, we need to re-audit.
                        break
                else:
                    cached = True

        if cached:
            for a in asked:
                # We remember the other auditors invoked during this
                # audition. Let's re-ask them since not all of them may have
                # cacheable results.
                self.ask(a)
            if answer:
                self.approvers.append(auditor)
            return answer
        else:
            prevlogs = self.askedLog, self.guardLog
            self.askedLog = []
            self.guardLog = []
            try:
                result = unwrapBool(auditor.call(u"audit", [self]))
                if doCaching and self.guardLog is not None:
                    self.auditorCache[auditor] = (result, self.askedLog[:],
                                                  self.guardLog[:])
                if result:
                    self.approvers.append(auditor)
            finally:
                self.askedLog, self.guardLog = prevlogs

    def getGuard(self, name):
        if name not in self.guards:
            self.guardLog = None
            from typhon.objects.data import StrObject
            raise UserException(StrObject(u'"%s" is not a free variable in %s' %
                                (name, self.fqn)))
        answer = self.guards[name]
        if self.guardLog is not None:
            if False:  # DF check
                self.guardLog.append((name, answer))
            else:
                self.guardLog = None
        return answer

    def recv(self, atom, args):
        if atom is ASK_1:
            return self.ask(args[0])

        if atom is GETGUARD_1:
            return self.getGuard(unwrapStr(args[0]))

        if atom is GETOBJECTEXPR_0:
            if self.ast.monteAST is None:
                self.ast.monteAST = self.ast.slowTransform(AstInflator())
            return self.ast.monteAST

        if atom is GETFQN_0:
            assert isinstance(self.fqn, unicode)
            return StrObject(self.fqn)

        raise Refused(self, atom, args)


class ScriptObject(Object):

    _immutable_fields_ = ("codeScript", "displayName", "globals[*]",
                          "closure[*]", "fqn")
    auditorCache = {}

    stamps = []

    def __init__(self, codeScript, globals, globalsNames,
                 closure, closureNames, displayName, auditors, fqn):
        self.codeScript = codeScript
        self.globals = globals
        self.closure = closure
        self.displayName = displayName
        self.fqn = fqn

        # Make sure that we can access ourselves.
        self.patchSelf(auditors[0]
                       if len(auditors) > 0 and auditors[0] != NullObject
                       else anyGuard)

        # XXX this should all eventually be on the codeScript so that the
        # caching can be auto-shared amongst all instances of this class.
        if auditors:
            self.stamps = self.audit(auditors, self.codeScript.objectAst,
                                     closureNames, globalsNames)[:]

    def audit(self, auditors, ast, closureNames, globalsNames):
        if auditors[0] == NullObject:
            del auditors[0]
        guards = {}
        for name, i in globalsNames.items():
            guards[name] = self.globals[i].call(u"getGuard", [])
        for name, i in closureNames.items():
            guards[name] = self.closure[i].call(u"getGuard", [])

        audition = Audition(self.fqn, ast, guards, {})
        for a in auditors:
            audition.ask(a)
        audition.active = False
        return audition.approvers

    def patchSelf(self, guard):
        selfIndex = self.codeScript.selfIndex()
        if selfIndex != -1:
            self.closure[selfIndex] = Binding(
                FinalSlot(self, guard),
                FinalSlotGuard(guard))

    def toString(self):
        # Easily the worst part of the entire stringifying experience. We must
        # be careful to not recurse here.
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.displayName
        except UserException, e:
            return u"<%s (threw exception %s when printed)>" % (self.displayName, e.error())

    def printOn(self, printer):
        # Note that the printer is a Monte-level object. Also note that, at
        # this point, we have had a bad day; we did not respond to _printOn/1.
        from typhon.objects.data import StrObject
        printer.call(u"print", [StrObject(u"<%s>" % self.displayName)])

    def docString(self):
        return self.codeScript.doc

    def respondingAtoms(self):
        # Only do methods for now. Matchers will be dealt with in other ways.
        return self.codeScript.methods.keys()

    @unroll_safe
    def recv(self, atom, args):
        code = self.codeScript.lookupMethod(atom)
        if code is None:
            # No atoms matched, so there's no prebuilt methods. Instead, we'll
            # use our matchers.
            for matcher in self.codeScript.matchers:
                with Ejector() as ej:
                    machine = SmallCaps(matcher, self.closure, self.globals)
                    machine.push(ConstList([StrObject(atom.verb),
                                            ConstList(args)]))
                    machine.push(ej)
                    try:
                        machine.run()
                        return machine.pop()
                    except Ejecting as e:
                        if e.ejector is ej:
                            # Looks like unification failed. On to the next
                            # matcher!
                            continue
                        else:
                            # It's not ours, cap'n.
                            raise

            raise Refused(self, atom, args)

        machine = SmallCaps(code, self.closure, self.globals)
        # print "--- Running", self.displayName, atom, args
        # Push the arguments onto the stack, backwards.
        for arg in reversed(args):
            machine.push(arg)
            machine.push(NullObject)
        machine.run()
        return machine.pop()
