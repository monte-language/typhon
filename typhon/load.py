from rpython.rlib.rstruct.ieee import unpack_float
from rpython.rlib.runicode import str_decode_utf_8

from typhon.nodes import (Assign, Call, Char, Def, Double, Escape,
                          FinalPattern, Finally, If, Int, IgnorePattern,
                          ListPattern, Method, Noun, Null, Obj, Script,
                          Sequence, Str, Tag, Tuple, VarPattern, ViaPattern)


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

    def done(self):
        return self._counter >= len(self._items)

    def nextItem(self):
        assert self._counter < len(self._items), "Buffer underrun while streaming"
        rv = self._items[self._counter]
        self._counter += 1
        return rv

    def nextByte(self):
        return ord(unshift(self.nextItem()))

    def slice(self, count):
        assert count > 0, "Negative count while slicing: %d" % count
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

# The kinds for primitive nodes.
NULL, STR, FLOAT, CHAR = 0, 1, 2, 3
SHORT_INT, LONG_INT  = 4, 5
BIG_TUPLE, SMALL_TUPLE  = 6, 7

kernelNodeInfo = {
    8: ('LiteralExpr', 1),
    9: ('NounExpr', 1),
    10: ('BindingExpr', 1),
    11: ('SeqExpr', 1),
    12: ('MethodCallExpr', 3),
    13: ('Def', 3),
    14: ('Escape', 3),
    15: ('Catch', 2),
    16: ('Object', 4),
    17: ('Script', 3),
    18: ('Method', 5),
    19: ('Matcher', 2),
    20: ('Assign', 2),
    21: ('Finally', 2),
    22: ('KernelTry', 3),
    23: ('HideExpr', 1),
    24: ('If', 3),
    25: ('Meta', 1),
    26: ('FinalPattern', 2),
    27: ('IgnorePattern', 1),
    28: ('VarPattern', 2),
    29: ('ListPattern', 2),
    30: ('ViaPattern', 2),
    31: ('BindingPattern', 1),
    32: ('Character', 1),
}


def loadTerm(stream):
    kind = stream.nextByte()

    if kind == NULL:
        return Null
    elif kind == STR:
        size = stream.nextInt()
        # Special-case zero-length strings to avoid confusing Stream.slice().
        if size == 0:
            return Str(u"")
        rv = stream.slice(size).decode('utf-8')
        return Str(rv)
    elif kind == FLOAT:
        return Double(stream.nextDouble())
    elif kind == CHAR:
        buf = stream.nextItem()
        rv, count = str_decode_utf_8(buf, len(buf), None)
        while rv == u'':
            rv, count = str_decode_utf_8(buf, len(buf), None)
        return Char(rv)
    elif kind == SHORT_INT:
        return Int(stream.nextInt())
    elif kind == LONG_INT:
        rv = 0
        size = stream.nextInt()
        for i in range(size):
            chunk = stream.nextShort()
            rv |= (chunk << LONG_SHIFT * i)
        return Int(rv)
    elif kind == SMALL_TUPLE:
        arity = stream.nextByte()
        return Tuple([loadTerm(stream) for _ in range(arity)])
    elif kind == BIG_TUPLE:
        arity = stream.nextInt()
        return Tuple([loadTerm(stream) for _ in range(arity)])

    # Well, that's it for the primitives. Let's lookup the tag and arity.
    tag, arity = kernelNodeInfo[kind]

    if tag == "FinalPattern":
        return FinalPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "IgnorePattern":
        return IgnorePattern(loadTerm(stream))

    elif tag == "ListPattern":
        return ListPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "VarPattern":
        return VarPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "ViaPattern":
        return ViaPattern(loadTerm(stream), loadTerm(stream))

    elif tag == "Assign":
        return Assign(loadTerm(stream), loadTerm(stream))

    elif tag == "Character":
        # Characters should always contain a single .char. term which can
        # stand alone in RPython.
        string = loadTerm(stream)
        assert isinstance(string, Str)
        assert len(string._s) == 1
        return Char(string._s[0])

    elif tag == "Def":
        return Def(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "Escape":
        return Escape(loadTerm(stream), loadTerm(stream))

    elif tag == "Finally":
        return Finally(loadTerm(stream), loadTerm(stream))

    elif tag == "If":
        return If(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "LiteralExpr":
        # LiteralExprs always contain one single literal; consume and return
        # that literal.
        return loadTerm(stream)

    elif tag == "Method":
        return Method(loadTerm(stream), loadTerm(stream), loadTerm(stream),
                      loadTerm(stream), loadTerm(stream))

    elif tag == "MethodCallExpr":
        return Call(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "NounExpr":
        return Noun(loadTerm(stream))

    elif tag == "Object":
        return Obj(loadTerm(stream), loadTerm(stream), loadTerm(stream),
                   loadTerm(stream))

    elif tag == "Script":
        return Script(loadTerm(stream), loadTerm(stream), loadTerm(stream))

    elif tag == "SeqExpr":
        # SeqExprs contain one single tuple; consume and return the tuple
        # wrapped in a Sequence.
        return Sequence(loadTerm(stream))

    return Tag(tag, [loadTerm(stream) for _ in range(arity)])


def load(data):
    stream = Stream(data)
    terms = []
    while not stream.done():
        terms.append(loadTerm(stream))
    return terms
