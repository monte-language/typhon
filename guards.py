import sys

guards = []

for i, line in enumerate(sys.stdin):
    if line.startswith("guard_"):
        guards.append((i, line))
    elif line.startswith("# bridge out of Guard"):
        guardTag = line.split()[5]
        for lineNo, guard in guards:
            if guardTag in guard:
                print "Guard", guardTag
                print lineNo, guard
                break
