#!/usr/bin/env python

import sys

from typhon.load.trash import load
from typhon.nodes import Sequence

path = sys.argv[1]

term = Sequence(load(open(path, "rb").read())[:])
for line in term.repr().split("\n"):
    print line.rstrip()
