"""
A new kind of stream.

Streamcaps are capability-oriented stream objects suitable for implementing
higher-order streaming systems. They come in two pieces: *sources* and
*sinks*. A source can emit packets of data, and a sink can consume them.

The source has one method, run/1, which takes a sink and returns a promise
which is fulfilled when a packet has been delivered to the sink, or broken if
delivery couldn't happen.

The sink has three methods, run/1, complete/0, and abort/1, each corresponding
to delivering three different messages. run/1 is for receiving packets of
data, complete/0 is a successful end-of-stream signal, and abort/1 is a
failing end-of-stream signal. run/1 also returns a promise which is fulfilled
when the received packet has been enqueued by the sink, or broken if queueing
failed.

Intended usage: To deliver a single packet from m`source` to m`sink`, try:

    source(sink)

To perform some m`action` only after delivery has succeeded, try:

    when (source(sink)) -> { action() }

To receive a single packet from a source inline, write an inline sink object:

    object sink:
        to run(packet):
            return process<-(packet)
        to complete():
            success()
        to abort(problem):
            throw(problem)
    source(sink)

To deliver a single m`packet` of data to a sink inline:

    sink(packet)

And to act only after enqueueing:

    when (sink(packet)) -> { action() }
"""

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.rffi import charpsize2str

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject
from typhon.objects.refs import makePromise
from typhon.objects.root import Object
from typhon.vats import scopedVat

ABORT_1 = getAtom(u"abort", 1)
COMPLETE_0 = getAtom(u"complete", 0)
RUN_1 = getAtom(u"run", 1)


def readCB(stream, status, buf):
    status = intmask(status)
    # We only restash in the success case, not the error cases.
    vat, source = ruv.unstashStream(stream)
    assert isinstance(source, StreamSource), "Implementation error"
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

    def __init__(self, stream, vat):
        self._stream = stream
        self._vat = vat

        self._queue = []

        ruv.stashStream(stream, (vat, self))

    def deliver(self, data):
        from typhon.objects.collections.maps import EMPTY_MAP
        assert self._queue, "sausage pizza"
        r, sink = self._queue.pop(0)
        # XXX we really should chain the promise from the vat send to the
        # resolver choosing to resolve or smash. Better yet, this should be in
        # t.o.refs as a standard helper. ~ C.
        r.resolve(NullObject)
        self._vat.sendOnly(sink, RUN_1, [BytesObject(data)], EMPTY_MAP)

    def complete(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        assert self._queue, "pepperoni pizza"
        r, sink = self._queue.pop(0)
        r.resolve(NullObject)
        self._vat.sendOnly(sink, COMPLETE_0, [], EMPTY_MAP)

    def abort(self, reason):
        from typhon.objects.collections.maps import EMPTY_MAP
        assert self._queue, "cheese pizza"
        r, sink = self._queue.pop(0)
        r.resolve(NullObject)
        self._vat.sendOnly(sink, ABORT_1, [StrObject(reason)], EMPTY_MAP)

    @method("Any", "Any")
    def run(self, sink):
        p, r = makePromise()
        self._queue.append((r, sink))
        ruv.readStart(self.stream, ruv.allocCB, readCB)
        return p


def writeCB(uv_write, status):
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

    def __del__(self):
        if not ruv.isClosing(self._stream):
            ruv.closeAndFree(self._stream)

    @method("Any", "Bytes")
    def run(self, data):
        if self.closed:
            raise userError(u"run/1: Couldn't send to closed stream")

        # XXX backpressure?
        uv_write = ruv.alloc_write()
        with ruv.scopedBufs([data]) as bufs:
            ruv.write(uv_write, self._stream, bufs, 1, writeCB)

    @method("Void")
    def complete(self):
        self.closed = True

    @method("Void", "Any")
    def abort(self, problem):
        self.closed = True
