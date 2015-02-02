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

from typhon.objects.data import CharObject, IntObject
from typhon.objects.lists import (ConstList, EmptyListStrategy,
                                  IntListStrategy, makeList)


class TestConstList(TestCase):

    def testHashEqual(self):
        a = makeList([IntObject(42), CharObject(u'é')])
        b = makeList([IntObject(42), CharObject(u'é')])
        self.assertEqual(a.hash(), b.hash())

    def testHashInequalLength(self):
        a = makeList([IntObject(42), CharObject(u'é')])
        b = makeList([IntObject(42)])
        self.assertNotEqual(a.hash(), b.hash())

    def testHashInequalItems(self):
        a = makeList([IntObject(42), CharObject(u'é')])
        b = makeList([IntObject(42), CharObject(u'e')])
        self.assertNotEqual(a.hash(), b.hash())

    def testReverse(self):
        a = makeList([IntObject(42), CharObject(u'é')])
        b = a.reverse()
        self.assertEqual(b.get(1).getInt(), 42)


class TestConstListStrategy(TestCase):

    def testEmpty(self):
        a = ConstList.withoutStrategy([])
        self.assertEqual(a.strategy, EmptyListStrategy)

    def testInt(self):
        a = ConstList.withoutStrategy([IntObject(42), IntObject(5)])
        self.assertEqual(a.strategy, IntListStrategy)
