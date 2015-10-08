# Copyright (C) 2015 Google Inc. All rights reserved.
#
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

import os

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import scoped_alloc
from rpython.rtyper.lltypesystem.rffi import charpsize2str

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapBytes, unwrapStr
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat, scopedVat


ABORTFLOW_0 = getAtom(u"abortFlow", 0)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
FLOWTO_1 = getAtom(u"flowTo", 1)
GETCONTENTS_0 = getAtom(u"getContents", 0)
OPENDRAIN_0 = getAtom(u"openDrain", 0)
OPENFOUNT_0 = getAtom(u"openFount", 0)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
SETCONTENTS_1 = getAtom(u"setContents", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


@autohelp
class FileUnpauser(Object):
    """
    A pause on a file fount.
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


def readCB(fs):
    # Does *not* invoke user code.
    try:
        vat, fount = ruv.unstashFS(fs)
        assert isinstance(fount, FileFount)
        size = intmask(fs.c_result)
        if size > 0:
            data = charpsize2str(fount.buf.c_base, size)
            fount.receive(data)
        elif size < 0:
            msg = ruv.formatError(size).decode("utf-8")
            fount.abort(u"libuv error: %s" % msg)
        else:
            fount.stop(u"End of file")
    except:
        print "Exception in readCB"


def closeCB(fs):
    pass


@autohelp
class FileFount(Object):
    """
    A fount for a file.
    """

    pauses = 0
    pos = 0

    def __init__(self, fs, fd, vat):
        self.fs = fs
        self.fd = fd
        self.vat = vat

        # XXX read size should be tunable
        self.buf = ruv.allocBuf(16384)

    def recv(self, atom, args):
        if atom is FLOWTO_1:
            self.drain = drain = args[0]
            rv = drain.call(u"flowingFrom", [self])
            self.queueRead()
            return rv

        if atom is PAUSEFLOW_0:
            return self.pause()

        if atom is STOPFLOW_0:
            self.stop(u"stopFlow() called")
            return NullObject

        if atom is ABORTFLOW_0:
            self.abort(u"abortFlow() called")
            return NullObject

        raise Refused(self, atom, args)

    def stop(self, reason):
        from typhon.objects.collections import EMPTY_MAP
        self.vat.sendOnly(self.drain, FLOWSTOPPED_1, [StrObject(reason)],
                          EMPTY_MAP)
        self.close()

    def abort(self, reason):
        from typhon.objects.collections import EMPTY_MAP
        self.vat.sendOnly(self.drain, FLOWABORTED_1, [StrObject(reason)],
                          EMPTY_MAP)
        self.close()

    def close(self):
        uv_loop = self.vat.uv_loop
        ruv.fsClose(uv_loop, self.fs, self.fd, closeCB)
        ruv.freeBuf(self.buf)
        self.drain = None

    def pause(self):
        self.pauses += 1
        return FileUnpauser(self)

    def unpause(self):
        self.pauses -= 1
        if not self.pauses:
            self.queueRead()

    def queueRead(self):
        ruv.stashFS(self.fs, (self.vat, self))
        with scoped_alloc(ruv.rffi.CArray(ruv.buf_t), 1) as bufs:
            bufs[0].c_base = self.buf.c_base
            bufs[0].c_len = self.buf.c_len
            ruv.fsRead(self.vat.uv_loop, self.fs, self.fd, bufs, 1, self.pos,
                       readCB)

    def receive(self, data):
        from typhon.objects.collections import EMPTY_MAP
        # Advance the file pointer.
        self.pos += len(data)
        self.vat.sendOnly(self.drain, RECEIVE_1, [BytesObject(data)],
                          EMPTY_MAP)
        self.queueRead()


def writeCB(fs):
    try:
        vat, drain = ruv.unstashFS(fs)
        assert isinstance(drain, FileDrain)
        size = intmask(fs.c_result)
        if size > 0:
            drain.written(size)
        elif size < 0:
            msg = ruv.formatError(size).decode("utf-8")
            drain.abort(u"libuv error: %s" % msg)
    except:
        print "Exception in writeCB"


@autohelp
class FileDrain(Object):
    """
    A drain for a file.
    """

    fount = None
    pos = 0
    writing = False

    def __init__(self, fs, fd, vat):
        self.fs = fs
        self.fd = fd
        self.vat = vat

        self.bufs = []

    def recv(self, atom, args):
        if atom is FLOWINGFROM_1:
            self.fount = args[0]
            return self

        if atom is RECEIVE_1:
            data = unwrapBytes(args[0])

            self.bufs.append(data)

            if not self.writing:
                # We're not writing right now, so queue a write.
                ruv.stashFS(self.fs, (self.vat, self))
                with ruv.scopedBufs(self.bufs) as bufs:
                    ruv.fsWrite(self.vat.uv_loop, self.fs, self.fd, bufs,
                                len(self.bufs), self.pos, writeCB)

            return NullObject

        if atom is FLOWSTOPPED_1:
            ruv.fsClose(self.vat.uv_loop, self.fs, self.fd, closeCB)
            return NullObject

        if atom is FLOWABORTED_1:
            ruv.fsClose(self.vat.uv_loop, self.fs, self.fd, closeCB)
            return NullObject

        raise Refused(self, atom, args)

    def abort(self, reason):
        print "Aborting file drain:", reason
        if self.fount is not None:
            with scopedVat(self.vat):
                from typhon.objects.collections import EMPTY_MAP
                self.vat.sendOnly(self.fount, ABORTFLOW_0, [], EMPTY_MAP)

    def written(self, size):
        self.pos += size
        bufs = []
        for buf in self.bufs:
            if size >= len(buf):
                size -= len(buf)
            elif size == 0:
                bufs.append(buf)
            else:
                assert size >= 0
                bufs.append(buf[size:])
                size = 0
        self.bufs = bufs


def openFountCB(fs):
    # Does *not* run user-level code. The scoped vat is only for promise
    # resolution.
    try:
        fd = intmask(fs.c_result)
        vat, r = ruv.unstashFS(fs)
        assert isinstance(r, LocalResolver)
        with scopedVat(vat):
            if fd < 0:
                msg = ruv.formatError(fd).decode("utf-8")
                r.smash(StrObject(u"Couldn't open file fount: %s" % msg))
            else:
                r.resolve(FileFount(fs, fd, vat))
    except:
        print "Exception in openFountCB"

def openDrainCB(fs):
    # As above.
    try:
        fd = intmask(fs.c_result)
        vat, r = ruv.unstashFS(fs)
        assert isinstance(r, LocalResolver)
        with scopedVat(vat):
            if fd < 0:
                msg = ruv.formatError(fd).decode("utf-8")
                r.smash(StrObject(u"Couldn't open file drain: %s" % msg))
            else:
                r.resolve(FileDrain(fs, fd, vat))
    except:
        print "Exception in openDrainCB"


@autohelp
class FileResource(Object):
    """
    A Resource which provides access to the file system of the current
    process.
    """

    # For help understanding this class, consult FilePath, the POSIX
    # standards, and a bottle of your finest and strongest liquor. Perhaps not
    # in that order, though.

    _immutable_ = True

    def __init__(self, path):
        self.path = path

    def recv(self, atom, args):
        # XXX this is racy.
        # if atom is GETCONTENTS_0:
        #     p, r = makePromise()
        #     vat = currentVat.get()
        #     uv_loop = vat.uv_loop
        #     fs = ruv.alloc_fs()

        #     fd = ruv.fsOpen(uv_loop, fs, self.path, 0, os.O_RDONLY, None)
        #     # XXX Ugh. We're going to stat() and then read from however large
        #     # the stat() was. This is probably racy in a fundamental way.
        #     ruv.fsRead(uv_loop, fs,
        #     r.resolve()
        #     return p

        # XXX lots of effort, no users in mast yet
        # if atom is SETCONTENTS_1:
        #     data = unwrapBytes(args[0])

        #     p, r = makePromise()
        #     vat = currentVat.get()
        #     vat.afterTurn(SetContents(self.path, data, r))
        #     return p

        if atom is OPENFOUNT_0:
            p, r = makePromise()
            vat = currentVat.get()
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (vat, r))
            ruv.fsOpen(vat.uv_loop, fs, self.path, os.O_RDONLY, 0,
                       openFountCB)
            return p

        if atom is OPENDRAIN_0:
            p, r = makePromise()
            vat = currentVat.get()
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (vat, r))
            # Create the file if it doesn't yet exist, and truncate it if it
            # does. Trust the umask to be reasonable for now.
            flags = os.O_CREAT | os.O_WRONLY
            # XXX this behavior should be configurable via namedarg?
            flags |= os.O_TRUNC
            ruv.fsOpen(vat.uv_loop, fs, self.path, flags, 0777, openDrainCB)
            return p

        raise Refused(self, atom, args)


@runnable(RUN_1)
def makeFileResource(args):
    """
    Make a file Resource.
    """

    path = unwrapStr(args[0]).encode("utf-8")
    return FileResource(path)
