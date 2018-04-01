import ast
from unittest import TestCase
from macropy.core import unparse
from typhon.macros import buildOperationsTable

sampleAst1 = """
f = 0
try:
    f = ruv.magic_fsOpen(vat, path, os.O_RDONLY, 0000)
except object as err:
    smash(r, StrObject(u"Couldn't open file fount: %s" % err))
else:
    try:
        contents = readLoop(f, buf)
    except object as err:
        ruv.magic_fsClose(vat, f)
        smash(r, StrObject(u"libuv error: %s" % err))
    else:
        ruv.magic_fsClose(vat, f)
        resolve(r, BytesObject(contents))
"""

sampleAst2 = """
x = 1
try:
    x = io1()
    y = io2()
except object as err1:
    io3()
    try:
        io4()
    except object as err2:
        io5()
else:
    io6()
    try:
        io7()
        io8()
    except object as err3:
        io9()
    else:
        ioA()
    ioB()
ioC()
"""

sampleAst3 = """
try:
    io0()
    try:
        x = io1()
        y = io2()
    except object as err1:
        io3()
    else:
        io4()
except object as err2:
    io5()
io6()
"""


class TestIOBlock(TestCase):

    def testBuildOpsList(self):
        """
        Proper jump tables get built for multiple try/except blocks.
        """
        input = ast.parse(sampleAst1).body
        output = buildOperationsTable(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["0",
                 1, None, "f", None],
                ["ruv.magic_fsOpen(vat, path, os.O_RDONLY, 0)",
                 3, 2, "f", "err"],
                ['smash(r, StrObject((u"Couldn\'t open file fount: %s" % err)))',
                 None, None, None, None],
                ["readLoop(f, buf)",
                 6, 4, "contents", "err"],
                ["ruv.magic_fsClose(vat, f)",
                 5, None, None, None],
                ["smash(r, StrObject((u'libuv error: %s' % err)))",
                 None, None, None, None],
                ["ruv.magic_fsClose(vat, f)",
                 7, None, None, None],
                ["resolve(r, BytesObject(contents))",
                 None, None, None, None]
            ])

        input = ast.parse(sampleAst2).body
        output = buildOperationsTable(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["1",
                 1, None, "x", None],
                ["io1()",
                 2, 3, "x", "err1"],
                ["io2()",
                 6, 3, "y", "err1"],
                ["io3()",
                 4, None, None, None],
                ["io4()",
                 12, 5, None, "err2"],
                ["io5()",
                 12, None, None, None],
                ["io6()",
                 7, None, None, None],
                ["io7()",
                 8, 9, None, "err3"],
                ["io8()",
                 10, 9, None, "err3"],
                ["io9()",
                 11, None, None, None],
                ["ioA()",
                 11, None, None, None],
                ["ioB()",
                 12, None, None, None],
                ["ioC()",
                 None, None, None, None]
            ])

        input = ast.parse(sampleAst3).body
        output = buildOperationsTable(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["io0()",
                 1, 5, None, "err2"],
                ["io1()",
                 2, 3, "x", "err1"],
                ["io2()",
                 4, 3, "y", "err1"],
                ["io3()",
                 6, 5, None, "err2"],
                ["io4()",
                 6, 5, None, "err2"],
                ["io5()",
                 6, None, None, None],
                ["io6()",
                 None, None, None, None]])
