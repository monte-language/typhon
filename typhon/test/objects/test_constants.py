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

from typhon.errors import Refused
from typhon.objects.constants import FalseObject, NullObject, TrueObject
from typhon.objects.root import Object


class TestNullObject(TestCase):

    def testNullRefusal(self):
        self.assertRaises(Refused, NullObject.recv, u"test", [])


class TestBoolObject(TestCase):

    def testAnd(self):
        result = FalseObject.recv(u"and", [TrueObject])
        self.assertEqual(result, FalseObject)

    def testOr(self):
        result = FalseObject.recv(u"or", [TrueObject])
        self.assertEqual(result, TrueObject)

    def testNot(self):
        result = FalseObject.recv(u"not", [])
        self.assertEqual(result, TrueObject)

    def testPick(self):
        first = Object()
        second = Object()

        result = TrueObject.recv(u"pick", [first, second])
        self.assertTrue(result is first)

        result = FalseObject.recv(u"pick", [first, second])
        self.assertTrue(result is second)

    def testXor(self):
        result = FalseObject.recv(u"xor", [TrueObject])
        self.assertEqual(result, TrueObject)
