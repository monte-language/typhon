"""
A new kind of stream.

Streamcaps are capability-oriented stream objects suitable for implementing
higher-order streaming systems. They come in two pieces: *sources* and
*sinks*. A source can emit objects, and a sink can consume them.

The source has one method, run/1, which takes a sink and returns a promise
which is fulfilled when an object has been delivered to the sink, or broken if
delivery couldn't happen.

The sink has three methods, run/1, complete/0, and abort/1, each corresponding
to delivering three different messages. run/1 is for receiving objects,
complete/0 is a successful end-of-stream signal, and abort/1 is a failing
end-of-stream signal. run/1 also returns a promise which is fulfilled when the
received object has been enqueued by the sink, or broken if queueing failed.

Intended usage: To deliver a single object from m`source` to m`sink`, try:

    source(sink)

To perform some m`action` only after delivery has succeeded, try:

    when (source(sink)) -> { action() }

To receive a single object from a source inline, write an inline sink object:

    object sink:
        to run(obj):
            return process<-(obj)
        to complete():
            success()
        to abort(problem):
            throw(problem)
    source(sink)

To deliver a single m`obj` to a sink inline:

    sink(obj)

And to act only after enqueueing:

    when (sink(obj)) -> { action() }
"""
from signal import SIGWINCH

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import scoped_alloc
from rpython.rtyper.lltypesystem.rffi import charpsize2str, INTP

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.futures import Future, Ok, IOEvent
from typhon.macros import macros, io
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject
from typhon.objects.refs import makePromise
from typhon.objects.signals import SignalHandle
from typhon.objects.root import Object
from typhon.vats import scopedVat

ABORT_1 = getAtom(u"abort", 1)
COMPLETE_0 = getAtom(u"complete", 0)
RUN_1 = getAtom(u"run", 1)


@autohelp
class _NullSink(Object):
    """
    A sink which does nothing.
    """

    @method("Void", "Any")
    def run(self, _):
        pass

    @method("Void")
    def complete(self):
        pass

    @method("Void", "Any")
    def abort(self, _):
        pass

nullSink = _NullSink()


@autohelp
class _EmptySource(Object):
    """
    A source which has nothing.
    """

    @method("Void", "Any")
    def run(self, sink):
        sink.call(u"complete", [])

emptySource = _EmptySource()


@autohelp
class StreamSource(Object):
    """
    A source which reads bytestrings from a libuv stream.
    """

    _failure = None
    _closed = False

    def __init__(self, stream, vat):
        self._stream = stream
        self._vat = vat

        self._queue = []

    def _nextSink(self):
        assert self._queue, "pepperocini"
        return self._queue.pop(0)

    def _cleanup(self):
        self._closed = True
        self._stream.release()
        self._stream = None


    @method("Any", "Any")
    def run(self, sink):
        if self._closed:
            # Surprisingly, we do *not* need to throw here; we can simply
            # indicate that we're already done.
            from typhon.objects.collections.maps import EMPTY_MAP
            if self._failure is None:
                return self._vat.send(sink, COMPLETE_0, [], EMPTY_MAP)
            else:
                return self._vat.send(sink, ABORT_1, [self._failure],
                                      EMPTY_MAP)

        p, r = makePromise()
        self._queue.append((r, sink))
        with io:
            try:
                data = ruv.magic_readStart(self._stream._stream)
            except object as err:
                sendAllSinks(self, ABORT_1,
                             [StrObject(u"libuv error: %s" % err)])
                cleanup(self)
            else:
                if data == "":
                    sendAllSinks(self, COMPLETE_0, [])
                    cleanup(self)
                else:
                    sendNextSink(self, RUN_1, [BytesObject(data)])

        return p

    @method("Bool")
    def isATTY(self):
        return False

@autohelp
class TTYSource(StreamSource):
    """
    A stream source specifically for terminals.
    """

    def __init__(self, tty, stream, vat):
        self._tty = tty
        StreamSource.__init__(self, stream, vat)

    @method("Bool")
    def isATTY(self):
        return True

    @method("Void", "Bool")
    def setRawMode(self, rawMode):
        if rawMode:
            ruv.TTYSetMode(self._tty, ruv.TTY_MODE_RAW)
        else:
            ruv.TTYSetMode(self._tty, ruv.TTY_MODE_NORMAL)


class StreamSinkCleanup(IOEvent):
    def __init__(self, streamSink):
        self.streamSink = streamSink

    def run(self):
        self.streamSink.closed = True
        self.streamSink._stream.release()
        self.streamSink._stream = None


