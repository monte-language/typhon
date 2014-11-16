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

from typhon.errors import Ejecting
from typhon.objects import IntObject
from typhon.objects.data import CharObject, StrObject
from typhon.objects.ejectors import Ejector


class TestCharObject(TestCase):

    def testAdd(self):
        c = CharObject(u'c')
        result = c.recv(u"add", [IntObject(2)])
        self.assertEqual(result._c, u'e')

    def testCategory(self):
        c = CharObject(u'c')
        result = c.recv(u"getCategory", [])
        self.assertEqual(result._s, u"Ll")

    def testCategoryUnicode(self):
        c = CharObject(u'č')
        result = c.recv(u"getCategory", [])
        self.assertEqual(result._s, u"Ll")

    def testCategorySymbol(self):
        c = CharObject(u'¢')
        result = c.recv(u"getCategory", [])
        self.assertEqual(result._s, u"Sc")

    def testMax(self):
        c = CharObject(u'c')
        d = CharObject(u'd')
        result = c.recv(u"max", [d])
        self.assertTrue(result is d)

    def testNext(self):
        c = CharObject(u'c')
        result = c.recv(u"next", [])
        self.assertEqual(result._c, u'd')

    def testNextUnicode(self):
        c = CharObject(u'¡')
        result = c.recv(u"next", [])
        self.assertEqual(result._c, u'¢')


class TestStr(TestCase):

    def testContainsTrue(self):
        """
        String containment tests have true positives.
        """

        haystack = StrObject(u"needle in a haystack")
        needle = StrObject(u"needle")
        result = haystack.recv(u"contains", [needle])
        self.assertTrue(result.isTrue())

    def testSplit(self):
        """
        Strings can be split.
        """

        s = StrObject(u"first second")
        result = s.recv(u"split", [StrObject(u" ")])
        pieces = [obj._s for obj in result.objects]
        self.assertEqual(pieces, [u"first", u"second"])

    def testToLowerCaseUnicode(self):
        s = StrObject(u"Α And Ω")
        result = s.recv(u"toLowerCase", [])
        self.assertEqual(result._s, u"α and ω")

    def testToUpperCase(self):
        s = StrObject(u"lower")
        result = s.recv(u"toUpperCase", [])
        self.assertEqual(result._s, u"LOWER")

    def testToUpperCaseUnicode(self):
        s = StrObject(u"¡Holá!")
        result = s.recv(u"toUpperCase", [])
        self.assertEqual(result._s, u"¡HOLÁ!")

    def testMakeIterator(self):
        """
        Strings are iterable.
        """

        s = StrObject(u"cs")
        iterator = s.recv(u"_makeIterator", [])
        with Ejector() as ej:
            result = iterator.recv(u"next", [ej])
            objs = result.objects
            self.assertEqual(objs[0].getInt(), 0)
            self.assertEqual(objs[1]._c, u'c')
            result = iterator.recv(u"next", [ej])
            objs = result.objects
            self.assertEqual(objs[0].getInt(), 1)
            self.assertEqual(objs[1]._c, u's')
            self.assertRaises(Ejecting, iterator.recv, u"next", [ej])
