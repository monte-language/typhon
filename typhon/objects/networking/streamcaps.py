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


def readStreamCB(stream, status, buf):
    status = intmask(status)
    # We only restash in the success case, not the error cases.
    vat, source = ruv.unstashStream(stream)
    assert isinstance(source, StreamSource), "Implementation error"
    # Don't read any more. We'll call .readStart() when we're interested in
    # reading again.
    ruv.readStop(stream)
    with scopedVat(vat):
        if status > 0:
            # Restash required.
            ruv.stashStream(stream, (vat, source))
            data = charpsize2str(buf.c_base, status)
            source.deliver(data)
        elif status == -4095:
            # EOF.
            source.complete()
        else:
            msg = ruv.formatError(status).decode("utf-8")
            source.abort(u"libuv error: %s" % msg)

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

        ruv.stashStream(stream._stream, (vat, self))

    def _nextSink(self):
        assert self._queue, "pepperocini"
        return self._queue.pop(0)

    def _cleanup(self):
        self._closed = True
        self._stream.release()
        self._stream = None

    def deliver(self, data):
        from typhon.objects.collections.maps import EMPTY_MAP
        r, sink = self._nextSink()
        p = self._vat.send(sink, RUN_1, [BytesObject(data)], EMPTY_MAP)
        r.resolve(p)

    def complete(self):
        self._cleanup()
        from typhon.objects.collections.maps import EMPTY_MAP
        for r, sink in self._queue:
            r.resolve(NullObject)
            self._vat.sendOnly(sink, COMPLETE_0, [], EMPTY_MAP)

    def abort(self, reason):
        self._cleanup()
        from typhon.objects.collections.maps import EMPTY_MAP
        for r, sink in self._queue:
            r.resolve(NullObject)
            self._vat.sendOnly(sink, ABORT_1, [StrObject(reason)], EMPTY_MAP)

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
        ruv.readStart(self._stream._stream, ruv.allocCB, readStreamCB)
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

def writeStreamCB(uv_write, status):
    pass

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
        self.closed = True
        self._stream.release()
        self._stream = None

    @method("Void", "Bytes")
    def run(self, data):
        if self.closed:
            raise userError(u"run/1: Couldn't send to closed stream")

        # XXX backpressure?
        uv_write = ruv.alloc_write()
        with ruv.scopedBufs([data]) as bufs:
            ruv.write(uv_write, self._stream._stream, bufs, 1, writeStreamCB)

    @method("Void")
    def complete(self):
        self._cleanup()

    @method("Void", "Any")
    def abort(self, problem):
        self._cleanup()

    @method("Bool")
    def isATTY(self):
        return False


def readFileCB(fs):
    size = intmask(fs.c_result)
    vat, source = ruv.unstashFS(fs)
    assert isinstance(source, FileSource)
    with scopedVat(vat):
        if size > 0:
            data = charpsize2str(source._buf.c_base, size)
            source.deliver(data)
        elif size < 0:
            msg = ruv.formatError(size).decode("utf-8")
            source.abort(u"libuv error: %s" % msg)
        else:
            # EOF.
            source.complete()
    ruv.fsDiscard(fs)


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

    def _cleanup(self):
        uv_loop = self._vat.uv_loop
        fs = ruv.alloc_fs()
        ruv.stashFS(fs, (self._vat, self))
        ruv.fsClose(uv_loop, fs, self._fd, ruv.fsUnstashAndDiscard)
        ruv.freeBuf(self._buf)

    def deliver(self, data):
        from typhon.objects.collections.maps import EMPTY_MAP
        r, sink = self._nextSink()
        p = self._vat.send(sink, RUN_1, [BytesObject(data)], EMPTY_MAP)
        r.resolve(p)

    def complete(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        r, sink = self._nextSink()
        r.resolve(NullObject)
        self._vat.sendOnly(sink, COMPLETE_0, [], EMPTY_MAP)
        self._cleanup()

    def abort(self, reason):
        from typhon.objects.collections.maps import EMPTY_MAP
        r, sink = self._nextSink()
        r.resolve(NullObject)
        self._vat.sendOnly(sink, ABORT_1, [StrObject(reason)], EMPTY_MAP)
        self._cleanup()

    @method("Any", "Any")
    def run(self, sink):
        p, r = makePromise()
        self._queue.append((r, sink))
        with scoped_alloc(ruv.rffi.CArray(ruv.buf_t), 1) as bufs:
            bufs[0].c_base = self._buf.c_base
            bufs[0].c_len = self._buf.c_len
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (self._vat, self))
            ruv.fsRead(self._vat.uv_loop, fs, self._fd, bufs, 1, -1,
                       readFileCB)
        return p

    @method("Bool")
    def isATTY(self):
        return False


def writeFileCB(fs):
    try:
        vat, sink = ruv.unstashFS(fs)
        assert isinstance(sink, FileSink)
        size = intmask(fs.c_result)
        if size > 0:
            # XXX backpressure drain.written(size)
            pass
        elif size < 0:
            msg = ruv.formatError(size).decode("utf-8")
            sink.abort(StrObject(u"libuv error: %s" % msg))
        ruv.fsDiscard(fs)
    except:
        print "Exception in writeFileCB"


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
        fs = ruv.alloc_fs()
        ruv.stashFS(fs, (self._vat, self))
        ruv.fsClose(self._vat.uv_loop, fs, self._fd, ruv.fsUnstashAndDiscard)
        self.closed = True

    @method("Void", "Bytes")
    def run(self, data):
        if self.closed:
            raise userError(u"run/1: Couldn't write to closed file")

        with ruv.scopedBufs([data]) as bufs:
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (self._vat, self))
            ruv.fsWrite(self._vat.uv_loop, fs, self._fd, bufs, 1, -1,
                        writeFileCB)

    @method("Void")
    def complete(self):
        self._cleanup()

    @method.py("Void", "Any")
    def abort(self, problem):
        self._cleanup()

    @method("Bool")
    def isATTY(self):
        return False
