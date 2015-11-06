from __future__ import division

from collections import defaultdict
from math import sqrt
import sys

current = None
totals = defaultdict(int)
markers = defaultdict(int)
inNoopt = False
loops = set()

for line in sys.stdin:
    if "{jit-log-noopt-loop" in line:
        inNoopt = True
    elif "jit-log-noopt-loop}" in line:
        inNoopt = False

    if "noopt with" in line:
        loops.add(int(line.split()[-2]))

    if not inNoopt:
        continue

    if line.startswith("jit_debug("):
        try:
            s, _, _ = line.split(",")
            name = s[11:-1]
            current = name
            markers[current] += 1
        except ValueError:
            totals[current] += 1
    else:
        totals[current] += 1

for marker in markers:
    if marker is None:
        continue

    m = markers[marker]
    t = totals[marker]
    avg = t / m
    name = marker.ljust(15)
    print "%s: %10d instances %10d total %0.2f average" % (name, m, t, avg)

loops = list(loops)
loops.sort()
avg = sum(loops) / len(loops)
stddev = sqrt(sum((l - avg) ** 2 for l in loops) / len(loops))
print len(loops), "loops"
print loops
print "Average loop length", avg, "standard deviation", stddev
print "+3 stddevs from mean", avg + (stddev * 3)
