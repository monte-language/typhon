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
from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.log import log
from typhon.objects.auditors import (deepFrozenStamp, selfless,
                                     transparentStamp)
from typhon.objects.constants import unwrapBool
from typhon.objects.collections.helpers import emptySet, monteSet
from typhon.objects.collections.lists import wrapList
from typhon.objects.data import StrObject
from typhon.objects.ejectors import Ejector
from typhon.objects.printers import Printer
from typhon.objects.root import Object
from typhon.profile import profileTyphon

# XXX AuditionStamp, Audition guard

_UNCALL_0 = getAtom(u"_uncall", 0)


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

    def __init__(self, fqn, ast, guards, dynamicGuards):
        assert isinstance(fqn, unicode)
        self.fqn = fqn
        self.ast = ast
        self.guards = guards

        self.cache = {}
        self.askedLog = []
        self.guardLog = []

        self.dynamicGuards = dynamicGuards
        self.neededDynamicGuards = False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.active = False

    @specialize.call_location()
    def log(self, message, tags=[]):
        log(["audit"] + tags, u"Auditor for %s: %s" % (self.fqn, message))

    @method.py("Bool", "Any")
    @profileTyphon("Auditor.ask/1")
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

    @method.py("Any", "Str")
    @profileTyphon("Auditor.getGuard/1")
    def getGuard(self, name):
        answer = self.guards.get(name, None)
        if answer is None:
            self.neededDynamicGuards = True
            answer = self.dynamicGuards.get(name, None)
        if answer is None:
            self.guardLog = None
            raise userError(u'"%s" is not a free variable in %s' %
                            (name, self.fqn))
        if self.guardLog is not None:
            if answer.auditedBy(deepFrozenStamp):
                self.log(u"getGuard/1: %s (DF)" % name)
                self.guardLog.append((name, answer))
            else:
                self.log(u"getGuard/1: %s (not DF)" % name)
                self.guardLog = None
        return answer

    def prepareReport(self):
        s = monteSet()
        for (k, (result, _, _)) in self.cache.items():
            if result:
                s[k] = None
        return AuditorReport(s)

    @method("Any")
    def getObjectExpr(self):
        return self.ast

    @method("Str")
    def getFQN(self):
        return self.fqn


class AuditorReport(object):
    """
    Artifact of an audition.
    """

    _immutable_ = True

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
        if not isSameEver(x, that[i]):
            return False
    return True


class AuditClipboard(object):
    """
    She is fast and thorough / And sharp as a tack
    She's touring the facility / And picking up slack
    """

    def __init__(self, fqn, ast):
        self.reportCabinet = []
        self.fqn = fqn
        self.ast = ast

        from typhon.metrics import globalRecorder
        self.dynamicRate = globalRecorder().getRateFor("Audition dynamic guards")

    def getReport(self, auditors, guards):
        """
        Fetch an existing audit report if one for this auditor/guard
        combination is on file.
        """

        for auditorList, guardFile in self.reportCabinet:
            if compareAuditorLists(auditors, auditorList):
                gs = guards.values()
                for guardValues, report in guardFile:
                    if compareGuardMaps(guardValues, gs):
                        return report
        return None

    def putReport(self, auditors, guards, report):
        """
        Keep an audit report on file for these guards and this auditor.
        """

        gs = guards.values()
        for auditorList, guardFile in self.reportCabinet:
            if compareAuditorLists(auditors, auditorList):
                guardFile.append((gs, report))
                break
        else:
            self.reportCabinet.append((auditors, [(gs, report)]))

    def createReport(self, auditors, guards, dynamicGuards):
        """
        Do an audit, make a report from the results.
        """

        with Audition(self.fqn, self.ast, guards, dynamicGuards) as audition:
            for a in auditors:
                audition.ask(a)
            self.dynamicRate.observe(audition.neededDynamicGuards)
        return audition.prepareReport()

    def audit(self, auditors, guards, dynamicGuards):
        """
        Hold an audition and return a report of the results.

        Auditions are cached for quality assurance and training purposes.
        """

        report = self.getReport(auditors, guards)
        if report is None:
            report = self.createReport(auditors, guards, dynamicGuards)
            self.putReport(auditors, guards, report)
        return report


class UserObjectHelper(object):
    """
    Abstract superclass for objects created by ObjectExpr.
    """
    _immutable_fields_ = "report",
    report = None

    def toString(self):
        # Easily the worst part of the entire stringifying experience. We must
        # be careful to not recurse here.
        try:
            printer = Printer()
            self.call(u"_printOn", [printer])
            return printer.value()
        except Refused:
            return u"<%s>" % self.getDisplayName()
        except UserException, e:
            return (u"<%s (threw exception %s when printed)>" %
                    (self.getDisplayName(), e.error()))

    def printOn(self, printer):
        # Note that the printer is a Monte-level object. Also note that, at
        # this point, we have had a bad day; we did not respond to _printOn/1.
        from typhon.objects.data import StrObject
        printer.call(u"print",
                     [StrObject(u"<%s>" % self.getDisplayName())])

    def auditorStamps(self):
        if self.report is None:
            return emptySet
        else:
            return self.report.getStamps()

    def isSettled(self, sofar=None):
        if selfless in self.auditorStamps():
            if transparentStamp in self.auditorStamps():
                from typhon.objects.collections.maps import EMPTY_MAP
                if sofar is None:
                    sofar = {self: None}
                # Uncall and recurse.
                return self.callAtom(_UNCALL_0, [],
                                     EMPTY_MAP).isSettled(sofar=sofar)
            # XXX Semitransparent support goes here

        # Well, we're resolved, so I guess that we're good!
        return True

    def recvNamed(self, atom, args, namedArgs):
        method = self.getMethod(atom)
        if method:
            return self.runMethod(method, args, namedArgs)
        else:
            # Maybe we should invoke a Miranda method.
            val = self.mirandaMethods(atom, args, namedArgs)
            if val is None:
                # No atoms matched, so there's no prebuilt methods. Instead,
                # we'll use our matchers.
                return self.runMatchers(atom, args, namedArgs)
            else:
                return val

    @unroll_safe
    def runMatchers(self, atom, args, namedArgs):
        message = wrapList([StrObject(atom.verb), wrapList(args),
                            namedArgs])
        for matcher in self.getMatchers():
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
