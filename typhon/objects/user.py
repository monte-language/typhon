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

from rpython.rlib.objectmodel import specialize

from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.log import log
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.constants import unwrapBool
from typhon.objects.collections.helpers import monteSet
from typhon.objects.root import Object
from typhon.profile import profileTyphon

# XXX AuditionStamp, Audition guard

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

    def __init__(self, fqn, ast, guardInfo):
        self.fqn = fqn
        assert isinstance(ast, Object)
        self.ast = ast
        self.guardInfo = guardInfo
        guardInfo.clean()

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
                if self.guardInfo.getGuard(name) != value:
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
        answer = self.guardInfo.getGuard(name)
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
        return AuditorReport(s, self.guardInfo.isDynamic())

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

    def __init__(self, stamps, isDynamic):
        self.stamps = stamps
        self.isDynamic = isDynamic

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


class Drawer(object):
    """
    A storage system for reports.
    """

class DynamicDrawer(Drawer):

    def __init__(self):
        self.files = []

    def findReport(self, guardInfo):
        gs = guardInfo.dynamicGuards()
        for guardValues, report in self.files:
            if compareGuardMaps(guardValues, gs):
                return report

    def makeDynamic(self):
        return self

class StaticDrawer(Drawer):

    def __init__(self, report):
        self.report = report

    def findReport(self, guardInfo):
        return self.report

    def makeDynamic(self):
        drawer = DynamicDrawer()
        drawer.files.append(([], self.report))


class AuditClipboard(object):
    """
    She is fast and thorough / And sharp as a tack
    She's touring the facility / And picking up slack
    """

    def __init__(self, fqn, ast):
        self.reportCabinet = []
        self.fqn = fqn
        self.ast = ast

        # This rate is typically less than 0.3%; our caching is very good
        # these days. ~ C.
        # from typhon.metrics import globalRecorder
        # self.newReportRate = globalRecorder().getRateFor(
        #         "AuditClipboard new report")

    def getReport(self, auditors, guardInfo):
        """
        Fetch an existing audit report if one for this auditor/guard
        combination is on file.
        """

        for auditorList, guardFile in self.reportCabinet:
            if compareAuditorLists(auditors, auditorList):
                report = guardFile.findReport(guardInfo)
                if report is not None:
                    return report

    def putReport(self, auditors, guardInfo, report):
        """
        Keep an audit report on file for these guards and this auditor.
        """

        for i, (auditorList, guardFile) in enumerate(self.reportCabinet):
            if compareAuditorLists(auditors, auditorList):
                if report.isDynamic:
                    gs = guardInfo.dynamicGuards()
                    guardFile = guardFile.makeDynamic()
                    assert isinstance(guardFile, DynamicDrawer), "protractor"
                    guardFile.files.append((gs, report))
                else:
                    guardFile = StaticDrawer(report)
                self.reportCabinet[i] = auditorList, guardFile
                break
        else:
            self.reportCabinet.append((auditors, StaticDrawer(report)))

    def createReport(self, auditors, guardInfo):
        """
        Do an audit, make a report from the results.
        """

        with Audition(self.fqn, self.ast, guardInfo) as audition:
            for a in auditors:
                audition.ask(a)
        return audition.prepareReport()

    def audit(self, auditors, guardInfo):
        """
        Hold an audition and return a report of the results.

        Auditions are cached for quality assurance and training purposes.
        """

        report = self.getReport(auditors, guardInfo)
        # if self.newReportRate.observe(report is None):
        if report is None:
            report = self.createReport(auditors, guardInfo)
            self.putReport(auditors, guardInfo, report)
        return report
