from functools import wraps

from rpython.rlib.debug import debug_print

"""
Simple tagged logger.
"""


class Logger(object):
    """
    A logger which uses context tags to determine whether an event is
    loggable.
    """

    def __init__(self):
        self.tags = {}

    def log(self, tags, message):
        for tag in tags:
            if tag in self.tags:
                self.write(tags, message)
                return

    def write(self, tags, message):
        tagString = "(%s)" % ":".join(tags)
        debug_print("Log:", tagString, message.encode("utf-8"))


logger = Logger()
log = logger.log

def deprecated(message):
    """
    Decorate a function so that it will log a deprecation warning when called.
    """

    def deco(f):
        @wraps(f)
        def inner(*args):
            log(["serious", "deprecated"], message)
            return f(*args)
        return inner
    return deco
