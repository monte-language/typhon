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

import math
from unittest import TestCase

from rpython.rlib.rbigint import rbigint

from typhon.errors import Ejecting, UserException
from typhon.objects.collections.lists import ConstList, unwrapList
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.ejectors import Ejector


class TestCharObject(TestCase):

    def testAdd(self):
        c = CharObject(u'c')
        result = c.call(u"add", [IntObject(2)])
        self.assertEqual(result._c, u'e')

    def testCategory(self):
        c = CharObject(u'c')
        result = c.call(u"getCategory", [])
        self.assertEqual(result._s, u"Ll")

    def testCategoryUnicode(self):
        c = CharObject(u'č')
        result = c.call(u"getCategory", [])
        self.assertEqual(result._s, u"Ll")

    def testCategorySymbol(self):
        c = CharObject(u'¢')
        result = c.call(u"getCategory", [])
        self.assertEqual(result._s, u"Sc")

    def testMax(self):
        c = CharObject(u'c')
        d = CharObject(u'd')
        result = c.call(u"max", [d])
        self.assertTrue(result is d)

    def testNext(self):
        c = CharObject(u'c')
        result = c.call(u"next", [])
        self.assertEqual(result._c, u'd')

    def testNextUnicode(self):
        c = CharObject(u'¡')
        result = c.call(u"next", [])
        self.assertEqual(result._c, u'¢')

    def testHashEqual(self):
        a = CharObject(u'a')
        b = CharObject(u'a')
        self.assertEqual(a.hash(), b.hash())

    def testHashInequal(self):
        a = CharObject(u'a')
        b = CharObject(u'b')
        self.assertNotEqual(a.hash(), b.hash())

    def testQuoteSlashes(self):
        c = CharObject(u'\\')
        result = c.call(u"quote", [])
        self.assertEqual(result._s, u"'\\\\'")


class TestStr(TestCase):

    def testContainsTrue(self):
        """
        String containment tests have true positives.
        """

        haystack = StrObject(u"needle in a haystack")
        needle = StrObject(u"needle")
        result = haystack.call(u"contains", [needle])
        self.assertTrue(result.isTrue())

    def testGet(self):
        s = StrObject(u"index")
        result = s.call(u"get", [IntObject(2)])
        self.assertEqual(result._c, u'd')

    def testGetNegative(self):
        s = StrObject(u"index")
        self.assertRaises(UserException, s.call, u"get", [IntObject(-1)])

    def testGetOutOfBounds(self):
        s = StrObject(u"index")
        self.assertRaises(UserException, s.call, u"get", [IntObject(6)])

    def testJoin(self):
        s = StrObject(u"|")
        result = s.call(u"join",
                [ConstList([StrObject(u"5"), StrObject(u"42")])])
        self.assertEqual(result._s, u"5|42")

    def testSliceStart(self):
        s = StrObject(u"slice of lemon")
        result = s.call(u"slice", [IntObject(9)])
        self.assertEqual(result._s, u"lemon")

    def testSliceStartStop(self):
        s = StrObject(u"the lime in the coconut")
        result = s.call(u"slice", [IntObject(4), IntObject(8)])
        self.assertEqual(result._s, u"lime")

    def testSliceStartNegative(self):
        s = StrObject(u"nope")
        self.assertRaises(UserException, s.call, u"slice", [IntObject(-2)])

    def testSplit(self):
        """
        Strings can be split.
        """

        s = StrObject(u"first second")
        result = s.call(u"split", [StrObject(u" ")])
        pieces = [obj._s for obj in unwrapList(result)]
        self.assertEqual(pieces, [u"first", u"second"])

    def testToLowerCaseUnicode(self):
        s = StrObject(u"Α And Ω")
        result = s.call(u"toLowerCase", [])
        self.assertEqual(result._s, u"α and ω")

    def testToUpperCase(self):
        s = StrObject(u"lower")
        result = s.call(u"toUpperCase", [])
        self.assertEqual(result._s, u"LOWER")

    def testToUpperCaseUnicode(self):
        s = StrObject(u"¡Holá!")
        result = s.call(u"toUpperCase", [])
        self.assertEqual(result._s, u"¡HOLÁ!")

    def testMakeIterator(self):
        """
        Strings are iterable.
        """

        s = StrObject(u"cs")
        iterator = s.call(u"_makeIterator", [])
        with Ejector() as ej:
            result = iterator.call(u"next", [ej])
            objs = unwrapList(result)
            self.assertEqual(objs[0].getInt(), 0)
            self.assertEqual(objs[1]._c, u'c')
            result = iterator.call(u"next", [ej])
            objs = unwrapList(result)
            self.assertEqual(objs[0].getInt(), 1)
            self.assertEqual(objs[1]._c, u's')
            self.assertRaises(Ejecting, iterator.call, u"next", [ej])

    def testHashEqual(self):
        a = StrObject(u"acidic")
        b = StrObject(u"acidic")
        self.assertEqual(a.hash(), b.hash())

    def testHashInequal(self):
        a = StrObject(u"acerbic")
        b = StrObject(u"bitter")
        self.assertNotEqual(a.hash(), b.hash())

    def testIndexOf(self):
        s = StrObject(u"needle")
        result = s.call(u"indexOf", [StrObject(u"e")])
        self.assertEqual(result.getInt(), 1)

    def testIndexOfFail(self):
        s = StrObject(u"needle")
        result = s.call(u"indexOf", [StrObject(u"z")])
        self.assertEqual(result.getInt(), -1)

    def testLastIndexOf(self):
        s = StrObject(u"needle")
        result = s.call(u"lastIndexOf", [StrObject(u"e")])
        self.assertEqual(result.getInt(), 5)

    def testLastIndexOfFail(self):
        s = StrObject(u"needle")
        result = s.call(u"lastIndexOf", [StrObject(u"x")])
        self.assertEqual(result.getInt(), -1)

    def testTrimEmpty(self):
        s = StrObject(u"")
        result = s.call(u"trim", [])
        self.assertEqual(result._s, u"")

    def testTrimSpaces(self):
        s = StrObject(u"    ")
        result = s.call(u"trim", [])
        self.assertEqual(result._s, u"")

    def testTrimWord(self):
        s = StrObject(u"  testing  ")
        result = s.call(u"trim", [])
        self.assertEqual(result._s, u"testing")



