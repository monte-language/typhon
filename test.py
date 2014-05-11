import sys

from typhon.env import Environment
from typhon.load import Stream, loadTerm
from typhon.simple import simpleScope


def entry_point(argv):
    if len(argv) < 2:
        print "No file provided?"
        return 1

    term = loadTerm(Stream(open(argv[1], "rb").read()))
    env = Environment(simpleScope())
    print term.repr()
    print term.evaluate(env).repr()

    return 0


def target(*args):
    return entry_point, None


if __name__ == "__main__":
    entry_point(sys.argv)
