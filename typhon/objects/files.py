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
import stat

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem.lltype import nullptr

from typhon import log, rsodium, ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.futures import FutureCtx, resolve, Ok, Break, Continue, LOOP_BREAK, LOOP_CONTINUE, OK, smash
from typhon.macros import macros, io
from typhon.objects.constants import NullObject
from typhon.objects.data import BytesObject, StrObject, unwrapStr
from typhon.objects.refs import makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


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

    if state.future2.data:
        return Continue()
    else:
        return Break(None)


class WriteLoop_K0(ruv.FSWriteFutureCallback):
    def do(self, state, result):
        (inStatus, size, inErr) = result
        if inStatus != OK:
            state.k.do(state.outerState, result)
        state.future2.data = state.future2.data[size:]
        if state.future2.data:
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


fileTypes = {
    stat.S_IFSOCK: u"socket",
    stat.S_IFLNK:  u"symbolic link",
    stat.S_IFREG:  u"regular file",
    stat.S_IFBLK:  u"block device",
    stat.S_IFDIR:  u"directory",
    stat.S_IFCHR:  u"character device",
    stat.S_IFIFO:  u"named pipe",
}

def packTime(timespec):
    return timespec.c_tv_sec + (timespec.c_tv_nsec / 1000000000)

@autohelp
class FileStatistics(Object):
    """
    Information about an object on the filesystem.
    """

    _immutable_fields_ = (
            "major", "minor", "st_mode", "type", "hardLinks", "user", "group",
            "inode", "size", "blockSize", "aTime", "mTime", "cTime",
    )

    def __init__(self, lstat):
        # This is what glibc does.
        st_dev = lstat.c_st_dev
        self.major = intmask(((st_dev >> 8) & 0xfff) |
                             ((st_dev >> 32) & ~0xfff))
        self.minor = intmask(((st_dev >> 0) & 0xff) |
                             ((st_dev >> 12) & ~0xff))

        self.st_mode = intmask(lstat.c_st_mode)
        self.type = fileTypes.get(stat.S_IFMT(self.st_mode),
                                  u"unknown file type")
        self.hardLinks = intmask(lstat.c_st_nlink)
        self.user = intmask(lstat.c_st_uid)
        self.group = intmask(lstat.c_st_gid)
        # ...
        self.inode = intmask(lstat.c_st_ino)
        self.size = intmask(lstat.c_st_size)
        self.blockSize = intmask(lstat.c_st_blksize)
        # self.blocks = intmask(lstat.c_st_blocks)
        self.aTime = packTime(lstat.c_st_atim)
        self.mTime = packTime(lstat.c_st_mtim)
        self.cTime = packTime(lstat.c_st_ctim)
        # ...

    def toString(self):
        return u"<%s %d on device %d:%d>" % (self.type, self.inode,
                                             self.major, self.minor)

    @method("Int")
    def deviceClass(self):
        "The device class, or major ID."
        return self.major

    @method("Int")
    def deviceInstance(self):
        "The device instance, or minor ID."
        return self.minor

    @method("Str")
    def fileType(self):
        """
        The file type.

        Known file types include "socket", "symbolic link", "regular file",
        "block device", "directory", "character device", and "named pipe".
        """
        return self.type

    @method("Bool")
    def runsAsUser(self):
        """
        Whether executing this file would run the resulting process as this
        file's user.

        Note that it is possible for this file to be marked to run as user
        even if it is not actually executable.
        """
        return bool(self.st_mode & stat.S_ISUID)

    @method("Bool")
    def runsAsGroup(self):
        """
        Whether executing this file would run the resulting process as this
        file's group.
        """
        return bool(self.st_mode & stat.S_ISGID) and bool(self.st_mode & stat.S_IXGRP)

    @method("Bool")
    def mandatesLocking(self):
        """
        Whether this file is locked with a mandatory lock upon access.
        """
        return bool(self.st_mode & stat.S_ISGID) and not bool(self.st_mode & stat.S_IXGRP)

    @method("Bool")
    def isSticky(self):
        """
        Whether this file's permissions are sticky.
        """
        return bool(self.st_mode & stat.S_ISVTX)

    @method("Bool")
    def ownerMayRead(self):
        "Whether the owner has read permission."
        return bool(self.st_mode & stat.S_IRUSR)

    @method("Bool")
    def ownerMayWrite(self):
        "Whether the owner has write permission."
        return bool(self.st_mode & stat.S_IWUSR)

    @method("Bool")
    def ownerMayExecute(self):
        "Whether the owner has execute permission."
        return bool(self.st_mode & stat.S_IXUSR)

    @method("Bool")
    def groupMayRead(self):
        "Whether the group has read permission."
        return bool(self.st_mode & stat.S_IRGRP)

    @method("Bool")
    def groupMayWrite(self):
        "Whether the group has write permission."
        return bool(self.st_mode & stat.S_IWGRP)

    @method("Bool")
    def groupMayExecute(self):
        "Whether the group has execute permission."
        return bool(self.st_mode & stat.S_IXGRP)

    @method("Bool")
    def othersMayRead(self):
        "Whether others have read permission."
        return bool(self.st_mode & stat.S_IROTH)

    @method("Bool")
    def othersMayWrite(self):
        "Whether others have write permission."
        return bool(self.st_mode & stat.S_IWOTH)

    @method("Bool")
    def othersMayExecute(self):
        "Whether others have execute permission."
        return bool(self.st_mode & stat.S_IXOTH)

    @method("Int")
    def hardLinks(self):
        "The number of hard links."
        return self.hardLinks

    @method("Int")
    def user(self):
        "The owning user ID."
        return self.user

    @method("Int")
    def group(self):
        "The owning group ID."
        return self.group

    # uint64_t st_rdev;

    @method("Int")
    def indexNode(self):
        "The index node ('inode') ID."
        return self.inode

    @method("Int", _verb="size")
    def _size(self):
        "The size."
        return self.size

    @method("Int", _verb="blockSize")
    def _blockSize(self):
        "The preferred block size."
        return self.blockSize

    # uint64_t st_blocks;
    # uint64_t st_flags;
    # uint64_t st_gen;

    @method("Double")
    def accessedTime(self):
        "The last time of access."
        return self.aTime

    @method("Double")
    def modifiedTime(self):
        "The last time of modification."
        return self.mTime

    @method("Double")
    def changedTime(self):
        "The last time of metadata change."
        return self.cTime

    # uv_timespec_t st_birthtim;


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
                smash(r, StrObject(u"Couldn't open file fount for %s: %s" % (path.decode("utf-8"), err)))
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
                    ruv.magic_fsRename(vat, path, self.asBytes())
                    resolve(r, NullObject)
        return p

    @method("Any")
    def getStatistics(self):
        p, r = makePromise()
        vat = currentVat.get()
        # Copying a pattern from t.o.networking.dns for appeasing the macro
        # generator. We must not appear to do work on the RHS of an
        # assignment, or we will anger the macro magic. ~ C.
        emptyLStat = nullptr(ruv.stat_t)
        with io:
            lstat = emptyLStat
            try:
                lstat = ruv.magic_fsLStat(vat, self.asBytes())
            except object as err:
                smash(r, StrObject(u"Couldn't stat file: %s" % err))
            else:
                resolve(r, FileStatistics(lstat))
        return p

    @method("Any", "Any")
    def rename(self, fr):
        if not isinstance(fr, FileResource):
            raise userError(u"rename/1: Must be file resource")
        dest = fr.asBytes()
        p, r = makePromise()
        vat = currentVat.get()
        with io:
            try:
                ruv.magic_fsRename(vat, self.asBytes(), dest)
            except object as err:
                smash(r, StrObject(u"Couldn't rename file: %s" % err))
            else:
                resolve(r, NullObject)
        return p

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