class TestDouble(TestCase):

    def testAdd(self):
        d = DoubleObject(3.2)
        result = d.call(u"add", [DoubleObject(1.1)])
        self.assertAlmostEqual(result.getDouble(), 4.3)

    def testAddInt(self):
        d = DoubleObject(3.2)
        result = d.call(u"add", [IntObject(1)])
        self.assertAlmostEqual(result.getDouble(), 4.2)

    def testSin(self):
        d = DoubleObject(math.pi / 2.0)
        result = d.call(u"sin", [])
        self.assertAlmostEqual(result.getDouble(), 1.0)

    def testSubtract(self):
        d = DoubleObject(5.5)
        result = d.call(u"subtract", [DoubleObject(1.3)])
        self.assertAlmostEqual(result.getDouble(), 4.2)

    def testHashEqual(self):
        a = DoubleObject(42.0)
        b = DoubleObject(42.0)
        self.assertEqual(a.hash(), b.hash())

    def testHashInequal(self):
        a = DoubleObject(42.0)
        b = DoubleObject(5.0)
        self.assertNotEqual(a.hash(), b.hash())

    def testCmpNaN(self):
        a = DoubleObject(float("nan"))
        comparison = a.call(u"op__cmp", [a])
        self.assertFalse(comparison.call(u"aboveZero", []).isTrue())
        self.assertFalse(comparison.call(u"belowZero", []).isTrue())
        self.assertFalse(comparison.call(u"isZero", []).isTrue())


