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

from unittest import TestCase

from typhon.objects.data import CharObject, DoubleObject, IntObject, StrObject
from typhon.objects.equality import EQUAL, INEQUAL, NOTYET, isSettled, optSame
from typhon.objects.lists import makeList
from typhon.objects.refs import makePromise


class TestIsSettled(TestCase):

    def testInt(self):
        i = IntObject(42)
        self.assertTrue(isSettled(i))

    def testPromise(self):
        p, r = makePromise()
        self.assertFalse(isSettled(p))

    def testPromiseResolved(self):
        p, r = makePromise()
        r.resolve(IntObject(42))
        self.assertTrue(isSettled(p))


class TestOptSame(TestCase):

    def testCharEquality(self):
        first = CharObject(u'c')
        second = CharObject(u'c')
        self.assertEqual(optSame(first, second), EQUAL)

    def testDoubleEquality(self):
        first = DoubleObject(4.2)
        second = DoubleObject(4.2)
        self.assertEqual(optSame(first, second), EQUAL)

    def testIntEquality(self):
        first = IntObject(42)
        second = IntObject(42)
        self.assertEqual(optSame(first, second), EQUAL)

    def testListEquality(self):
        first = makeList([IntObject(42)])
        second = makeList([IntObject(42)])
        self.assertEqual(optSame(first, second), EQUAL)

    def testListEqualityRecursionReflexive(self):
        first = makeList([makeList([]), IntObject(42)])
        # This nasty incantation is required to mutate constant lists.
        first.storage = first.strategy.stash(
                first.strategy.unstash(first.storage) + [first])
        self.assertEqual(optSame(first, first), EQUAL)

    def testListEqualityRecursion(self):
        first = makeList([makeList([]), IntObject(42)])
        # This nasty incantation is required to mutate constant lists.
        first.storage = first.strategy.stash(
                first.strategy.unstash(first.storage) + [first])
        second = makeList([makeList([]), IntObject(42)])
        # And again here.
        second.storage = second.strategy.stash(
                second.strategy.unstash(second.storage) + [second])
        self.assertEqual(optSame(first, second), EQUAL)

    def testListInequality(self):
        first = makeList([IntObject(42)])
        second = makeList([IntObject(41)])
        self.assertEqual(optSame(first, second), INEQUAL)

    def testListInequalityLength(self):
        first = makeList([IntObject(42)])
        second = makeList([IntObject(42), IntObject(5)])
        self.assertEqual(optSame(first, second), INEQUAL)

    def testStrEquality(self):
        first = StrObject(u"cs")
        second = StrObject(u"cs")
        self.assertEqual(optSame(first, second), EQUAL)

    def testRefEqualityReflexive(self):
        p, r = makePromise()
        self.assertEqual(optSame(p, p), EQUAL)

    def testRefEquality(self):
        first, r = makePromise()
        second, r = makePromise()
        self.assertEqual(optSame(first, second), NOTYET)

    def testRefEqualitySettled(self):
        first, r = makePromise()
        r.resolve(IntObject(42))
        second, r = makePromise()
        r.resolve(IntObject(42))
        self.assertEqual(optSame(first, second), EQUAL)
