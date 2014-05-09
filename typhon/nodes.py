from typhon.objects import (ConstListObject, IntObject, NullObject, StrObject)


class Node(object):

    def __repr__(self):
        return self.repr()

    def repr(self):
        assert False, "Inconceivable!"

    def evaluate(self):
        raise NotImplementedError


class Null(Node):

    def repr(self):
        return "<null>"

    def evaluate(self):
        return NullObject()


class Int(Node):

    def __init__(self, i):
        self._i = i

    def repr(self):
        return "%d" % self._i

    def evaluate(self):
        return IntObject(self._i)


class Str(Node):

    def __init__(self, s):
        self._s = s

    def repr(self):
        return '"%s"' % (self._s.encode("utf-8"))

    def evaluate(self):
        return StrObject(self._s)


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

    def evaluate(self):
        return ConstListObject([item.evaluate() for item in self._t])


class Call(Node):

    def __init__(self, target, verb, args):
        self._target = target
        self._verb = verb
        self._args = args

    def repr(self):
        buf = "Call(" + self._target.repr() + ", " + self._verb.repr()
        buf += ", " + self._args.repr() + ")"
        return buf

    def evaluate(self):
        # There's a careful order of operations here. First we have to
        # evaluate the target, then the verb, and finally the arguments.
        # Once we do all that, we make the actual call.
        target = self._target.evaluate()
        verb = self._verb.evaluate()
        assert isinstance(verb, StrObject), "non-Str verb"
        args = self._args.evaluate()
        assert isinstance(args, ConstListObject), "non-List arguments"

        return target.recv(verb._s, args._l)


class Sequence(Node):

    def __init__(self, t):
        assert isinstance(t, Tuple), "Bad Sequence"
        self._t = t

    def repr(self):
        buf = "Sequence("
        buf += self._t.repr()
        buf += ")"
        return buf

    def evaluate(self):
        rv = NullObject()
        for node in self._t._t:
            rv = node.evaluate()
        return rv


class Tag(Node):

    def __init__(self, tag, args):
        self._tag = tag
        self._args = args

    def repr(self):
        buf = self._tag + "("
        buf += ", ".join([item.repr() for item in self._args])
        buf += ")"
        return buf
