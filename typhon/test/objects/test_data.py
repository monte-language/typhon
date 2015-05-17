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

from typhon.errors import Ejecting, UserException, WrongType
from typhon.objects.collections import ConstList
from typhon.objects.constants import BoolObject
from typhon.objects.data import (
    BigInt, CharObject, DoubleObject, IntObject, StrObject, LocatedTwine,
    CompositeTwine)
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


class _TwineTests(object):
    """
    Holds abstract tests for various Twine types.

    Because Twine is an abstract class this doesn't run anything itself. There
    should be a base case that implements ``makeTwine`` appropriately and
    subclasses TestCase, to run these tests for a specific subclass of Twine.
    """

    def makeTwine(self, s, id):
        """Makes an instance of the class under test.

        The ``id`` param can be used to create unique internal structure,
        such as locations in the case of LocatedTwine. If not internal
        structure needs to be created, ignore the ``id`` param.

        Every call of ``makeTwine`` in a test will use a unique value for
        ``id``.
        """
        raise NotImplementedError

    def test_endsWith(self):
        haystack = self.makeTwine(u"foo bar", 1)

        needle1 = self.makeTwine(u"bar", 2)
        self.assertTrue(haystack.call(u"endsWith", [needle1]))
        needle2 = self.makeTwine(u"baz", 3)
        self.assertFalse(haystack.call(u"endsWith", [needle2]))

    def test_startsWith(self):
        haystack = self.makeTwine(u"foo bar", 1)

        needle1 = self.makeTwine(u"foo", 2)
        self.assertTrue(haystack.call(u"startsWith", [needle1]))
        needle2 = self.makeTwine(u"foz", 3)
        self.assertFalse(haystack.call(u"startsWith", [needle2]))

    def test_add(self):
        t1 = self.makeTwine(u"foo ", 1)
        t2 = self.makeTwine(u"bar", 2)

        res = t1.call(u"add", [t2])
        self.assertEqual(res.getString(), u"foo bar")
        self.assertEqual(res.slice(0, 4).getSpan(), t1.getSpan())
        self.assertEqual(res.slice(4, 7).getSpan(), t2.getSpan())

    def test_join(self):
        joiner = self.makeTwine(", ", 1)
        t1 = self.makeTwine("foo", 2)
        t2 = self.makeTwine("bar", 3)
        t3 = self.makeTwine("qux", 3)

        res = joiner.call("join", [ConstList([t1, t2, t3])])
        self.assertEqual(res.getString(), u"foo, bar, qux")
        self.assertEqual(res.slice(0, 3).getSpan(), t1.getSpan())
        self.assertEqual(res.slice(5, 8).getSpan(), t2.getSpan())
        self.assertEqual(res.slice(10, 13).getSpan(), t3.getSpan())

    def test_asFrom_singleLine(self):
        t1 = self.makeTwine(u"foo", 1)

        res = t1.call('asFrom', [StrObject(u"file:///serious_business.mt"), IntObject(2), IntObject(4)])
        self.assertEqual(res.getString(), u"foo")

        span = res.getSpan()
        self.assertTrue(span.isOneToOne())
        self.assertEqual(span.getStartLine(), 2)
        self.assertEqual(span.getEndLine(), 2)
        self.assertEqual(span.getStartCol(), 4)
        self.assertEqual(span.getEndCol(), 6)

    def test_asFrom_multiLine(self):
        t1 = self.makeTwine(u"foo bar\nbaz qux", 1)

        res = t1.call('asFrom', [StrObject(u"file:///ircbot/parser.mt"), IntObject(2), IntObject(4)])
        self.assertEqual(res.getString(), u"foo bar\nbaz qux")

        span = res.getSpan()
        self.assertTrue(span.isOneToOne())
        self.assertEqual(span.getStartLine(), 2)
        self.assertEqual(span.getEndLine(), 3)
        self.assertEqual(span.getStartCol(), 4)
        self.assertEqual(span.getEndCol(), 6)

        self.assertEqual(len(res.getParts()), 2)
        part1, part2 = res.getParts()

        self.assertEqual(part1.getString(), u"foo bar\n")
        span1 = part1.getSpan()
        self.assertTrue(span1.isOneToOne())
        self.assertEqual(span1.getStartLine(), 2)
        self.assertEqual(span1.getEndLine(), 2)
        self.assertEqual(span1.getStartCol(), 4)
        self.assertEqual(span1.getEndCol(), 11)

        self.assertEqual(part2.getString(), u"baz qux")
        span2 = part2.getSpan()
        self.assertTrue(span2.isOneToOne())
        self.assertEqual(span2.getStartLine(), 3)
        self.assertEqual(span2.getEndLine(), 3)
        self.assertEqual(span2.getStartCol(), 0)
        self.assertEqual(span2.getEndCol(), 6)

    def test_infect_oneToOne(self):
        t1 = self.makeTwine(u"foo", 1)
        t2 = self.makeTwine(u"bar", 2)

        res = t1.call('infect', [t2, BoolObject(True)])
        self.assertEqual(res.getString(), u"bar")
        self.assertEqual(res.getSpan(), t1.getSpan())

    def test_infect_notOneToOne(self):
        t1 = self.makeTwine(u"foo", 1)
        t2 = self.makeTwine(u"frob", 2)

        res = t1.call('infect', [t2, BoolObject(False)])
        self.assertEqual(res.getString(), u"frob")
        self.assertEqual(res.getSpan(), t1.getSpan())

    def test_infect_badCalls(self):
        t1 = self.makeTwine(u"foo", 1)
        # Bad type
        self.assertRaises(WrongType, t1.call, u"infect", [0, BoolObject(True)])
        # asked for oneToOne without having the same length.
        self.assertRaises(UserException, t1.call, u"infect", [StrObject(u"xy"), BoolObject(True)])


class TestTwineStr(_TwineTests, TestCase):

    def makeTwine(self, s, _):
        return StrObject(s)


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
        pieces = [obj._s for obj in result.objects]
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
            objs = result.objects
            self.assertEqual(objs[0].getInt(), 0)
            self.assertEqual(objs[1]._c, u'c')
            result = iterator.call(u"next", [ej])
            objs = result.objects
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
