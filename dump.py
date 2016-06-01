#!/usr/bin/env python

import sys
from typhon.load.nano import InvalidMAST, loadMAST
from typhon.nano.mast import PrettyMAST
from typhon.nodes import InvalidAST


def entryPoint(argv):
    path = argv[1]
    try:
        term = loadMAST(path, noisy=False)
    except InvalidAST:
        print "Invalid AST"
        return 1
    except InvalidMAST:
        print "Invalid MAST"
        return 1
    pretty = PrettyMAST()
    pretty.visitExpr(term)
    s = pretty.asUnicode()
    for line in s.encode("utf-8").split("\n"):
        print line.rstrip()
    return 0


def target(driver, *args):
    driver.exe_name = "mt-dump-mast"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
