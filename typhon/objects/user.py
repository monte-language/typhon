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

from rpython.rlib.jit import elidable, elidable_promote, unroll_safe
from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.env import emptyEnv
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.log import log
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.collections.lists import ConstList
from typhon.objects.data import StrObject, unwrapStr
from typhon.objects.ejectors import Ejector
from typhon.objects.guards import anyGuard
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.objects.slots import finalBinding

# XXX AuditionStamp, Audition guard

ASK_1 = getAtom(u"ask", 1)
GETGUARD_1 = getAtom(u"getGuard", 1)
GETOBJECTEXPR_0 = getAtom(u"getObjectExpr", 0)
GETFQN_0 = getAtom(u"getFQN", 0)


pemci = u".".join([
    u"lo lebna cu rivbi",
    u"lo nu fi ri facki",
    u"fa le vi larmuzga",
    u"fe le zi ca du'u",
    u"le lebna pu jbera",
    u"lo catlu pe ro da",
])

def boolStr(b):
    return u"true" if b else u"false"


@autohelp
class Audition(Object):
    """
    The context for an object's performance review.

    During audition, an object's structure is examined by a series of auditors
    which the object has specified. This object is capable of verifying to any
    concerned parties that the object has undergone the specified auditions.
    """

    _immutable_fields_ = "fqn", "ast", "guards"
    # Whether the audition is still fresh and usable.
    active = True

    def __init__(self, fqn, ast, guards):
        assert isinstance(fqn, unicode)
        self.fqn = fqn
        self.ast = ast
        self.guards = guards

        self.cache = {}
        self.askedLog = []
        self.guardLog = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.active = False

    @specialize.call_location()
    def log(self, message, tags=[]):
        log(["audit"] + tags, u"Auditor for %s: %s" % (self.fqn, message))

    def ask(self, auditor):
        if not self.active:
            self.log(u"ask/1: Stolen audition: %s" % pemci, tags=["serious"])
            raise userError(u"Audition is out of scope")

        cached = False

        self.askedLog.append(auditor)
        if auditor in self.cache:
            answer, asked, guards = self.cache[auditor]
            self.log(u"ask/1: %s: %s (cached)" % (auditor.toString(),
                boolStr(answer)))
            for name, value in guards:
                # We remember what the binding guards for the previous
                # invocation were.
                if self.guards[name] != value:
                    # If any of them have changed, we need to re-audit.
                    self.log(u"ask/1: %s: Invalidating" % name)
                    break
            else:
                # XXX stopgap: Ignore negative answers in the cache.
                cached = answer

        if cached:
            for a in asked:
                # We remember the other auditors invoked during this
                # audition. Let's re-ask them since not all of them may have
                # cacheable results.
                self.log(u"ask/1: Reasking %s" % auditor.toString())
                answer = self.ask(a)
            return answer
        else:
            # This seems a little convoluted, but the idea is that the logs
            # are written to during the course of the audition, and then
            # copied out to the cache afterwards.
            prevlogs = self.askedLog, self.guardLog
            self.askedLog = []
            self.guardLog = []
            try:
                result = unwrapBool(auditor.call(u"audit", [self]))
                if self.guardLog is None:
                    self.log(u"ask/1: %s: %s (uncacheable)" %
                            (auditor.toString(), boolStr(result)))
                else:
                    self.log(u"ask/1: %s: %s" %
                            (auditor.toString(), boolStr(result)))
                    self.cache[auditor] = (result, self.askedLog[:],
                                           self.guardLog[:])
                return result
            finally:
                self.askedLog, self.guardLog = prevlogs

        self.log(u"ask/1: %s: failure" % auditor.toString())
        return False

    def getGuard(self, name):
        if name not in self.guards:
            self.guardLog = None
            raise userError(u'"%s" is not a free variable in %s' %
                            (name, self.fqn))
        answer = self.guards[name]
        if self.guardLog is not None:
            if answer.auditedBy(deepFrozenStamp):
                self.log(u"getGuard/1: %s (DF)" % name)
                self.guardLog.append((name, answer))
            else:
                self.log(u"getGuard/1: %s (not DF)" % name)
                self.guardLog = None
        return answer

    def prepareReport(self, auditors):
        from typhon.smallcaps.code import AuditorReport
        stamps = [k for (k, (result, _, _)) in self.cache.items() if result]
        return AuditorReport(stamps)

    def recv(self, atom, args):
        if atom is ASK_1:
            return wrapBool(self.ask(args[0]))

        if atom is GETGUARD_1:
            return self.getGuard(unwrapStr(args[0]))

        if atom is GETOBJECTEXPR_0:
            return self.ast

        if atom is GETFQN_0:
            return StrObject(self.fqn)

        raise Refused(self, atom, args)


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


