#!/usr/bin/env python

import sys

path = sys.argv[1]

if path.endswith(".ty"):
    from typhon.load.trash import load
    from typhon.nodes import Sequence

    term = Sequence(load(open(path, "rb").read())[:])
else:
    from typhon.load.mast import loadMAST
    term = loadMAST(path, noisy=True)

for line in term.repr().split("\n"):
    print line.rstrip()
