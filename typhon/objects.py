from typhon.errors import Ejecting, Refused


class Object(object):
    pass


class _NullObject(Object):

    def repr(self):
        return "<null>"

    def recv(self, verb, args):
        raise Refused(verb, args)


NullObject = _NullObject()


class BoolObject(Object):

    def __init__(self, b):
        self._b = b

    def repr(self):
        return "true" if self._b else "false"

    def recv(self, verb, args):
        raise Refused(verb, args)

    def isTrue(self):
        return self._b


TrueObject = BoolObject(True)
FalseObject = BoolObject(False)


def wrapBool(b):
    return TrueObject if b else FalseObject


class CharObject(Object):

    def __init__(self, c):
        self._c = c

    def repr(self):
        return "'%s'" % (self._c.encode("utf-8"))

    def recv(self, verb, args):
        raise Refused(verb, args)


class EjectorObject(Object):

    active = True

    def repr(self):
        return "<ejector>"

    def recv(self, verb, args):
        if verb == u"run":
            if len(args) == 1:
                if self.active:
                    raise Ejecting(self, args[0])
                else:
                    raise RuntimeError
        raise Refused(verb, args)

    def deactivate(self):
        self.active = False


class EqualizerObject(Object):

    def repr(self):
        return "<equalizer>"

    def recv(self, verb, args):
        if verb == u"sameEver":
            if len(args) == 2:
                first, second = args
                return wrapBool(self.sameEver(first, second))
        raise Refused(verb, args)

    def sameEver(self, first, second):
        """
        Determine whether two objects are ever equal.

        This is a complex topic; expect lots of comments.
        """

        # Two identical objects are equal.
        if first is second:
            return True

        # By default, objects are not equal.
        return False


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
        raise Refused(verb, args)


class ConstListObject(Object):

    def __init__(self, l):
        self._l = l

    def repr(self):
        return "[" + ", ".join([obj.repr() for obj in self._l]) + "]"

    def recv(self, verb, args):
        raise Refused(verb, args)


class StrObject(Object):

    def __init__(self, s):
        self._s = s

    def recv(self, verb, args):
        if verb == u"get":
            if len(args) == 1:
                if isinstance(args[0], IntObject):
                    return CharObject(self._s[args[0]._i])
        raise Refused(verb, args)


class ScriptObject(Object):

    def __init__(self, script, env):
        self._env = env
        self._script = script
        self._methods = {}

        for method in self._script._methods:
            # God *dammit*, RPython.
            from typhon.nodes import Method
            assert isinstance(method, Method)
            assert isinstance(method._verb, unicode)
            self._methods[method._verb] = method

    def repr(self):
        return "<scriptObject>"

    def recv(self, verb, args):
        if verb in self._methods:
            method = self._methods[verb]

            try:
                self._env.enterFrame()
                # Set up parameters from arguments.
                if not method._ps.unify(ConstListObject(args), self._env):
                    raise RuntimeError
                # Run the block.
                rv = method._b.evaluate(self._env)
            finally:
                self._env.leaveFrame()

            return rv
        raise Refused(verb, args)
