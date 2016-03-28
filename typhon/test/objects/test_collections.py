# encoding: utf-8
#
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

from typhon.errors import UserException
from typhon.objects.collections.lists import wrapList, FlexList, unwrapList
from typhon.objects.collections.maps import ConstMap, monteMap
from typhon.objects.collections.sets import ConstSet, monteSet
from typhon.objects.data import CharObject, IntObject


class TestConstMap(TestCase):

    def testContains(self):
        d = monteMap()
        d[IntObject(42)] = IntObject(5)
        m = ConstMap(d)
        self.assertTrue(m.contains(IntObject(42)))
        self.assertFalse(m.contains(IntObject(7)))

    def testToString(self):
        d = monteMap()
        self.assertEqual(ConstMap(d).toString(), u"[].asMap()")

    def testSurprisingMapCorruption(self):
        d = monteMap()
        d[IntObject(1)] = IntObject(2)
        m = ConstMap(d)
        f = m.call(u"diverge", [])
        f.call(u"removeKey", [IntObject(1)])
        result = m.call(u"get", [IntObject(1)])
        self.assertEqual(result.getInt(), 2)


class TestwrapList(TestCase):

    def testCmpShortLeft(self):
        a = wrapList([IntObject(2)])
        b = wrapList([IntObject(2), IntObject(4)])
        result = a.call(u"op__cmp", [b])
        self.assertEqual(result.getInt(), -1)

    def testCmpShortRight(self):
        a = wrapList([IntObject(2), IntObject(4)])
        b = wrapList([IntObject(2)])
        result = a.call(u"op__cmp", [b])
        self.assertEqual(result.getInt(), 1)

    def testGetNegative(self):
        l = wrapList([])
        self.assertRaises(UserException, l.call, u"get", [IntObject(-1)])

    def testHashEqual(self):
        a = wrapList([IntObject(42), CharObject(u'é')])
        b = wrapList([IntObject(42), CharObject(u'é')])
        self.assertEqual(a.samenessHash(), b.samenessHash())

    def testHashInequalLength(self):
        a = wrapList([IntObject(42), CharObject(u'é')])
        b = wrapList([IntObject(42)])
        self.assertNotEqual(a.samenessHash(), b.samenessHash())

    def testHashInequalItems(self):
        a = wrapList([IntObject(42), CharObject(u'é')])
        b = wrapList([IntObject(42), CharObject(u'e')])
        self.assertNotEqual(a.samenessHash(), b.samenessHash())

    def testSlice(self):
        l = wrapList(map(CharObject, "abcdefg"))
        result = l.call(u"slice", [IntObject(3), IntObject(6)])
        chars = [char._c for char in unwrapList(result)]
        self.assertEqual(chars, list("def"))


class TestFlexList(TestCase):

    def testPop(self):
        l = FlexList([IntObject(42)])
        result = l.call(u"pop", [])
        self.assertEqual(result.getInt(), 42)

    def testPopMany(self):
        l = FlexList([IntObject(42), IntObject(5)])
        result = l.call(u"pop", [])
        self.assertEqual(result.getInt(), 5)

    def testPopManyHeterogenous(self):
        l = FlexList([CharObject(u'm'), IntObject(5)])
        result = l.call(u"pop", [])
        self.assertEqual(result.getInt(), 5)

    def testToStringEmpty(self):
        l = FlexList([])
        self.assertEqual(l.toString(), u"[].diverge()")

    def testToStringOne(self):
        l = FlexList([IntObject(42)])
        self.assertEqual(l.toString(), u"[42].diverge()")

    def testToStringMany(self):
        l = FlexList([IntObject(5), IntObject(42)])
        self.assertEqual(l.toString(), u"[5, 42].diverge()")

    def testContains(self):
        l = FlexList([IntObject(5), CharObject(u'a')])
        self.assertTrue(l.contains(IntObject(5)))
        self.assertFalse(l.contains(IntObject(42)))
        self.assertFalse(l.contains(l))

    def testPutSize(self):
        l = FlexList([IntObject(5), CharObject(u'a')])
        l.put(1, IntObject(7))
        expected = [IntObject(5), IntObject(7)]
        self.assertEqual(l.strategy.size(l), len(expected))


class TestConstSet(TestCase):

    def testHashEqual(self):
        d = monteSet()
        d[IntObject(42)] = None
        d[CharObject(u'¡')] = None
        a = ConstSet(d)
        b = ConstSet(d)
        self.assertEqual(a.samenessHash(), b.samenessHash())

    def testToStringEmpty(self):
        d = monteSet()
        self.assertEqual(ConstSet(d).toString(), u"[].asSet()")

    def testToString(self):
        d = monteSet()
        d[IntObject(42)] = None
        self.assertEqual(ConstSet(d).toString(), u"[42].asSet()")
