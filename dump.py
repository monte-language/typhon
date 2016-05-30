#!/usr/bin/env python

import sys
from typhon.load.nano import InvalidMAST, loadMAST
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
    import pdb; pdb.set_trace()
    for line in term.repr().split("\n"):
        print line.rstrip()
    return 0


def target(driver, *args):
    driver.exe_name = "mt-dump-mast"
    return entryPoint, None


if __name__ == "__main__":
    sys.exit(entryPoint(sys.argv))
