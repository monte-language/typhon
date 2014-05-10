import struct
import sys
from rpython.rlib.rstruct.ieee import unpack_float
from rpython.rlib.runicode import str_decode_utf_8


from typhon.env import Environment
from typhon.nodes import (Call, Char, Def, Double, FinalPattern, Int,
                          IgnorePattern, ListPattern, Noun, Null, Str,
                          Sequence, Tag, Tuple, VarPattern)
from typhon.simple import simpleScope


def unshift(byte):
    return chr((ord(byte[0]) - 32) % 256)


def unshiftBytes(bs):
    rv = ''
    for b in bs:
        rv += unshift(b)
    return rv


class Stream(object):

    _counter = 0

    def __init__(self, items):
        self._items = items

    def nextItem(self):
        assert self._counter < len(self._items), "Buffer underrun while streaming"
        rv = self._items[self._counter]
        self._counter += 1
        return rv

    def nextByte(self):
        return ord(unshift(self.nextItem()))

    def slice(self, count):
        assert count > 0, "Count must be positive when slicing"
        assert self._counter + count <= len(self._items), "Buffer underrun while streaming"
        rv = self._items[self._counter:self._counter + count]
        self._counter += count
        return rv

    def nextShort(self):
        return self.nextByte() << 8 | self.nextByte()

    def nextInt(self):
        return (self.nextByte() << 24 | self.nextByte() << 16 |
                self.nextByte() << 8 | self.nextByte())

    def nextDouble(self):
        # Second parameter is the big-endian flag.
        return unpack_float(self.slice(8), True)


LONG_SHIFT = 15

kernelNodeInfo = [
    ('null', 0),
    ('.String.', 0),
    ('.float64.', 0),
    ('.char.', 0),
    # different tags for short ints...
    ('.int.', 0),
    # ... and long ints
    ('.int.', 0),
    # this one for small tuples...
    ('.tuple.', 0),
    # ... this one for large
    ('.tuple.', 0),
    ('LiteralExpr', 1),
    ('NounExpr', 1),
    ('BindingExpr', 1),
    ('SeqExpr', 1),
    ('MethodCallExpr', 3),
    ('Def', 3),
    ('Escape', 3),
    ('Catch', 2),
    ('Object', 4),
    ('Script', 3),
    ('Method', 5),
    ('Matcher', 2),
    ('Assign', 2),
    ('Finally', 2),
    ('KernelTry', 2),
    ('HideExpr', 1),
    ('If', 3),
    ('Meta', 1),
    ('FinalPattern', 2),
    ('IgnorePattern', 1),
    ('VarPattern', 2),
    ('ListPattern', 2),
    ('ViaPattern', 2),
    ('BindingPattern', 1),
    ('Character', 1)
]

SHORT_INT, LONG_INT  = (4, 5) # indices of the two '.int.'s above
BIG_TUPLE, SMALL_TUPLE  = (6, 7) # indices of the two '.int.'s above


def loadTerm(stream):
    kind = stream.nextByte()
    tag, arity = kernelNodeInfo[kind]

    if tag == "null":
        return Null()
    elif tag == '.int.':
        if kind == SHORT_INT:
            rv = stream.nextInt()
        else:
            rv = 0
            size = stream.nextInt()
            for i in range(size):
                chunk = stream.nextShort()
                rv |= (chunk << LONG_SHIFT * i)
        return Int(rv)
    elif tag == '.String.':
        size = stream.nextInt()
        rv = stream.slice(size).decode('utf-8')
        return Str(rv)
    elif tag == '.float64.':
        return Double(stream.nextDouble())
    elif tag == '.char.':
        buf = stream.nextItem()
        rv, count = str_decode_utf_8(buf, len(buf), None)
        while rv == u'':
            rv, count = str_decode_utf_8(buf, len(buf), None)
        return Char(rv)
    elif tag == '.tuple.':
        if kind == BIG_TUPLE:
            arity = stream.nextInt()
        else:
            arity = stream.nextByte()
        return Tuple([loadTerm(stream) for _ in range(arity)])

    elif tag == "FinalPattern":
        return FinalPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "IgnorePattern":
        return IgnorePattern(loadTerm(stream))

    elif tag == "ListPattern":
        return ListPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "VarPattern":
        return VarPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "Def":
        return Def(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "LiteralExpr":
        # LiteralExprs always contain one single literal; consume and return
        # that literal.
        return loadTerm(stream)

    elif tag == "MethodCallExpr":
        return Call(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "NounExpr":
        return Noun(loadTerm(stream))

    elif tag == "SeqExpr":
        # SeqExprs contain one single tuple; consume and return the tuple
        # wrapped in a Sequence.
        return Sequence(loadTerm(stream))

    return Tag(tag, [loadTerm(stream) for _ in range(arity)])


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
