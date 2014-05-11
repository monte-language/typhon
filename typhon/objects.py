from typhon.errors import Ejecting


class Object(object):
    pass


class _NullObject(Object):

    def repr(self):
        return "<null>"

    def recv(self, verb, args):
        raise RuntimeError


NullObject = _NullObject()


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
        raise RuntimeError

    def deactivate(self):
        self.active = False


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


class StrObject(Object):

    def __init__(self, s):
        self._s = s

    def recv(self, verb, args):
        raise RuntimeError


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
        raise RuntimeError
