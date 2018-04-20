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

from rpython.rlib.objectmodel import specialize
from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import scoped_alloc
from rpython.rtyper.lltypesystem.rffi import charpsize2str

from typhon import log, rsodium, ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.futures import FutureCtx, FutureCallback, resolve, Ok, Err, Break, Continue, LOOP_BREAK, LOOP_CONTINUE, OK, smash
from typhon.macros import macros, io#, io_loop
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapStr
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat, scopedVat


ABORTFLOW_0 = getAtom(u"abortFlow", 0)
FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_1 = getAtom(u"run", 1)


@autohelp
class FileUnpauser(Object):
    """
    A pause on a file fount.
    """

    def __init__(self, fount):
        self.fount = fount

    @method("Void")
    def unpause(self):
        if self.fount is not None:
            self.fount.unpause()
            # Let go so that the fount can be GC'd if necessary.
            self.fount = None


def renameCB(fs):
    try:
        success = intmask(fs.c_result)
        vat, r = ruv.unstashFS(fs)
        if success < 0:
            msg = ruv.formatError(success).decode("utf-8")
            r.smash(StrObject(u"Couldn't rename file: %s" % msg))
        else:
            r.resolve(NullObject)
        ruv.fsDiscard(fs)
    except:
        print "Exception in renameCB"


class SetContents(Object):

    pos = 0

    def __init__(self, vat, data, resolver, src, dest):
        self.vat = vat
        self.data = data
        self.resolver = resolver
        self.src = src
        self.dest = dest

    def fail(self, reason):
        self.resolver.smash(StrObject(reason))

    def queueWrite(self):
        fs = ruv.alloc_fs()
        sb = ruv.scopedBufs([self.data], self)
        bufs = sb.allocate()
        ruv.stashFS(fs, (self.vat, sb))
        ruv.fsWrite(self.vat.uv_loop, fs, self.fd, bufs,
                    1, -1, writeSetContentsCB)

    def startWriting(self, fd):
        self.fd = fd
        self.queueWrite()

    def written(self, size):
        self.pos += size
        self.data = self.data[size:]
        if self.data:
            self.queueWrite()
        else:
            # Finished writing; let's move on to the rename.
            fs = ruv.alloc_fs()
            ruv.stashFS(fs, (self.vat, self))
            ruv.fsClose(self.vat.uv_loop, fs, self.fd,
                        closeSetContentsCB)

    def rename(self):
        # And issuing the rename is surprisingly straightforward.
        p = self.src.rename(self.dest.asBytes())
        self.resolver.resolve(p)


def openSetContentsCB(fs):
    try:
        fd = intmask(fs.c_result)
        vat, sc = ruv.unstashFS(fs)
        assert isinstance(sc, SetContents)
        if fd < 0:
            msg = ruv.formatError(fd).decode("utf-8")
            sc.fail(u"Couldn't open file fount: %s" % msg)
        else:
            sc.startWriting(fd)
        ruv.fsDiscard(fs)
    except:
        print "Exception in openSetContentsCB"


def writeSetContentsCB(fs):
    try:
        vat, sb = ruv.unstashFS(fs)
        sc = sb.obj
        assert isinstance(sc, SetContents)
        size = intmask(fs.c_result)
        if size >= 0:
            sc.written(size)
        else:
            msg = ruv.formatError(size).decode("utf-8")
            sc.fail(u"libuv error: %s" % msg)
        ruv.fsDiscard(fs)
        sb.deallocate()
    except:
        print "Exception in writeSetContentsCB"


def closeSetContentsCB(fs):
    try:
        vat, sc = ruv.unstashFS(fs)
        # Need to scope vat here.
        with scopedVat(vat):
            assert isinstance(sc, SetContents)
            size = intmask(fs.c_result)
            if size < 0:
                msg = ruv.formatError(size).decode("utf-8")
                sc.fail(u"libuv error: %s" % msg)
            else:
                # Success.
                sc.rename()
        ruv.fsDiscard(fs)
    except:
        print "Exception in closeSetContentsCB"


def readLoopCore(state, data):
    if data == "":
        return Break("".join(state.pieces))
    else:
        state.pieces.append(data)
        state.pos += len(data)
        return Continue()


class _State1(FutureCtx):
    def __init__(_1, vat, future, buf, pieces, pos, outerState, k):
        _1.vat = vat
        _1.future1 = future
        _1.buf = buf
        _1.pieces = pieces
        _1.pos = pos
        _1.outerState = outerState
        _1.k1 = k


class ReadLoop_K0(ruv.FSReadFutureCallback):
    def do(self, state, result):
        (inStatus, data, inErr) = result
        if inStatus != OK:
            return state.k1.do(state.outerState, result)
        (status, output, err) = readLoopCore(state, data)
        if status == LOOP_CONTINUE:
            state.future1.run(state, readLoop_k0)
        elif status == LOOP_BREAK:
            state.k1.do(state.outerState, Ok(output))
        else:
            raise ValueError(status)


readLoop_k0 = ReadLoop_K0()