class FunScript(Object):
    """
    A recipe for laughter and merriment.
    """

    _immutable_ = True

    def __init__(self, objectAST):
        self.objectAST = objectAST
        self.fileName = u"unknown.mt"
        self.objectName = objectAST._n.repr().decode("utf-8")
        self.docstring = objectAST._d

        script = objectAST._script
        methodDict = {}
        for method in script._methods:
            methodDict[method.getAtom()] = method
        self.strategy = chooseStrategy(methodDict, script._matchers)

        self.reportCabinet = []
        # XXX
        self.methodDocs = {}

    def getFQN(self):
        return u"%s$%s" % (self.fileName, self.objectName)

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
        with Audition(self.getFQN(), self.objectAST, guards) as audition:
            for a in auditors:
                audition.ask(a)
        return audition.prepareReport(auditors)


class ScriptObject(Object):
    """
    An object whose behavior depends on a Monte script.
    """

    _immutable_fields_ = "script", "globals[*]", "report"

    report = None

    def toString(self):
        # Easily the worst part of the entire stringifying experience. We must
        # be careful to not recurse here.
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.script.objectName
        except UserException, e:
            return (u"<%s (threw exception %s when printed)>" %
                    (self.script.objectName, e.error()))
    def printOn(self, printer):
        # Note that the printer is a Monte-level object. Also note that, at
        # this point, we have had a bad day; we did not respond to _printOn/1.
        from typhon.objects.data import StrObject
        printer.call(u"print",
                     [StrObject(u"<%s>" % self.script.objectName)])

    def auditorStamps(self):
        if self.report is None:
            return []
        else:
            return self.report.getStamps()

    def docString(self):
        return self.script.docstring

    def respondingAtoms(self):
        # Only do methods for now. Matchers will be dealt with in other ways.
        d = {}
        for atom in self.script.strategy.getAtoms():
            d[atom] = self.script.methodDocs.get(atom, None)

        return d

    def recvNamed(self, atom, args, namedArgs):
        method = self.script.strategy.lookupMethod(atom)
        if method:
            return self.runMethod(method, args, namedArgs)
        else:
            # No atoms matched, so there's no prebuilt methods. Instead, we'll
            # use our matchers.
            return self.runMatchers(atom, args, namedArgs)

    @unroll_safe
    def runMatchers(self, atom, args, namedArgs):
        message = ConstList([StrObject(atom.verb), ConstList(args),
                             namedArgs])
        for matcher in self.script.strategy.getMatchers():
            with Ejector() as ej:
                try:
                    return self.runMatcher(matcher, message, ej)
                except Ejecting as e:
                    if e.ejector is ej:
                        # Looks like unification failed. On to the next
                        # matcher!
                        continue
                    else:
                        # It's not ours, cap'n.
                        raise

        raise Refused(self, atom, args)


class QuietObject(ScriptObject):
    """
    An object without a closure.
    """

    _immutable_ = True

    def __init__(self, script, auditors):
        self.script = script

        # The first auditor is our as-auditor, and it can be null.
        if auditors[0] is NullObject:
            auditors = auditors[1:]
        self.auditors = auditors

        # Do the auditing dance.
        if auditors:
            self.report = self.script.audit(auditors, {})

    def runMethod(self, method, args, namedArgs):
        return method.evalMethod(args, namedArgs, emptyEnv)

    def runMatcher(self, matcher, message, ej):
        return matcher.evalMatcher(message, ej, emptyEnv)


class BusyObject(ScriptObject):
    """
    An object with a closure.
    """

    _immutable_ = True
    _immutable_fields_ = "closure",

    def __init__(self, script, closure, auditors):
        self.script = script
        self.closure = closure

        # The first auditor is our as-auditor, so it'll also be the guard. If
        # it's null, then we'll use Any as our guard.
        if auditors[0] is NullObject:
            self.patchSelf(anyGuard)
            auditors = auditors[1:]
        else:
            self.patchSelf(auditors[0])
        self.auditors = auditors

        # Grab the guards of our globals and send them off for processing.
        if auditors:
            guards = self.closure.getGuards()
            self.report = self.script.audit(auditors, guards)

    def patchSelf(self, guard):
        return
        selfIndex = self.script.selfIndex()
        if selfIndex != -1:
            self.closure[selfIndex] = finalBinding(self, guard)

    def runMethod(self, method, args, namedArgs):
        staticScope = method.getCompleteStaticScope()
        return method.evalMethod(args, namedArgs,
                self.closure.new(staticScope.outNames()))

    def runMatcher(self, matcher, message, ej):
        return matcher.evalMatcher(message, ej,
                self.closure.new(matcher.getStaticScope().outNames()))
