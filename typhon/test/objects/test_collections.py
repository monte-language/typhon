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

from typhon.objects.collections import ConstMap, ConstSet, monteDict
from typhon.objects.data import CharObject, IntObject


class TestConstMap(TestCase):

    def testContains(self):
        d = monteDict()
        d[IntObject(42)] = IntObject(5)
        m = ConstMap(d)
        self.assertTrue(m.contains(IntObject(42)))
        self.assertFalse(m.contains(IntObject(7)))

    def testToString(self):
        d = monteDict()
        self.assertEqual(ConstMap(d).toString(), u"[].asMap()")


class TestConstSet(TestCase):

    def testHashEqual(self):
        d = monteDict()
        d[IntObject(42)] = None
        d[CharObject(u'¡')] = None
        a = ConstSet(d)
        b = ConstSet(d)
        self.assertEqual(a.hash(), b.hash())

    def testToStringEmpty(self):
        d = monteDict()
        self.assertEqual(ConstSet(d).toString(), u"[].asSet()")

    def testToString(self):
        d = monteDict()
        d[IntObject(42)] = None
        self.assertEqual(ConstSet(d).toString(), u"[42].asSet()")
