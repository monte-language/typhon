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

from rpython.rlib.rbigint import rbigint

from typhon.objects.collections.lists import wrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.equality import EQUAL, INEQUAL, NOTYET, optSame
from typhon.objects.refs import makePromise
from typhon.vats import scopedVat, testingVat


class TestIsSettled(TestCase):

    def testInt(self):
        i = IntObject(42)
        self.assertTrue(i.isSettled())

    def testNaN(self):
        d = DoubleObject(float("nan"))
        self.assertTrue(d.isSettled())

    def testPromise(self):
        with scopedVat(testingVat()):
            p, r = makePromise()
            self.assertFalse(p.isSettled())

    def testPromiseResolved(self):
        with scopedVat(testingVat()):
            p, r = makePromise()
            r.resolve(IntObject(42))
            self.assertTrue(p.isSettled())


class TestOptSame(TestCase):

    def testCharEquality(self):
        first = CharObject(u'c')
        second = CharObject(u'c')
        self.assertEqual(optSame(first, second), EQUAL)

    def testDoubleEquality(self):
        first = DoubleObject(4.2)
        second = DoubleObject(4.2)
        self.assertEqual(optSame(first, second), EQUAL)

    def testDoubleEqualityNaN(self):
        first = DoubleObject(float("nan"))
        second = DoubleObject(float("nan"))
        self.assertEqual(optSame(first, second), EQUAL)

    def testIntEquality(self):
        first = IntObject(42)
        second = IntObject(42)
        self.assertEqual(optSame(first, second), EQUAL)

    def testBigIntEquality(self):
        first = BigInt(rbigint.fromint(42))
        second = BigInt(rbigint.fromint(42))
        self.assertEqual(optSame(first, second), EQUAL)

    def testIntAndBigIntEquality(self):
        first = IntObject(42)
        second = BigInt(rbigint.fromint(42))
        self.assertEqual(optSame(first, second), EQUAL)

    def testBigIntAndIntEquality(self):
        first = BigInt(rbigint.fromint(42))
        second = IntObject(42)
        self.assertEqual(optSame(first, second), EQUAL)

    def testListEquality(self):
        first = wrapList([IntObject(42)])
        second = wrapList([IntObject(42)])
        self.assertEqual(optSame(first, second), EQUAL)

    def testListEqualityRecursionReflexive(self):
        first = wrapList([IntObject(42), NullObject])
        # Hax.
        first.objs.append(first)
        self.assertEqual(optSame(first, first), EQUAL)

    def testListEqualityRecursion(self):
        first = wrapList([IntObject(42), NullObject])
        # Hax.
        first.objs.append(first)
        second = wrapList([IntObject(42), NullObject])
        # Hax.
        second.objs.append(second)
        self.assertEqual(optSame(first, second), EQUAL)

    def testListInequality(self):
        first = wrapList([IntObject(42)])
        second = wrapList([IntObject(41)])
        self.assertEqual(optSame(first, second), INEQUAL)

    def testListInequalityLength(self):
        first = wrapList([IntObject(42)])
        second = wrapList([IntObject(42), IntObject(5)])
        self.assertEqual(optSame(first, second), INEQUAL)

    def testStrEquality(self):
        first = StrObject(u"cs")
        second = StrObject(u"cs")
        self.assertEqual(optSame(first, second), EQUAL)

    def testStrInequality(self):
        first = StrObject(u"false")
        second = StrObject(u"true")
        self.assertEqual(optSame(first, second), INEQUAL)

    def testRefEqualityReflexive(self):
        with scopedVat(testingVat()):
            p, r = makePromise()
            self.assertEqual(optSame(p, p), EQUAL)

    def testRefEquality(self):
        with scopedVat(testingVat()):
            first, r = makePromise()
            second, r = makePromise()
            self.assertEqual(optSame(first, second), NOTYET)

    def testRefEqualitySettled(self):
        with scopedVat(testingVat()):
            first, r = makePromise()
            r.resolve(IntObject(42))
            second, r = makePromise()
            r.resolve(IntObject(42))
            self.assertEqual(optSame(first, second), EQUAL)

    def testNaNFail(self):
        # Found by accident.
        first = DoubleObject(float("nan"))
        second = IntObject(42)
        self.assertEqual(optSame(first, second), INEQUAL)
