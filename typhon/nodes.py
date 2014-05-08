class Node(object):
    def __repr__(self):
        return self.repr()
    def repr(self):
        assert False, "Inconceivable!"
    def evaluate(self):
        return self


class Null(Node):
    def repr(self):
        return "<null>"


class Int(Node):
    def __init__(self, i):
        self._i = i
    def repr(self):
        return "%d" % self._i


class Str(Node):
    def __init__(self, s):
        self._s = s
    def repr(self):
        return '"%s"' % (self._s.encode("utf-8"))


class Double(Node):
    def __init__(self, d):
        self._d = d
    def repr(self):
        return "%f" % self._d


class Char(Node):
    def __init__(self, c):
        self._c = c
    def repr(self):
        return "'%s'" % (self._c.encode("utf-8"))


class Tuple(Node):
    def __init__(self, t):
        self._t = t
    def repr(self):
        buf = "["
        buf += ", ".join([item.repr() for item in self._t])
        buf += "]"
        return buf


class Tag(Node):
    def __init__(self, tag, args):
        self._tag = tag
        self._args = args
    def repr(self):
        buf = self._tag + "("
        buf += ", ".join([item.repr() for item in self._args])
        buf += ")"
        return buf
