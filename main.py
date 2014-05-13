import sys

from typhon.env import Environment
from typhon.load import load
from typhon.simple import simpleScope


def entry_point(argv):
    if len(argv) < 2:
        print "No file provided?"
        return 1

    terms = load(open(argv[1], "rb").read())
    env = Environment(simpleScope())
    for term in terms:
        print term.repr()
        print term.evaluate(env).repr()

    return 0


def target(*args):
    return entry_point, None


if __name__ == "__main__":
    entry_point(sys.argv)
