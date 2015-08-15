from StringIO import StringIO
from unittest import TestCase

from typhon.load.mast import loadMASTHandle
from typhon.nodes import Def

class testLoadMAST(TestCase):

    def testSimpleDef(self):
        data = (
            "Mont\xe0MAST\x00" # magic
            "LN"               # null
            "N\x03Int"         # Int
            "PF\x01x\x01"      # x :Int
            "LI\x54"           # 42
            "D\x00\x00\x02"    # def x :Int := 42
        )
        expr = loadMASTHandle(StringIO(data))
        self.assertTrue(isinstance(expr, Def))
