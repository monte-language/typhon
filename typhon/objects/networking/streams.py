# Copyright (C) 2014 Google Inc. All rights reserved.  #
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

from rpython.rlib.rarithmetic import intmask
from rpython.rlib.objectmodel import specialize, we_are_translated
from rpython.rtyper.lltypesystem.rffi import charpsize2str

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapBytes
from typhon.objects.root import Object
from typhon.vats import scopedVat


FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
FLUSH_0 = getAtom(u"flush", 0)


@autohelp
class StreamUnpauser(Object):
    """
    A pause on a stream fount.
    """

    def __init__(self, fount):
        self.fount = fount

    @method("Void")
    def unpause(self):
        if self.fount is not None:
            self.fount.unpause()
            self.fount = None


def readCB(stream, status, buf):
    status = intmask(status)
    try:
        # We only restash in the success case, not the error cases.
        vat, fount = ruv.unstashStream(stream)
        assert isinstance(fount, StreamFount), "Implementation error"
        with scopedVat(vat):
            if status > 0:
                # Restash required.
                ruv.stashStream(stream, (vat, fount))
                data = charpsize2str(buf.c_base, status)
                fount.receive(data)
            elif status == -4095:
                # EOF.
                fount.stop(u"End of stream")
            else:
                msg = ruv.formatError(status).decode("utf-8")
                fount.abort(u"libuv error: %s" % msg)
    except:
        if not we_are_translated():
            raise


@autohelp
class StreamFount(Object):
    """
    A fount which flows data out from a stream.
    """

    pauses = 0
    _drain = None
    _reading = False

    _closed = False

    @specialize.call_location()
    def __init__(self, stream, vat):
        # I hate C.
        stream = ruv.rffi.cast(ruv.stream_tp, stream)

        self.stream = stream
        self.vat = vat

        self.bufs = []

        # The initial stashing.
        ruv.stashStream(stream, (vat, self))

    def toString(self):
        return u"<StreamFount>"

    @method("Any", "Any")
    def flowTo(self, drain):
        self._drain = drain
        # We can't actually call receive/1 on the drain until
        # flowingFrom/1 has been called, *but* flush/0 will be queued in a
        # subsequent send to the the one queued here, so we're fine as far
        # as ordering. ~ C.
        from typhon.objects.collections.maps import EMPTY_MAP
        rv = self.vat.send(self._drain, FLOWINGFROM_1, [self], EMPTY_MAP)
        self.considerFlush()
        return rv

    @method("Any")
    def pauseFlow(self):
        return self.pause()

    @method("Void")
    def abortFlow(self):
        self.abort(u"Flow aborted")

    @method("Void")
    def stopFlow(self):
        self.stop(u"Flow stopped")

    def abort(self, reason):
        if self._drain is not None:
            from typhon.objects.collections.maps import EMPTY_MAP
            self.vat.sendOnly(self._drain, FLOWABORTED_1, [StrObject(reason)],
                              EMPTY_MAP)
        self.cleanup()

    def stop(self, reason):
        if self._drain is not None:
            from typhon.objects.collections.maps import EMPTY_MAP
            self.vat.sendOnly(self._drain, FLOWSTOPPED_1, [StrObject(reason)],
                              EMPTY_MAP)
        self.cleanup()

    def cleanup(self):
        if not self._closed:
            # Flush, in case we have any last words.
            self.flush()
            self._closed = True
            # Release the drain. They should have released us as well.
            self._drain = None
            # Stop reading.
            ruv.readStop(self.stream)
            # And, finally, close and reap the stream.
            # print "active" if ruv.isActive(self.stream) else "inactive"
            # print "closing" if ruv.isClosing(self.stream) else "not closing"
            if not ruv.isClosing(self.stream):
                ruv.closeAndFree(self.stream)

    def pause(self):
        # uv_read_stop() is idempotent.
        ruv.readStop(self.stream)
        self._reading = False
        self.pauses += 1
        return StreamUnpauser(self)

    def unpause(self):
        self.pauses -= 1
        self.considerFlush()

    def receive(self, buf):
        self.bufs.append(buf)
        self.considerFlush()

    def considerFlush(self):
        if not self.pauses and self._drain is not None:
            if not self._reading:
                try:
                    ruv.readStart(self.stream, ruv.allocCB, readCB)
                except ruv.UVError as uve:
                    raise userError(u"StreamFount couldn't read: %s" %
                                    uve.repr().decode("utf-8"))
                self._reading = True
            from typhon.objects.collections.maps import EMPTY_MAP
            self.vat.sendOnly(self, FLUSH_0, [], EMPTY_MAP)

    @method.py("Void")
    def flush(self):
        # We are running in vat scope.
        for i, buf in enumerate(self.bufs):
            # During this loop, the drain might pause us, which we'll respect.
            if self.pauses or self._drain is None:
                # Keep any non-flushed bufs.
                self.bufs = self.bufs[i:]
                break
            rv = BytesObject(buf)
            self._drain.call(u"receive", [rv])
        else:
            # We wrote out everything successfully!
            self.bufs = []


def writeCB(uv_write, status):
    vat, sb = ruv.unstashWrite(uv_write)
    sb.deallocate()


@autohelp
class StreamDrain(Object):
    """
    A drain which sends received data out on a stream.
    """

    _closed = False

    @specialize.call_location()
    def __init__(self, stream, vat):
        # I hate C.
        self.stream = ruv.rffi.cast(ruv.stream_tp, stream)
        self.vat = vat

    def toString(self):
        return u"<StreamDrain>"

    @method("Any", "Any")
    def flowingFrom(self, fount):
        return self

    @method("Void", "Any")
    def receive(self, data):
        if self._closed:
            raise userError(u"Can't send data to a closed stream!")

        if data is NullObject:
            # Pump-style notification that we're supposed to close.
            self.flush()
            self.cleanup()
            return

        # XXX we are punting completely on any notion of backpressure for
        # now. How to fix:
        # * Figure out how to get libuv to signal that a write is likely
        #   to complete

        data = unwrapBytes(data)
        uv_write = ruv.alloc_write()
        sb = ruv.scopedBufs([data], self)
        bufs = sb.allocate()
        ruv.stashWrite(uv_write, (self.vat, sb))
        ruv.write(uv_write, self.stream, bufs, 1, writeCB)

    @method("Void", "Any")
    def flowAborted(self, unused):
        self.cleanup()

    @method("Void", "Any")
    def flowStopped(self, unused):
        # XXX flush() is currently a no-op, but that's not right for the
        # case where there's pending data.
        self.flush()
        self.cleanup()

    def cleanup(self):
        if not self._closed:
            self._closed = True
            # Finally, close and reap the stream.
            # print "active" if ruv.isActive(self.stream) else "inactive"
            # print "closing" if ruv.isClosing(self.stream) else "not closing"
            if not ruv.isClosing(self.stream):
                ruv.closeAndFree(self.stream)

    @method.py("Void")
    def flush(self):
        pass
