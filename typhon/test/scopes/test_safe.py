# encoding: utf-8

from unittest import TestCase

from rpython.rlib.rbigint import rbigint

from typhon.objects.data import BytesObject, IntObject, StrObject
from typhon.scopes.safe import MakeInt

class TestMakeInt(TestCase):

    def testFromBigStr(self):
        makeInt = MakeInt()
        s = StrObject(u"1180591620717411303424")
        bi = rbigint.fromint(128).pow(rbigint.fromint(10))
        result = makeInt.call(u"run", [s])
        self.assertEqual(result.bi, bi)

    def testFromBigBytes(self):
        makeInt = MakeInt()
        bs = BytesObject("1180591620717411303424")
        bi = rbigint.fromint(128).pow(rbigint.fromint(10))
        result = makeInt.call(u"fromBytes", [bs])
        self.assertEqual(result.bi, bi)

    def test_fromBytes(self):
        makeInt = MakeInt()
        result = makeInt.call(u"fromBytes", [BytesObject("42")])
        self.assertEqual(result.bi, rbigint.fromint(42))

    def test_fromBytesRadix(self):
        makeInt = MakeInt()
        result = makeInt.call(u"fromBytes", [BytesObject("42"), IntObject(16)])
        self.assertEqual(result.bi, rbigint.fromint(66))

    def testWithUnderscores(self):
        makeInt = MakeInt()
        s = StrObject(u"100_000")
        result = makeInt.call(u"run", [s])
        bi = rbigint.fromint(100000)
        self.assertEqual(result.bi, bi)