class readLoop(object):
    callbackType = ruv.FSReadFutureCallback

    def __init__(self, f, buf):
        self.f = f
        self.buf = buf

    def run(self, state, k):
        ruv.magic_fsRead(state.vat, self.f, self.buf).run(
            _State1(state.vat, self, self.buf, [], 0, state, k),
            readLoop_k0)


class _State2(FutureCtx):
    def __init__(_2, vat, future, outerState, k):
        _2.vat = vat
        _2.future2 = future
        _2.outerState = outerState
        _2.k = k


def writeLoopCore(state, size):

    if state.data:
        return Continue()
    else:
        return Break(None)


class WriteLoop_K0(ruv.FSWriteFutureCallback):
    def do(self, state, result):
        (inStatus, size, inErr) = result
        if inStatus != OK:
            state.k.do(state.outerState, result)
        state.data = state.data[size:]
        if state.data:
            state.future2.run(state, writeLoop_k0)
        else:
            state.k.do(state.outerState, Ok(0))


writeLoop_k0 = WriteLoop_K0()


class writeLoop(object):
    callbackType = ruv.FSWriteFutureCallback

    def __init__(self, f, data):
        self.f = f
        self.data = data

    def run(self, state, k):
        ruv.magic_fsWrite(state.vat, self.f, self.data).run(
            _State2(state.vat, self, state, k),
            writeLoop_k0)


@autohelp
class FileResource(Object):
    """
    A Resource which provides access to the file system of the current
    process.
    """

    # For help understanding this class, consult FilePath, the POSIX
    # standards, and a bottle of your finest and strongest liquor. Perhaps not
    # in that order, though.

    _immutable_fields_ = "segments[*]",

    def __init__(self, segments):
        self.segments = segments

    def toString(self):
        return u"<file resource %s>" % self.asBytes().decode("utf-8")

    def asBytes(self):
        return "/".join(self.segments)


    def rename(self, dest):
        p, r = makePromise()
        vat = currentVat.get()
        uv_loop = vat.uv_loop
        fs = ruv.alloc_fs()

        src = self.asBytes()
        ruv.stashFS(fs, (vat, r))
        ruv.fsRename(uv_loop, fs, src, dest, renameCB)
        return p

    def sibling(self, segment):
        return FileResource(self.segments[:-1] + [segment])

    def temporarySibling(self, suffix):
        fileName = rsodium.randomHex() + suffix
        return self.sibling(fileName)

    @method("Any")
    def getContents(self):
        p, r = makePromise()
        vat = currentVat.get()
        buf = ruv.allocBuf(16384)
        path = self.asBytes()
        log.log(["fs"], u"makeFileResource: Opening file '%s'" % path.decode("utf-8"))
        with io:
            f = 0
            try:
                f = ruv.magic_fsOpen(vat, path, os.O_RDONLY, 0000)
            except object as err:
                smash(r, StrObject(u"Couldn't open file fount: %s" % err))
            else:
                try:
                    contents = readLoop(f, buf)
                except object as err:
                    ruv.magic_fsClose(vat, f)
                    smash(r, StrObject(u"libuv error: %s" % err))
                else:
                    ruv.magic_fsClose(vat, f)
                    resolve(r, BytesObject(contents))
        return p

    @method("Any", "Bytes")
    def setContents(self, data):
        sibling = self.temporarySibling(".setContents")

        p, r = makePromise()
        vat = currentVat.get()
        path = sibling.asBytes()
        # Use CREAT | EXCL to cause a failure if the temporary file
        # already exists.
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        with io:
            f = 0
            try:
                f = ruv.magic_fsOpen(vat, path, flags, 0777)
            except object as err:
                smash(r, StrObject(u"Couldn't open file fount: %s" % err))
            else:
                try:
                    writeLoop(f, data)
                except object as err:
                    ruv.magic_fsClose(vat, f)
                    smash(r, StrObject(u"libuv error: %s" % err))
                else:
                    ruv.magic_fsClose(vat, f)
                    ruv.magic_fsRename(vat, self.asBytes(), sibling.asBytes())
                    resolve(r, NullObject)
        return p

    @method("Any", "Any", _verb="rename")
    def _rename(self, fr):
        if not isinstance(fr, FileResource):
            raise userError(u"rename/1: Must be file resource")
        return self.rename(fr.asBytes())

    @method("Any", "Str", _verb="sibling")
    def _sibling(self, name):
        if u'/' in name:
            raise userError(u"sibling/1: Illegal file name '%s'" % name)
        return self.sibling(name.encode("utf-8"))

    @method("Any", _verb="temporarySibling")
    def _temporarySibling(self):
        return self.temporarySibling(".new")


@runnable(RUN_1)
def makeFileResource(path):
    """
    Make a file Resource.
    """

    path = unwrapStr(path)
    segments = [segment.encode("utf-8") for segment in path.split(u'/')]
    if not path.startswith(u'/'):
        # Relative path.
        segments = os.getcwd().split('/') + segments
        log.log(["fs"], u"makeFileResource.run/1: Relative path '%s'" % path)
    return FileResource(segments)
