#!/usr/bin/env python

import sys
from typhon.load.nano import InvalidMAST, loadMAST
from typhon.nano.mast import PrettyMAST
from typhon.nano.smallcaps import PrettySmallCaps, doNanoSmallCaps
from typhon.nodes import InvalidAST


def dumpLines(s):
    for line in s.encode("utf-8").split("\n"):
        print line.rstrip()


def entryPoint(argv):
    path = argv[1]
    try:
        expr = loadMAST(path, noisy=False)
    except InvalidAST:
        print "Invalid AST"
        return 1
    except InvalidMAST:
        print "Invalid MAST"
        return 1
    pretty = PrettyMAST()
    pretty.visitExpr(expr)
    dumpLines(pretty.asUnicode())
    expr = doNanoSmallCaps(expr)
    pretty = PrettySmallCaps()
    pretty.visitExpr(expr)
    dumpLines(pretty.asUnicode())
    return 0


def target(driver, *args):
    driver.exe_name = "mt-dump-mast"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
