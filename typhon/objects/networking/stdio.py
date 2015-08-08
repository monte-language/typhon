from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapBytes, unwrapStr
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


ABORTFLOW_0 = getAtom(u"abortFlow", 0)
FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
FLOWTO_1 = getAtom(u"flowTo", 1)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_0 = getAtom(u"run", 0)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


@autohelp
class InputUnpauser(Object):
    """
    A pause on a standard input fount.
    """

    def __init__(self, fount):
        self.fount = fount

    def recv(self, atom, args):
        if atom is UNPAUSE_0:
            if self.fount is not None:
                self.fount.unpause()
                self.fount = None
            return NullObject
        raise Refused(self, atom, args)


@autohelp
class InputFount(Object):
    """
    A fount which flows data out from standard input.
    """

    pauses = 0
    buf = ""

    _drain = None

    def __init__(self, vat):
        self.vat = vat

    def toString(self):
        return u"<InputFount>"

    def recv(self, atom, args):
        if atom is FLOWTO_1:
            self._drain = drain = args[0]
            rv = drain.call(u"flowingFrom", [self])
            return rv

        if atom is PAUSEFLOW_0:
            return self.pause()

        if atom is ABORTFLOW_0:
            self._drain.call(u"flowAborted", [StrObject(u"flow aborted")])
            # Release the drain. They should have released us as well.
            self._drain = None
            return NullObject

        if atom is STOPFLOW_0:
            self.terminate(u"Flow stopped")
            return NullObject

        raise Refused(self, atom, args)

    def pause(self):
        self.pauses += 1
        return InputUnpauser(self)

    def unpause(self):
        self.pauses -= 1
        self.flush()

    def receive(self, buf):
        self.buf += buf
        self.flush()

    def flush(self):
        from typhon.objects.collections import EMPTY_MAP
        if not self.pauses and self._drain is not None:
            rv = BytesObject(self.buf)
            self.vat.sendOnly(self._drain, RECEIVE_1, [rv], EMPTY_MAP)
            self.buf = ""

    def terminate(self, reason):
        if self._drain is not None:
            self._drain.call(u"flowStopped", [StrObject(reason)])
            # Release the drain. They should have released us as well.
            self._drain = None


@runnable(RUN_0)
def makeStdIn(_):
    from typhon.selectables import StandardInput

    vat = currentVat.get()
    reactor = vat._reactor

    stdin = StandardInput()
    stdin.addToReactor(reactor)
    return stdin.createFount()


@autohelp
class OutputDrain(Object):
    """
    A drain which sends received data out on standard output.

    Standard error is also supported.
    """

    _closed = False

    def __init__(self, selectable):
        self.selectable = selectable
        self._buf = []

    def toString(self):
        return u"<OutputDrain>"

    def recv(self, atom, args):
        if atom is FLOWINGFROM_1:
            return self

        if atom is RECEIVE_1:
            if self._closed:
                raise userError(u"Can't send data to a closed FD!")

            data = unwrapBytes(args[0])
            self.selectable.enqueue(data)
            return NullObject

        if atom is FLOWABORTED_1:
            self._closed = True
            vat = currentVat.get()
            self.selectable.error(vat._reactor, unwrapStr(args[0]))
            return NullObject

        if atom is FLOWSTOPPED_1:
            self._closed = True
            vat = currentVat.get()
            self.selectable.error(vat._reactor, unwrapStr(args[0]))
            return NullObject

        raise Refused(self, atom, args)


@runnable(RUN_0)
def makeStdOut(_):
    from typhon.selectables import StandardOutput

    vat = currentVat.get()
    reactor = vat._reactor

    stdout = StandardOutput(reactor, 1)
    stdout.addToReactor(reactor)
    return OutputDrain(stdout)


@runnable(RUN_0)
def makeStdErr(_):
    from typhon.selectables import StandardOutput

    vat = currentVat.get()
    reactor = vat._reactor

    stderr = StandardOutput(reactor, 2)
    stderr.addToReactor(reactor)
    return OutputDrain(stderr)
