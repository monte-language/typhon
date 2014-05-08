import struct
import sys
from encodings.utf_8 import IncrementalDecoder

class Stream(object):

    _counter = 0

    def __init__(self, items):
        self._items = items

    def nextItem(self):
        if self._counter >= len(self._items):
            return None
        rv = self._items[self._counter]
        self._counter += 1
        return rv

    def nextByte(self):
        return ord(unshift(self.nextItem()))

    def slice(self, count):
        if self._counter + count >= len(self._items):
            return None
        rv = self._items[self._counter:self._counter + count]
        self._counter += count
        return rv

    def nextShort(self):
        return struct.unpack('!h', unshift(self.slice(2)))[0]

    def nextInt(self):
        return struct.unpack('!i', unshift(self.slice(4)))[0]

    def nextDouble(self):
        return struct.unpack('!d', unshift(self.slice(8)))[0]


def unshift(bs):
    return ''.join(chr((ord(b) - 32) % 256) for b in bs)


LONG_SHIFT = 15

kernelNodeInfo = [
    ('null', 0),
    ('.String.', None),
    ('.float64.', None),
    ('.char.', None),
    # different tags for short ints...
    ('.int.', None),
    # ... and long ints
    ('.int.', None),
    # this one for small tuples...
    ('.tuple.', None),
    # ... this one for large
    ('.tuple.', None),
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
        return "null"
    elif tag == '.int.':
        if kind == SHORT_INT:
            rv = stream.nextInt()
        else:
            rv = 0
            size = stream.nextInt()
            for i in range(size):
                chunk = stream.nextShort()
                literalVal |= (chunk << LONG_SHIFT * i)
        return ["int", rv]
    elif tag == '.String.':
        size = stream.nextInt()
        rv = stream.slice(size).decode('utf-8')
        return ["str", rv]
    elif tag == '.float64.':
        return ["double", stream.nextDouble()]
    elif tag == '.char.':
        de = IncrementalDecoder()
        rv = de.decode(stream.nextItem())
        while rv == u'':
            rv = de.decode(stream.nextItem())
        return ["char", rv]
    elif tag == '.tuple.':
        if kind == BIG_TUPLE:
            arity = stream.nextInt()
        else:
            arity = stream.nextByte()
        return ["tuple", [loadTerm(stream) for _ in range(arity)]]

    return [tag, [loadTerm(stream) for _ in range(arity)]]


def entry_point(argv):
    print argv

    if len(argv) < 2:
        print "No file provided?"
        return 1

    print loadTerm(Stream(open(sys.argv[1], "rb").read()))
    return 0


def target(*args):
    return entry_point, None


if __name__ == "__main__":
    entry_point(sys.argv)
