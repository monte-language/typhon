from unittest import TestCase

from typhon.vats import Vat, VatCheckpointed

class TestVat(TestCase):

    def testCheckpointImmortal(self):
        # -1 for immortal.
        v = Vat(None, None, name=u"test", checkpoints=-1)
        v.checkpoint()
        # Should still be immortal.
        self.assertTrue(v.checkpoints < 0)

    def testCheckpointSingle(self):
        v = Vat(None, None, name=u"test", checkpoints=10)
        v.checkpoint()
        # Should have 9 left.
        self.assertEqual(v.checkpoints, 9)

    def testCheckpointBatch(self):
        v = Vat(None, None, name=u"test", checkpoints=10)
        v.checkpoint(points=2)
        # Should have 8 left.
        self.assertEqual(v.checkpoints, 8)

    def testCheckpointSingleExhausted(self):
        # The Vat constructor, sensibly, requires at least one point to be
        # invested in our vat, so we must deduct twice to trigger the
        # exception.
        v = Vat(None, None, name=u"test", checkpoints=1)
        v.checkpoint()
        self.assertRaises(VatCheckpointed, v.checkpoint)

    def testCheckpointBatchExhausted(self):
        v = Vat(None, None, name=u"test", checkpoints=2)
        # 2 isn't enough for a deduction of 3.
        self.assertRaises(VatCheckpointed, v.checkpoint, points=3)
