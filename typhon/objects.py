class Object(object):
    pass


class IntObject(Object):

    def __init__(self, i):
        self._i = i

    def repr(self):
        return "%d" % self._i

    def recv(self, verb, args):
        if verb == u"add":
            if len(args) == 1:
                other = args[0]
                if isinstance(other, IntObject):
                    return IntObject(self._i + other._i)
        elif verb == u"multiply":
            if len(args) == 1:
                other = args[0]
                if isinstance(other, IntObject):
                    return IntObject(self._i * other._i)
        raise RuntimeError


class ConstListObject(Object):

    def __init__(self, l):
        self._l = l

    def recv(self, verb, args):
        raise RuntimeError


class NullObject(Object):

    def recv(self, verb, args):
        raise RuntimeError


class StrObject(Object):

    def __init__(self, s):
        self._s = s

    def recv(self, verb, args):
        raise RuntimeError
