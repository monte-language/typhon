#!/usr/bin/env python

import sys
from typhon.load.mast import loadMAST

path = sys.argv[1]
term = loadMAST(path, noisy=False)
for line in term.repr().split("\n"):
    print line.rstrip()