class TestInt(TestCase):

    def testAdd(self):
        i = IntObject(32)
        result = i.call(u"add", [IntObject(11)])
        self.assertEqual(result.getInt(), 43)

    def testAddDouble(self):
        i = IntObject(32)
        result = i.call(u"add", [DoubleObject(1.1)])
        self.assertAlmostEqual(result.getDouble(), 33.1)

    def testApproxDivide(self):
        i = IntObject(4)
        result = i.call(u"approxDivide", [IntObject(2)])
        self.assertAlmostEqual(result.getDouble(), 2.0)

    def testComplement(self):
        i = IntObject(5)
        result = i.call(u"complement", [])
        self.assertEqual(result.getInt(), -6)

    def testMax(self):
        i = IntObject(3)
        result = i.call(u"max", [IntObject(5)])
        self.assertEqual(result.getInt(), 5)

    def testMin(self):
        i = IntObject(3)
        result = i.call(u"min", [IntObject(5)])
        self.assertEqual(result.getInt(), 3)

    def testMulDouble(self):
        """
        Ints are promoted by doubles during multiplication.
        """

        i = IntObject(4)
        result = i.call(u"multiply", [DoubleObject(2.1)])
        self.assertTrue(isinstance(result, DoubleObject))
        self.assertEqual(result.getDouble(), 8.4)

    def testOpCmpDouble(self):
        i = IntObject(2)
        result = i.call(u"op__cmp", [DoubleObject(2.0)])
        self.assertEqual(result.getInt(), 0)

    def testOpCmpBigInt(self):
        i = IntObject(2)
        bi = BigInt(rbigint.fromint(6))
        result = i.call(u"op__cmp", [bi])
        self.assertEqual(result.getInt(), -1)

    def testOr(self):
        i = IntObject(0x3)
        result = i.call(u"or", [IntObject(0x5)])
        self.assertEqual(result.getInt(), 0x7)

    def testPowSmall(self):
        i = IntObject(5)
        result = i.call(u"pow", [IntObject(7)])
        self.assertEqual(result.getInt(), 78125)

    def testPow(self):
        i = IntObject(3)
        result = i.call(u"pow", [IntObject(100)])
        self.assertTrue(result.bi.eq(rbigint.fromint(3).pow(rbigint.fromint(100))))

    def testModPow(self):
        i = IntObject(3)
        result = i.call(u"modPow", [IntObject(1000000), IntObject(255)])
        self.assertEqual(result.getInt(), 171)

    def testShiftLeft(self):
        i = IntObject(0xf0)
        result = i.call(u"shiftLeft", [IntObject(5)])
        self.assertEqual(result.getInt(), 0x1e00)

    def testShiftLeftLarge(self):
        i = IntObject(0x5c5c)
        result = i.call(u"shiftLeft", [IntObject(64)])
        bi = rbigint.fromint(0x5c5c).lshift(64)
        self.assertTrue(result.bi.eq(bi))

    def testShiftLeftFar(self):
        i = IntObject(0x1)
        result = i.call(u"shiftLeft", [IntObject(65)])
        bi = rbigint.fromint(0x1).lshift(65)
        self.assertTrue(result.bi.eq(bi))

    def testShiftRight(self):
        i = IntObject(0xf0)
        result = i.call(u"shiftRight", [IntObject(5)])
        self.assertEqual(result.getInt(), 0x7)

    def testShiftRightLarge(self):
        i = IntObject(0x7fffffffffffffff)
        result = i.call(u"shiftRight", [IntObject(64)])
        self.assertEqual(result.getInt(), 0x0)

    def testSubtract(self):
        i = IntObject(5)
        result = i.call(u"subtract", [IntObject(15)])
        self.assertAlmostEqual(result.getInt(), -10)

    def testSubtractDouble(self):
        i = IntObject(5)
        result = i.call(u"subtract", [DoubleObject(1.5)])
        self.assertAlmostEqual(result.getDouble(), 3.5)

    def testHashEqual(self):
        a = DoubleObject(42)
        b = DoubleObject(42)
        self.assertEqual(a.hash(), b.hash())

    def testHashInequal(self):
        a = DoubleObject(42)
        b = DoubleObject(5)
        self.assertNotEqual(a.hash(), b.hash())

    def testBitLength(self):
        i = IntObject(42)
        result = i.call(u"bitLength", [])
        self.assertEqual(result.getInt(), 6)


class TestBigInt(TestCase):

    def testShiftLeft(self):
        bi = BigInt(rbigint.fromint(42))
        result = bi.call(u"shiftLeft", [IntObject(2)])
        self.assertTrue(result.bi.int_eq(168))

    def testShiftRight(self):
        bi = BigInt(rbigint.fromint(42))
        result = bi.call(u"shiftRight", [IntObject(2)])
        self.assertTrue(result.bi.int_eq(10))

    def testXorInt(self):
        bi = BigInt(rbigint.fromint(0xcccc))
        result = bi.call(u"xor", [IntObject(0xaaaa)])
        self.assertTrue(result.bi.int_eq(0x6666))

    def testBitLength(self):
        bi = BigInt(rbigint.fromint(42))
        result = bi.call(u"bitLength", [])
        self.assertEqual(result.getInt(), 6)

    def testAndInt(self):
        bi = BigInt(rbigint.fromint(0x3fffffffffffffff).int_mul(3))
        result = bi.call(u"and", [IntObject(0xffff)])
        self.assertTrue(result.bi.int_eq(0xfffd))

    def testComplement(self):
        bi = BigInt(rbigint.fromint(6))
        result = bi.call(u"complement", [])
        self.assertTrue(result.bi.int_eq(-7))

    def testOpCmpInt(self):
        bi = BigInt(rbigint.fromint(6))
        i = IntObject(2)
        result = bi.call(u"op__cmp", [i])
        self.assertEqual(result.getInt(), 1)
