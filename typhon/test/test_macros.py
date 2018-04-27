import ast
from unittest import TestCase
from macropy.core import unparse
from typhon.macros import buildOperationsDAG, opsToCallbacks

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
        output = buildOperationsDAG(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["resolve(r, BytesObject(contents))", None, None, None, None],
                ["ruv.magic_fsClose(vat, f)", output[0], None, None, None],
                ["smash(r, StrObject((u'libuv error: %s' % err)))",
                 None, None, None, None],
                ["ruv.magic_fsClose(vat, f)", output[2], None, None, None],
                ["readLoop(f, buf)", output[1], output[3], "contents", "err"],
                ['smash(r, StrObject((u"Couldn\'t open file fount: %s" % err)))',
                 None, None, None, None],
                ['ruv.magic_fsOpen(vat, path, os.O_RDONLY, 0)', output[4],
                 output[5], "f", "err"],
                ['0', output[6], None, 'f', None]
            ])

        input = ast.parse(sampleAst2).body
        output = buildOperationsDAG(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["ioC()", None, None, None, None],
                ["ioB()", output[0], None, None, None],
                ["ioA()", output[1], None, None, None],
                ["io9()", output[1], None, None, None],
                ["io8()", output[2], output[3], None, "err3"],
                ["io7()", output[4], output[3], None, "err3"],
                ["io6()", output[5], None, None, None],
                ["io5()", output[0], None, None, None],
                ["io4()", output[0], output[7], None, "err2"],
                ["io3()", output[8], None, None, None],
                ["io2()", output[6], output[9], "y", "err1"],
                ["io1()", output[10], output[9], "x", "err1"],
                ["1", output[11], None, "x", None]
            ])

        input = ast.parse(sampleAst3).body
        output = buildOperationsDAG(input)
        self.assertEqual(
            [[unparse(line[0]).strip()] + list(line[1:]) for line in output],
            [
                ["io6()", None, None, None, None],
                ["io5()", output[0], None, None, None],
                ["io4()", output[0], output[1], None, "err2"],
                ["io3()", output[0], output[1], None, "err2"],
                ["io2()", output[2], output[3], "y", "err1"],
                ["io1()", output[4], output[3], "x", "err1"],
                ["io0()", output[5], output[1], None, "err2"]
            ])

    def testOpsToCallbacks(self):
        """
        Op lists are converted to callback lists properly.
        """
        def flattenOps(ops):
            return [[unparse(line.base).strip(), line.successName,
                     line.successExpr and unparse(line.successExpr).strip(),
                     line.successCB, line.failName,
                     line.failExpr and unparse(line.failExpr).strip(),
                     line.failCB] for line in ops]
        input = ast.parse(sampleAst1).body
        initialState, output = opsToCallbacks(buildOperationsDAG(input))
        self.assertEqual(initialState.keys(), ['f'])
        self.assertEqual([unparse(v) for v in initialState.values()], ['0'])
        self.assertEqual(
            flattenOps(output),
            [['ruv.magic_fsOpen.callbackType', "f", "readLoop(f, buf)",
              output[1], "err",
              'smash(r, StrObject((u"Couldn\'t open file fount: %s" % err)))',
              None],
             ['readLoop.callbackType', "contents", "ruv.magic_fsClose(vat, f)",
              output[3], "err", "ruv.magic_fsClose(vat, f)", output[2]],
             ['ruv.magic_fsClose.callbackType', None,
              "smash(r, StrObject((u'libuv error: %s' % err)))", None, None,
              None, None],
             ['ruv.magic_fsClose.callbackType', None,
              "resolve(r, BytesObject(contents))", None, None, None, None]])

        input = ast.parse(sampleAst2).body
        initialState, output = opsToCallbacks(buildOperationsDAG(input))
        self.assertEqual(initialState.keys(), ['x'])
        self.assertEqual([unparse(v) for v in initialState.values()], ['1'])
        self.assertEqual(
            flattenOps(output),
            [['io1.callbackType', 'x', 'io2()', output[1], 'err1', 'io3()',
              output[2]],
             ['io2.callbackType', 'y', 'io6()', output[5], 'err1', 'io3()',
              output[2]],
             ['io3.callbackType', None, 'io4()', output[3], None, None,
              None],
             ['io4.callbackType', None, 'ioC()', None, 'err2', 'io5()',
              output[4]],
             ['io5.callbackType', None, 'ioC()', None, None, None, None],
             ['io6.callbackType', None, 'io7()', output[6], None, None,
              None],
             ['io7.callbackType', None, 'io8()', output[7], 'err3', 'io9()',
              output[8]],
             ['io8.callbackType', None, 'ioA()', output[9], 'err3', 'io9()',
              output[8]],
             ['io9.callbackType', None, 'ioB()', output[10], None, None,
              None],
             ['ioA.callbackType', None, 'ioB()', output[10], None, None,
              None],
             ['ioB.callbackType', None, 'ioC()', None, None, None, None]])

        input = ast.parse(sampleAst3).body
        initialState, output = opsToCallbacks(buildOperationsDAG(input))
        self.assertEqual(initialState, {})
        self.assertEqual(
            flattenOps(output),
            [['io0.callbackType', None, 'io1()', output[1], 'err2', 'io5()',
              output[5]],
             ['io1.callbackType', 'x', 'io2()', output[2], 'err1', 'io3()',
              output[3]],
             ['io2.callbackType', 'y', 'io4()', output[4], 'err1', 'io3()',
              output[3]],
             ['io3.callbackType', None, 'io6()', None, 'err2', 'io5()',
              output[5]],
             ['io4.callbackType', None, 'io6()', None, 'err2', 'io5()',
              output[5]],
             ['io5.callbackType', None, 'io6()', None, None, None, None]])
