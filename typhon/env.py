class Environment(object):
    """
    An execution context.
    """

    def __init__(self, baseScope):
        self._frames = [baseScope]

    def enterFrame(self):
        self._frames.append({})

    def leaveFrame(self):
        self._frames.pop()

    def record(self, noun, value):
        frame = self._frames[-1]
        frame[noun] = value

    def find(self, noun):
        i = len(self._frames)
        while i > 0:
            i -= 1
            frame = self._frames[i]
            if noun in frame:
                return frame[noun]
        raise RuntimeError
