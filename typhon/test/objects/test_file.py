from unittest import TestCase

from typhon.objects.files import FileResource

class TestFileResource(TestCase):

    def testSibling(self):
        fr = FileResource(["foo", "bar"])
        sibling = fr.sibling("baz")
        self.assertEqual(sibling.segments, ["foo", "baz"])

    def testTemporarySibling(self):
        # XXX cannot be run in Nix harness for some reason
        return
        fr = FileResource(["foo", "bar"])
        first = fr.temporarySibling(".test")
        second = fr.temporarySibling(".test")
        self.assertTrue(first.segments[-1].endswith(".test"))
        self.assertTrue(second.segments[-1].endswith(".test"))
        self.assertNotEqual(first.segments[-1], second.segments[-1])
