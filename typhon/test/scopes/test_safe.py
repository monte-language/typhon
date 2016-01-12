# encoding: utf-8

from unittest import TestCase

from typhon.objects.data import BytesObject, IntObject
from typhon.scopes.safe import MakeInt

class TestMakeInt(TestCase):

    def test_fromBytes(self):
        makeInt = MakeInt()
        result = makeInt.call(u"fromBytes", [BytesObject("42")])
        self.assertEqual(result.getInt(), 42)

    def test_fromBytesRadix(self):
        makeInt = MakeInt()
        result = makeInt.call(u"fromBytes", [BytesObject("42"), IntObject(16)])
        self.assertEqual(result.getInt(), 66)
