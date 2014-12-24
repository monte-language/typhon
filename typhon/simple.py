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

from typhon.atoms import getAtom
from typhon.errors import Refused, UserException
from typhon.objects.collections import ConstList, ConstMap
from typhon.objects.constants import BoolObject, NullObject, wrapBool
from typhon.objects.data import CharObject, DoubleObject, IntObject, StrObject
from typhon.objects.ejectors import throw
from typhon.objects.equality import Equalizer
from typhon.objects.guards import predGuard
from typhon.objects.iteration import loop
from typhon.objects.root import Object, runnable
from typhon.objects.slots import Binding
from typhon.objects.tests import UnitTest


VALUEMAKER_1 = getAtom(u"valueMaker", 1)
MATCHMAKER_1 = getAtom(u"matchMaker", 1)
FROMPAIRS_1 = getAtom(u"fromPairs", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
EJECT_2 = getAtom(u"eject", 2)
SUBSTITUTE_1 = getAtom(u"substitute", 1)


@predGuard
def boolGuard(specimen):
    return isinstance(specimen, BoolObject)


@predGuard
def charGuard(specimen):
    return isinstance(specimen, CharObject)


@predGuard
def doubleGuard(specimen):
    return isinstance(specimen, DoubleObject)


@predGuard
def intGuard(specimen):
    return isinstance(specimen, IntObject)


@predGuard
def strGuard(specimen):
    return isinstance(specimen, StrObject)


@predGuard
def listGuard(specimen):
    return isinstance(specimen, ConstList)


@predGuard
def mapGuard(specimen):
    return isinstance(specimen, ConstMap)


class Trace(Object):
    def toString(self):
        return u"<trace>"

    def call(self, verb, args):
        print "TRACE:",
        for obj in args:
            print obj.toQuote(),

        return NullObject


class TraceLn(Object):
    def toString(self):
        return u"<traceln>"

    def call(self, verb, args):
        print "TRACE:",
        for obj in args:
            print obj.toQuote(),
        print ""

        return NullObject


class MakeList(Object):
    def toString(self):
        return u"<makeList>"

    def call(self, verb, args):
        return ConstList(args)


@runnable(FROMPAIRS_1)
def makeMap(args):
    return ConstMap.fromPairs(args[0])


class Throw(Object):

    def toString(self):
        return u"<throw>"

    def recv(self, atom, args):
        if atom is RUN_1:
            raise UserException(args[0])

        if atom is EJECT_2:
            return throw(args[0], args[1])

        raise Refused(self, atom, args)


@runnable(RUN_2)
def slotToBinding(args):
    # XXX don't really care much about this right now
    specimen = args[0]
    # ej = args[1]
    return Binding(specimen)


def simpleScope():
    return {
        u"null": NullObject,

        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"Bool": boolGuard(),
        u"Char": charGuard(),
        u"Double": doubleGuard(),
        u"Int": intGuard(),
        u"List": listGuard(),
        u"Map": mapGuard(),
        u"Str": strGuard(),
        u"boolean": boolGuard(),
        u"int": intGuard(),

        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": MakeList(),
        u"__makeMap": makeMap(),
        u"__slotToBinding": slotToBinding(),
        u"throw": Throw(),
        u"trace": Trace(),
        u"traceln": TraceLn(),

        u"unittest": UnitTest(),
    }
