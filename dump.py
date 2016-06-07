#!/usr/bin/env python

import sys
from typhon.load.nano import InvalidMAST, loadMAST
from typhon.nano.mast import SaveScripts
from typhon.nano.scopes import (LayOutScopes, PrettySpecialNouns,
                                SpecializeNouns)
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
    ss = SaveScripts().visitExpr(expr)
    ll = LayOutScopes().visitExpr(ss)
    sl = SpecializeNouns().visitExpr(ll)
    pretty = PrettySpecialNouns()
    pretty.visitExpr(sl)
    dumpLines(pretty.asUnicode())
    return 0


def target(driver, *args):
    driver.exe_name = "mt-dump-mast"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
