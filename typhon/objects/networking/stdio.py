from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject, unwrapInt, unwrapStr
from typhon.objects.root import Object, method, runnable
from typhon.specs import Any, List, Str, Void
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

    @method([], Void)
    def unpause(self):
        assert isinstance(self, InputUnpauser)
        if self.fount is not None:
            self.fount.unpause()
            self.fount = None


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

    @method([Any], Any)
    def flowTo(self, drain):
        assert isinstance(self, InputFount)
        self._drain = drain
        rv = drain.call(u"flowingFrom", [self])
        return rv

    @method([], Any)
    def pauseFlow(self):
        assert isinstance(self, InputFount)
        return self.pause()

    @method([], Void)
    def abortFlow(self):
        assert isinstance(self, InputFount)
        self._drain.call(u"flowAborted", [StrObject(u"flow aborted")])
        # Release the drain. They should have released us as well.
        self._drain = None

    @method([], Void)
    def stopFlow(self):
        assert isinstance(self, InputFount)
        self.terminate(u"Flow stopped")

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
        if not self.pauses and self._drain is not None:
            rv = [IntObject(ord(byte)) for byte in self.buf]
            self.vat.sendOnly(self._drain, RECEIVE_1, [ConstList(rv)])
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

    @method([Any], Any)
    def flowingFrom(self, fount):
        return self

    @method([List], Void)
    def receive(self, data):
        assert isinstance(self, OutputDrain)
        if self._closed:
            raise userError(u"Can't send data to a closed FD!")

        s = "".join([chr(unwrapInt(byte)) for byte in data])
        self.selectable.enqueue(s)

    @method([Str], Void)
    def flowAborted(self, reason):
        assert isinstance(self, OutputDrain)
        self._closed = True
        vat = currentVat.get()
        self.selectable.error(vat._reactor, reason)

    @method([Str], Void)
    def flowStopped(self, reason):
        assert isinstance(self, OutputDrain)
        self._closed = True
        vat = currentVat.get()
        self.selectable.error(vat._reactor, reason)


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
