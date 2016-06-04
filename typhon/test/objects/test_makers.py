# encoding: utf-8

from unittest import TestCase

from rpython.rlib.rbigint import rbigint

from typhon.objects.data import BytesObject, IntObject, StrObject
from typhon.objects.makers import theMakeInt

class TestMakeInt(TestCase):

    def testFromBigStr(self):
        s = StrObject(u"1180591620717411303424")
        bi = rbigint.fromint(128).pow(rbigint.fromint(10))
        result = theMakeInt.call(u"run", [s])
        self.assertEqual(result.bi, bi)

    def testFromBigBytes(self):
        bs = BytesObject("1180591620717411303424")
        bi = rbigint.fromint(128).pow(rbigint.fromint(10))
        result = theMakeInt.call(u"fromBytes", [bs])
        self.assertEqual(result.bi, bi)

    def test_fromBytes(self):
        result = theMakeInt.call(u"fromBytes", [BytesObject("42")])
        self.assertEqual(result.bi, rbigint.fromint(42))

    def test_fromBytesRadix(self):
        withRadix = theMakeInt.call(u"withRadix", [IntObject(16)])
        result = withRadix.call(u"fromBytes", [BytesObject("42")])
        self.assertEqual(result.bi, rbigint.fromint(66))

    def testWithUnderscores(self):
        s = StrObject(u"100_000")
        result = theMakeInt.call(u"run", [s])
        bi = rbigint.fromint(100000)
        self.assertEqual(result.bi, bi)