@autohelp
class StreamSink(Object):
    """
    A sink which delivers bytestrings to a libuv stream.
    """

    closed = False

    def __init__(self, stream, vat):
        self._stream = stream
        self._vat = vat

    def _cleanup(self):
        currentVat.get().enqueueEvent(StreamSinkCleanup(self))

    @method("Void", "Bytes")
    def run(self, data):
        if self.closed:
            raise userError(u"run/1: Couldn't send to closed stream")

        # XXX backpressure?
        with io:
            ruv.magic_write(self._stream._stream, data)

    @method("Void")
    def complete(self):
        self._cleanup()

    @method("Void", "Any")
    def abort(self, problem):
        self._cleanup()

    @method("Bool")
    def isATTY(self):
        return False



@autohelp
class TTYSink(StreamSink):
    """
    A stream sink for terminals.
    """

    def __init__(self, tty, stream, vat):
        self._tty = tty
        StreamSink.__init__(self, stream, vat)

    @method("Any")
    def getWindowSize(self):
        from typhon.objects.data import wrapInt
        from typhon.objects.collections.lists import ConstList
        with scoped_alloc(INTP.TO, 1) as widthp, \
                scoped_alloc(INTP.TO, 1) as heightp:
            ruv.TTYGetWinSize(self._tty, widthp, heightp)
            width = intmask(widthp[0])
            height = intmask(heightp[0])
        return ConstList([wrapInt(width), wrapInt(height)])

    @method("Any", "Any")
    def whenWindowSizeChanges(self, cb):
        return SignalHandle(SIGWINCH, cb, self._vat)

@autohelp
class FileSource(Object):
    """
    A source which reads bytestrings from a file.
    """

    def __init__(self, fd, vat):
        self._fd = fd
        self._vat = vat

        self._queue = []

        # XXX read size should be tunable
        self._buf = ruv.allocBuf(16384)

    def _nextSink(self):
        assert self._queue, "pepperocini"
        return self._queue.pop(0)


    @method("Any", "Any")
    def run(self, sink):
        p, r = makePromise()
        self._queue.append((r, sink))
        # XXX long handwavey explanation of io macro limitations vs rpython
        # type unification here
        vat, fd, buf = self._vat, self._fd, self._buf
        with io:
            try:
                data = ruv.magic_fsRead(vat, fd, buf)
            except object as err:
                sendAllSinks(self, ABORT_1, [StrObject(u"libuv error: %s" % err)])
                ruv.magic_fsClose(self._vat, self._fd)

                cleanup(self)
            else:
                if data == "":
                    sendAllSinks(self, COMPLETE_0, [])
                    ruv.magic_fsClose(self._vat, self._fd)
                else:
                    sendNextSink(self, RUN_1, [BytesObject(data)])

        return p

    @method("Bool")
    def isATTY(self):
        return False


@autohelp
class FileSink(Object):
    """
    A sink which writes bytestrings to a file.
    """

    closed = False

    def __init__(self, fd, vat):
        self._fd = fd
        self._vat = vat

    def _cleanup(self):
        self.closed = True
        with io:
            ruv.magic_fsClose(self._vat, self._fd)

    @method("Void", "Bytes")
    def run(self, data):
        if self.closed:
            raise userError(u"run/1: Couldn't write to closged file")
        with io:
            try:
                ruv.magic_fsWrite(self._vat, self._fd, data)
            except object as _:
                cleanup(self)

    @method("Void")
    def complete(self):
        self._cleanup()

    @method.py("Void", "Any")
    def abort(self, problem):
        self._cleanup()

    @method("Bool")
    def isATTY(self):
        return False


class cleanup(Future):
    callbackType = object

    def __init__(self, target):
        target._cleanup()

    def run(self, state, k):
        assert k is None


class SendNextSinkCallback(object):
    pass


class sendNextSink(Future):
    callbackType = SendNextSinkCallback

    def __init__(self, target, verb, args):
        self.target = target
        self.verb = verb
        self.args = args

    def run(self, state, k):
        from typhon.objects.collections.maps import EMPTY_MAP
        r, sink = self.target._nextSink()
        with scopedVat(self.target._vat):
            p = self.target._vat.send(sink, self.verb, self.args, EMPTY_MAP)
        r.resolve(p)
        if k:
            k.do(state, Ok(None))


class SendAllSinksCallback(object):
    pass


class sendAllSinks(Future):
    callbackType = SendAllSinksCallback

    def __init__(self, target, verb, args):
        self.target = target
        self.verb = verb
        self.args = args

    def run(self, state, k):
        from typhon.objects.collections.maps import EMPTY_MAP
        for r, sink in self.target._queue:
            r.resolve(NullObject)
            with scopedVat(self.target._vat):
                self.target._vat.send(sink, self.verb, self.args, EMPTY_MAP)
        if k:
            k.do(state, Ok(None))
