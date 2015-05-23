#!/usr/bin/env python

import sys

from typhon.load import load
from typhon.nodes import Sequence

path = sys.argv[1]

term = Sequence(load(open(path, "rb").read())[:])
print term.repr()
