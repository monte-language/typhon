import ast
from unittest import TestCase
from macropy.core import unparse
from typhon.macros import buildOperationsTable, opsToCallbacks

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
                ["resolve(r, BytesObject(contents))", None, None, None, None],
                ["ruv.magic_fsClose(vat, f)", -1, None, None, None],
                ["smash(r, StrObject((u'libuv error: %s' % err)))",
                 None, None, None, None],
                ["ruv.magic_fsClose(vat, f)", -1, None, None, None],
                ["readLoop(f, buf)", -3, -1, "contents", "err"],
                ['smash(r, StrObject((u"Couldn\'t open file fount: %s" % err)))',
                 None, None, None, None],
                ['ruv.magic_fsOpen(vat, path, os.O_RDONLY, 0)', -2, -1, "f",
                "err"],
                ['0', -1, None, 'f', None]
            ])

        input = ast.parse(sampleAst2).body
        output = buildOperationsTable(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["ioC()", None, None, None, None],
                ["ioB()", -1, None, None, None],
                ["ioA()", -1, None, None, None],
                ["io9()", -2, None, None, None],
                ["io8()", -2, -1, None, "err3"],
                ["io7()", -1, -2, None, "err3"],
                ["io6()", -1, None, None, None],
                ["io5()", -7, None, None, None],
                ["io4()", -8, -1, None, "err2"],
                ["io3()", -1, None, None, None],
                ["io2()", -4, -1, "y", "err1"],
                ["io1()", -1, -2, "x", "err1"],
                ["1", -1, None, "x", None]
            ])

        input = ast.parse(sampleAst3).body
        output = buildOperationsTable(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["io6()", None, None, None, None],
                ["io5()", -1, None, None, None],
                ["io4()", -2, -1, None, "err2"],
                ["io3()", -3, -2, None, "err2"],
                ["io2()", -2, -1, "y", "err1"],
                ["io1()", -1, -2, "x", "err1"],
                ["io0()", -1, -5, None, "err2"]
            ])

    def testOpsToCallbacks(self
    ):
        """
        Op lists are converted to callback lists properly.
        """
        def flattenOps(ops):
            return  [[unparse(line[0]).strip(), line[1],
                      line[2] and unparse(line[2]).strip(),
                      line[3], line[4], line[5] and unparse(line[5]).strip(),
                      line[6]] for line in ops]
        input = ast.parse(sampleAst1).body
        initialState, output = opsToCallbacks(buildOperationsTable(input))
        self.assertEqual(initialState.keys(), ['f'])
        self.assertEqual([unparse(v) for v in initialState.values()], ['0'])
        self.assertEqual(
            flattenOps(output),
            [
                ['ruv.magic_fsOpen.callbackType', "f", "readLoop(f, buf)", 1, "err", 'smash(r, StrObject((u"Couldn\'t open file fount: %s" % err)))', None],
                ['readLoop.callbackType', "contents", "ruv.magic_fsClose(vat, f)", 3, "err", "ruv.magic_fsClose(vat, f)", 2],
                ['ruv.magic_fsClose.callbackType', None, "smash(r, StrObject((u'libuv error: %s' % err)))", None, None, None, None],
                ['ruv.magic_fsClose.callbackType', None, "resolve(r, BytesObject(contents))", None, None, None, None]
                ])

        input = ast.parse(sampleAst2).body
        initialState, output = opsToCallbacks(buildOperationsTable(input))
        self.assertEqual(initialState.keys(), ['x'])
        self.assertEqual([unparse(v) for v in initialState.values()], ['1'])
        self.assertEqual(
            flattenOps(output),
            [
                ['io1.callbackType', 'x', 'io2()', 1, 'err1', 'io3()', 2],
                ['io2.callbackType', 'y', 'io6()', 5, 'err1', 'io3()', 2],
                ['io3.callbackType', None, 'io4()', 3, None, None, None],
                ['io4.callbackType', None, 'ioC()', None, 'err2', 'io5()', 4],
                ['io5.callbackType', None, 'ioC()', None, None, None, None],
                ['io6.callbackType', None, 'io7()', 6, None, None, None],
                ['io7.callbackType', None, 'io8()', 7, 'err3', 'io9()', 8],
                ['io8.callbackType', None, 'ioA()', 9, 'err3', 'io9()', 8],
                ['io9.callbackType', None, 'ioB()', 10, None, None, None],
                ['ioA.callbackType', None, 'ioB()', 10, None, None, None],
                ['ioB.callbackType', None, 'ioC()', None, None, None, None]
            ])

        input = ast.parse(sampleAst3).body
        initialState, output = opsToCallbacks(buildOperationsTable(input))
        self.assertEqual(initialState, {})
        self.assertEqual(
            flattenOps(output),
            [
                ['io0.callbackType', None, 'io1()', 1, 'err2', 'io5()', 5],
                ['io1.callbackType', 'x', 'io2()', 2, 'err1', 'io3()', 3],
                ['io2.callbackType', 'y', 'io4()', 4, 'err1', 'io3()', 3],
                ['io3.callbackType', None, 'io6()', None, 'err2', 'io5()', 5],
                ['io4.callbackType', None, 'io6()', None, 'err2', 'io5()', 5],
                ['io5.callbackType', None, 'io6()', None, None, None, None],
            ])
