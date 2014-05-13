DEF, VAR = range(2)


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = DEF, scope[key]
    return rv


class Environment(object):
    """
    An execution context.
    """

    def __init__(self, baseScope):
        self._frames = [finalize(baseScope)]

    def enterFrame(self):
        self._frames.append({})

    def leaveFrame(self):
        frame = self._frames.pop()

    def _record(self, noun, value):
        try:
            frame = self._findFrame(noun)
        except:
            frame = self._frames[-1]
        frame[noun] = value

    def _findFrame(self, noun):
        i = len(self._frames)
        while i > 0:
            i -= 1
            frame = self._frames[i]
            if noun in frame:
                return frame
        raise KeyError(noun)

    def _find(self, noun):
        i = len(self._frames)
        while i > 0:
            i -= 1
            frame = self._frames[i]
            if noun in frame:
                return frame[noun]
        raise KeyError(noun)

    def final(self, noun, value):
        self._record(noun, (DEF, value))

    def variable(self, noun, value):
        self._record(noun, (VAR, value))

    def update(self, noun, value):
        style, oldValue = self._find(noun)
        if style == VAR:
            # XXX this won't alter outer bindings. A real slot mechanism is
            # needed here!
            self._record(noun, (VAR, value))
        else:
            raise RuntimeError

    def get(self, noun):
        style, value = self._find(noun)
        return value
