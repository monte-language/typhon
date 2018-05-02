from rpython.rlib.objectmodel import specialize
from typhon.enum import makeEnum
OK, ERR, LOOP_BREAK, LOOP_CONTINUE = makeEnum(
    "Future", ("OK", "ERR", "LOOP_BREAK", "LOOP_CONTINUE"))


@specialize.argtype(0)
def Ok(value):
    return (OK, value, None)


@specialize.argtype(0)
def Err(err):
    return (ERR, None, err)


@specialize.argtype(0)
def Break(value):
    return (LOOP_BREAK, value, None)


def Continue():
    return (LOOP_CONTINUE, None, None)


class Future(object):
    pass


class IOEvent(object):
    pass


class resolve(Future):
    callbackType = object

    def __init__(self, resolver, value):
        self.resolver = resolver
        self.value = value

    def run(self, state, k):
        self.resolver.resolve(self.value)
        if k is not None:
            k.do(state, Ok(self.value))


class smash(Future):
    callbackType = object

    def __init__(self, resolver, value):
        self.resolver = resolver
        self.value = value

    def run(self, state, k):
        self.resolver.smash(self.value)
        if k is not None:
            k.do(state, Err(self.value))


class FutureCtx(object):
    vat = None
