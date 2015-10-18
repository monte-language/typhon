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

from rpython.rlib.debug import debug_print

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Ejecting, Refused, UserException
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections import (ConstList, ConstMap, monteDict,
                                        unwrapList)
from typhon.objects.data import StrObject
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.equality import EQUAL, INEQUAL, NOTYET, optSame
from typhon.objects.root import Object


DOESNOTEJECT_1 = getAtom(u"doesNotEject", 1)
EJECTS_1 = getAtom(u"ejects", 1)
EQUAL_2 = getAtom(u"equal", 2)
NOTEQUAL_2 = getAtom(u"notEqual", 2)
RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
STARTTEST_1 = getAtom(u"startTest", 1)
THROWS_1 = getAtom(u"throws", 1)


@autohelp
class Asserter(Object):
    """
    A unit test assertion manager.

    This object allows claims to be made, and stores cases where the
    assertions failed.
    """

    _label = None

    def __init__(self):
        self._errors = {}

    def recv(self, atom, args):
        if atom is DOESNOTEJECT_1:
            with Ejector() as ej:
                try:
                    args[0].call(u"run", [ej])
                except Ejecting as e:
                    if e.ejector is ej:
                        self.log(u"Ejector was fired")
                    else:
                        raise
            return NullObject

        if atom is EJECTS_1:
            success = False
            with Ejector() as ej:
                try:
                    args[0].call(u"run", [ej])
                except Ejecting as e:
                    if e.ejector is ej:
                        success = True
                    else:
                        raise
            if not success:
                self.log(u"Ejector was not fired")
            return NullObject

        if atom is EQUAL_2:
            result = optSame(args[0], args[1])
            if result is NOTYET:
                self.log(u"Equality not yet decidable: %s ?= %s" %
                        (args[0].toQuote(), args[1].toQuote()))
            if result is INEQUAL:
                self.log(u"Not equal: %s != %s" %
                        (args[0].toQuote(), args[1].toQuote()))
            return NullObject

        if atom is NOTEQUAL_2:
            result = optSame(args[0], args[1])
            if result is NOTYET:
                self.log(u"Equality not yet decidable: %s ?= %s" %
                        (args[0].toQuote(), args[1].toQuote()))
            if result is EQUAL:
                self.log(u"Equal: %s == %s" %
                        (args[0].toQuote(), args[1].toQuote()))
            return NullObject

        if atom is THROWS_1:
            success = False
            try:
                args[0].call(u"run", [])
            except UserException:
                success = True
            if not success:
                self.log(u"No exception was thrown")
            return NullObject

        self.log(u"Unknown assertion made: %s" % atom.repr.decode("utf-8"))
        return NullObject

    def log(self, message):
        self._errors[self._label].append(message)

    def startTest(self, label):
        self._errors[label] = []
        self._label = label

    def dump(self):
        for label, errors in self._errors.items():
            if errors:
                debug_print(label.encode("utf-8"), "FAIL")
                for error in errors:
                    debug_print("    ERROR:", error.encode("utf-8"))
            else:
                debug_print(label.encode("utf-8"), "PASS")


@autohelp
class TestCollector(Object):
    """
    A unit test collector.

    Unit tests in various modules are aggregated here for the convenience of
    test runners.
    """
    def __init__(self):
        self._tests = {}

    def addTest(self, locus, test):
        if locus not in self._tests:
            self._tests[locus] = []
        self._tests[locus].append(test)

    def recv(self, atom, args):
        if atom is RUN_0:
            d = monteDict()
            for k in self._tests:
                d[StrObject(k)] = ConstList(self._tests[k][:])
            return ConstMap(d)
        raise Refused(self, atom, args)


@autohelp
class UnitTest(Object):
    """
    A unit test backend.

    Pass unit tests to this object, they will be available from its
    TestCollector.
    """

    # Not at all DF, but doesn't produce any app-affecting side effects.
    stamps = [deepFrozenStamp]

    def __init__(self, locus, testCollector):
        self.locus = locus
        self.testCollector = testCollector

    def recv(self, atom, args):
        if atom is RUN_1:
            for test in unwrapList(args[0]):
                self.testCollector.addTest(self.locus, test)
            return NullObject
        raise Refused(self, atom, args)
