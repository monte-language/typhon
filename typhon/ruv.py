"""
libuv bindings.

I got sick of typing "uv_", so everything is missing it except where
absolutely required. You're welcome.

Import as `from typhon import ruv` and then use namespaced. Please.
"""

import os
import sys

from functools import wraps

from rpython.rlib import _rsocket_rffi as s
from rpython.rlib.objectmodel import (current_object_addr_as_int, specialize,
                                      we_are_translated)
from rpython.rlib.rarithmetic import intmask
from rpython.rlib.rawstorage import alloc_raw_storage, free_raw_storage
from rpython.rlib.rerased import new_erasing_pair
from rpython.rtyper.lltypesystem import lltype, rffi
from rpython.rtyper.tool import rffi_platform
from rpython.translator.tool.cbuild import ExternalCompilationInfo
from typhon.log import log

from typhon.futures import Ok, ERR
from typhon.objects.root import Object


class UVError(Exception):
    """
    libuv was unhappy.
    """

    def __init__(self, status, message):
        self.status = status
        self.message = message

    def repr(self):
        return "%s: %s" % (self.message, formatError(self.status))

    __repr__ = repr


def formatError(code):
    return "%s (%s)" % (rffi.charp2str(uv_strerror(code)),
                        rffi.charp2str(uv_err_name(code)))


def check(message, rv):
    rv = intmask(rv)
    if rv < 0:
        uve = UVError(rv, message)
        log(["uv", "error"],
            u"libuv API error: %s" % uve.repr().decode("utf-8"))
        raise uve
    return rv


@specialize.arg(0)
def checking(message, f):
    @wraps(f)
    def checker(*args):
        return check(message, intmask(f(*args)))
    return checker


def envPaths(name):
    val = os.getenv(name)
    if val is None:
        return []
    else:
        return val.split(':')


libs = ["uv"]
# Issue 96: Darwin: Don't add nsl. ~ C.
# ...or rt. ~ cdunklau
if not sys.platform.startswith("darwin"):
    libs.extend(["nsl", "rt"])
eci = ExternalCompilationInfo(includes=["uv.h"],
                              include_dirs=envPaths("TYPHON_INCLUDE_PATH"),
                              library_dirs=envPaths("TYPHON_LIBRARY_PATH"),
                              libraries=libs)


class CConfig:
    _compilation_info_ = eci

    loop_t = rffi_platform.Struct("uv_loop_t", [("data", rffi.VOIDP)])
    handle_t = rffi_platform.Struct("uv_handle_t", [("data", rffi.VOIDP)])
    timer_t = rffi_platform.Struct("uv_timer_t", [("data", rffi.VOIDP)])
    prepare_t = rffi_platform.Struct("uv_prepare_t", [("data", rffi.VOIDP)])
    idle_t = rffi_platform.Struct("uv_idle_t", [("data", rffi.VOIDP)])
    process_options_t = rffi_platform.Struct(
        "uv_process_options_t", [
            ("file", rffi.CCHARP),
            ("args", rffi.CCHARPP),
            ("env", rffi.CCHARPP),
            ("cwd", rffi.CCHARP),
            ("flags", rffi.UINT),
            ("stdio_count", rffi.INT),
            ("stdio", lltype.Ptr(lltype.ForwardReference()))])
    stdio_container_t = rffi_platform.Struct("uv_stdio_container_t",
                                             [("flags", rffi.INT)])
    process_t = rffi_platform.Struct("uv_process_t",
                                     [("data", rffi.VOIDP),
                                      ("pid", rffi.INT)])
    connect_t = rffi_platform.Struct("uv_connect_t",
                                     [("handle",
                                       lltype.Ptr(lltype.ForwardReference()))])
    stream_t = rffi_platform.Struct("uv_stream_t", [("data", rffi.VOIDP)])
    shutdown_t = rffi_platform.Struct("uv_shutdown_t", [])
    write_t = rffi_platform.Struct("uv_write_t", [("data", rffi.VOIDP)])
    tcp_t = rffi_platform.Struct("uv_tcp_t", [("data", rffi.VOIDP)])
    pipe_t = rffi_platform.Struct("uv_pipe_t", [("data", rffi.VOIDP)])
    signal_t = rffi_platform.Struct("uv_signal_t", [("data", rffi.VOIDP)])
    tty_t = rffi_platform.Struct("uv_tty_t", [("data", rffi.VOIDP)])
    fs_t = rffi_platform.Struct("uv_fs_t",
                                [("data", rffi.VOIDP),
                                 ("path", rffi.CONST_CCHARP),
                                 ("result", rffi.SSIZE_T),
                                 ("ptr", rffi.VOIDP)])
    getaddrinfo_t = rffi_platform.Struct("uv_getaddrinfo_t",
                                         [("data", rffi.VOIDP)])
    buf_t = rffi_platform.Struct("uv_buf_t",
                                 [("base", rffi.CCHARP),
                                  ("len", rffi.SIZE_T)])

# I know, weird nomenclature. Not my fault. I'm just copying what other
# RPython code does. ~ C.
cConfig = rffi_platform.configure(CConfig)

loop_tp = lltype.Ptr(cConfig["loop_t"])
handle_tp = lltype.Ptr(cConfig["handle_t"])
timer_tp = rffi.lltype.Ptr(cConfig["timer_t"])
prepare_tp = rffi.lltype.Ptr(cConfig["prepare_t"])
idle_tp = rffi.lltype.Ptr(cConfig["idle_t"])
process_options_tp = rffi.lltype.Ptr(cConfig["process_options_t"])
stdio_container_t = cConfig["stdio_container_t"]
stdio_container_tp = rffi.lltype.Ptr(cConfig["stdio_container_t"])
process_tp = rffi.lltype.Ptr(cConfig["process_t"])
stream_t = cConfig["stream_t"]
stream_tp = rffi.lltype.Ptr(cConfig["stream_t"])
connect_tp = rffi.lltype.Ptr(cConfig["connect_t"])
shutdown_tp = rffi.lltype.Ptr(cConfig["shutdown_t"])
write_tp = rffi.lltype.Ptr(cConfig["write_t"])
tcp_tp = rffi.lltype.Ptr(cConfig["tcp_t"])
pipe_tp = rffi.lltype.Ptr(cConfig["pipe_t"])
signal_tp = rffi.lltype.Ptr(cConfig["signal_t"])
tty_tp = rffi.lltype.Ptr(cConfig["tty_t"])
fs_tp = rffi.lltype.Ptr(cConfig["fs_t"])
gai_tp = rffi.lltype.Ptr(cConfig["getaddrinfo_t"])
buf_tp = lltype.Ptr(cConfig["buf_t"])

buf_t = cConfig["buf_t"]
array_buf_t = lltype.Ptr(lltype.Array(buf_t, hints={"nolength": True}))

# Forward references.
cConfig["connect_t"].c_handle.TO.become(cConfig["stream_t"])
cConfig["process_options_t"].c_stdio.TO.become(lltype.Array(
    cConfig["stdio_container_t"], hints={"nolength": True}))


def stashFor(name, struct, initial=None):
    class Stash(object):
        """
        Like a weaklist, but keeps a strong reference to its elements.

        Beware: get and put aren't idempotent. A get will remove the object
        from the stash!

        Asynchronous code is weird, man. If you don't keep strong references,
        then the only references left might be in FFI or libc, which is not
        good. So we can't use weakrefs here.
        """

        def __init__(self, initialSize=4):
            self.freeList = range(initialSize)
            self.storage = [(None, initial)] * initialSize

        def get(self, index):
            assert index not in self.freeList, "stash: Double get()"
            rv = self.storage[index]
            # Zero out the reference in storage so that the object doesn't live
            # too long.
            self.storage[index] = None, initial
            self.freeList.append(index)
            return rv

        def put(self, obj):
            index = self.reserve()
            self.storage[index] = obj
            return index

        def reserve(self):
            # Similar to rpython.rlib.rweaklist.

            # Fast: Try the free list.
            try:
                return self.freeList.pop()
            except IndexError:
                pass

            # Bogus. Slow: Reallocate storage.
            extraSize = len(self.storage)
            newStorage = self.storage + [(None, initial)] * extraSize
            self.freeList.extend(range(extraSize, extraSize * 2))
            self.storage = newStorage
            # We just extended freeList, so this should always be safe.
            return self.freeList.pop()

    theStash = Stash()

    def stash(uv_t, obj):
        # uv_t = rffi.cast(struct, uv_t)
        index = theStash.put(obj)
        uv_t.c_data = rffi.cast(rffi.VOIDP, index)
        log(["uv"], u"Stash %s: Storing 0x%x to %d (0x%x)" %
                    (name.decode("utf-8"), current_object_addr_as_int(obj),
                     intmask(index), current_object_addr_as_int(uv_t)))

    def unstash(uv_t):
        # uv_t = rffi.cast(struct, uv_t)
        index = rffi.cast(rffi.INT, uv_t.c_data)
        obj = theStash.get(index)
        log(["uv"], u"Stash %s: Getting 0x%x from %d (0x%x)" %
                    (name.decode("utf-8"), current_object_addr_as_int(obj),
                     intmask(index), current_object_addr_as_int(uv_t)))
        return obj

    class unstashing(object):

        def __init__(self, uv_t):
            self.uv_t = uv_t

        def __enter__(self):
            self.unstashed = unstash(self.uv_t)
            return self.unstashed

        def __exit__(self, *args):
            stash(self.uv_t, self.unstashed)

    return stash, unstash, unstashing

stashTimer, unstashTimer, unstashingTimer = stashFor(
    "timer", timer_tp, initial=(None, 0))
stashStream, unstashStream, unstashingStream = stashFor("stream", stream_tp)
stashWrite, unstashWrite, unstashingWrite = stashFor("write", write_tp)
stashFS, unstashFS, unstashingFS = stashFor("fs", fs_tp)
stashGAI, unstashGAI, unstashingGAI = stashFor("gai", gai_tp)
stashProcess, unstashProcess, unstashingProcess = stashFor("process",
                                                           process_tp)
stashSignal, unstashSignal, unstashingSignal = stashFor("signal", signal_tp)


@specialize.ll()
def free(struct):
    # This is how to free nearly everything. Only some specific things need
    # teardown before freeing.
    lltype.free(struct, flavor="raw")


uv_strerror = rffi.llexternal("uv_strerror", [rffi.INT], rffi.CCHARP,
                              compilation_info=eci)
uv_err_name = rffi.llexternal("uv_err_name", [rffi.INT], rffi.CCHARP,
                              compilation_info=eci)

walk_cb = rffi.CCallback([handle_tp, rffi.VOIDP], lltype.Void)

loop_init = rffi.llexternal("uv_loop_init", [loop_tp], rffi.INT,
                            compilation_info=eci)
loop_close = rffi.llexternal("uv_loop_close", [loop_tp], rffi.INT,
                             compilation_info=eci)
loopClose = checking("loop_close", loop_close)
loop_alive = rffi.llexternal("uv_loop_alive", [loop_tp], rffi.INT,
                             compilation_info=eci)


def loopAlive(loop):
    return bool(intmask(loop_alive(loop)))

loop_size = rffi.llexternal("uv_loop_size", [], rffi.SIZE_T,
                            compilation_info=eci)
default_loop = rffi.llexternal("uv_default_loop", [], loop_tp,
                               compilation_info=eci)
uv_run = rffi.llexternal("uv_run", [loop_tp, rffi.INT], rffi.INT,
                         compilation_info=eci)
run = checking("run", uv_run)
now = rffi.llexternal("uv_now", [loop_tp], rffi.ULONGLONG,
                      compilation_info=eci)
update_time = rffi.llexternal("uv_update_time", [loop_tp], lltype.Void,
                              compilation_info=eci)
walk = rffi.llexternal("uv_walk", [loop_tp, walk_cb, rffi.VOIDP], lltype.Void,
                       compilation_info=eci)


def alloc_loop():
    loop = lltype.malloc(cConfig["loop_t"], flavor="raw", zero=True)
    check("loop_init", loop_init(loop))
    return loop

RUN_DEFAULT, RUN_ONCE, RUN_NOWAIT = range(3)


alloc_cb = rffi.CCallback([handle_tp, rffi.SIZE_T, buf_tp], lltype.Void)
close_cb = rffi.CCallback([handle_tp], lltype.Void)


def allocBuf(size):
    buf = lltype.malloc(cConfig["buf_t"], flavor="raw", zero=True)
    buf.c_base = alloc_raw_storage(size)
    rffi.setintfield(buf, "c_len", size)
    return buf


def freeBuf(buf):
    free_raw_storage(buf.c_base)
    free(buf)


def allocCB(handle, size, buf):
    # This is almost certainly the right thing to pass to alloc_cb
    buf.c_base = alloc_raw_storage(size)
    rffi.setintfield(buf, "c_len", size)


streamReadStart_erase, streamReadStart_unerase = new_erasing_pair(
    "streamReadStart")


class StreamReadStartFutureCallback(object):
    pass


stashStream2, unstashStream2, unstashingStream2 = stashFor(
    "stream", stream_tp,
    initial=streamReadStart_erase(StreamReadStartFutureCallback()))


def readStreamCB(stream, status, buf):
    status = intmask(status)
    # We only restash in the success case, not the error cases.
    state, v = unstashStream2(stream)
    k = streamReadStart_unerase(v)
    if not k:
        return
    if status == 0:
        # EAGAIN or somesuch, wait til next callback
        return
    # Don't read any more. We'll call readStart() when we're interested in
    # reading again.
    readStop(stream)
    if status > 0:
        data = rffi.charpsize2str(buf.c_base, status)
        k.do(state, Ok(data))
    elif status == -4095:
        k.do(state, Ok(""))
    else:
        msg = formatError(status).decode("utf-8")
        k.do(state, (ERR, "", msg))


class magic_readStart(object):
    callbackType = StreamReadStartFutureCallback

    def __init__(self, stream):
        self.stream = stream

    def run(self, state, k):
        stashStream2(self.stream, (state, streamReadStart_erase(k)))
        readStart(self.stream, allocCB, readStreamCB)


class StreamWriteFutureCallback(object):
    pass


stashWrite2, unstashWrite2, _ = stashFor("write", write_tp)


def writeStreamCB(uv_write, status):
    state, sb = unstashWrite2(uv_write)
    sb.deallocate()
    if sb.k:
        sb.k.do(state, (Ok(0)))


class magic_write(object):
    def __init__(self, stream, data):
        self.stream = stream
        self.data = data

    def run(self, state, k):
        uv_write = alloc_write()
        sb = WriteBuf(self.data, k)
        bufs = sb.allocate()
        stashWrite2(uv_write, (state, sb))
        write(uv_write, self.stream, bufs, 1, writeStreamCB)

class scopedBufs(Object):

    def __init__(self, data, obj):
        self.obj = obj
        self.data = data
        self.scoping = lltype.scoped_alloc(rffi.CArray(buf_t), len(self.data))

    def allocate(self):
        bufs = self.scoping.__enter__()
        self.metabufs = []
        for i, datum in enumerate(self.data):
            # get_nonmovingbuffer tries its hardest to avoid copies. Don't
            # forget that we have to deallocate each one later.
            assert datum is not None
            charp, flag = rffi.get_nonmovingbuffer(datum)
            bufs[i].c_base = charp
            rffi.setintfield(bufs[i], "c_len", len(datum))
            # Store the original strs to keep them alive and make iteration
            # easier later.
            self.metabufs.append((datum, charp, flag))
        return bufs

    def deallocate(self):
        # Deallocate. Can't forget to do this, or else we could fill the
        # GC with pinned crap.
        for datum, charp, flag in self.metabufs:
            rffi.free_nonmovingbuffer(datum, charp, flag)
        self.scoping.__exit__()


(HANDLE_ASYNC, HANDLE_CHECK, HANDLE_FS_EVENT, HANDLE_FS_POLL, HANDLE_HANDLE,
 HANDLE_IDLE, HANDLE_NAMED_PIPE, HANDLE_POLL, HANDLE_PREPARE, HANDLE_PROCESS,
 HANDLE_STREAM, HANDLE_TCP, HANDLE_TIMER, HANDLE_TTY, HANDLE_UDP,
 HANDLE_SIGNAL, HANDLE_FILE) = range(1, 18)

is_active = rffi.llexternal("uv_is_active", [handle_tp], rffi.INT,
                            compilation_info=eci)


@specialize.ll()
def isActive(handleish):
    rv = intmask(is_active(rffi.cast(handle_tp, handleish)))
    return bool(rv)
is_closing = rffi.llexternal("uv_is_closing", [handle_tp], rffi.INT,
                             compilation_info=eci)


def isClosing(handleish):
    rv = intmask(is_closing(rffi.cast(handle_tp, handleish)))
    return bool(rv)
uv_close = rffi.llexternal(
    "uv_close", [handle_tp, close_cb], lltype.Void, compilation_info=eci)


def close(handleish, cb):
    uv_close(rffi.cast(handle_tp, handleish), cb)


def closeAndFree(handleish):
    uv_close(rffi.cast(handle_tp, handleish), closeAndFreeCB)


def closeAndFreeCB(handleish):
    free(handleish)


timer_cb = rffi.CCallback([timer_tp], lltype.Void)

timer_init = rffi.llexternal("uv_timer_init", [loop_tp, timer_tp], rffi.INT,
                             compilation_info=eci)
timer_start = rffi.llexternal("uv_timer_start", [timer_tp, timer_cb,
                                                 rffi.ULONGLONG,
                                                 rffi.ULONGLONG],
                              rffi.INT, compilation_info=eci)
timerStart = checking("timer_start", timer_start)


def alloc_timer(loop):
    timer = lltype.malloc(cConfig["timer_t"], flavor="raw", zero=True)
    check("timer_init", timer_init(loop, timer))
    return timer


prepare_cb = rffi.CCallback([prepare_tp], lltype.Void)

prepare_init = rffi.llexternal("uv_prepare_init", [loop_tp, prepare_tp],
                               rffi.INT, compilation_info=eci)
prepare_start = rffi.llexternal("uv_prepare_start", [prepare_tp, prepare_cb],
                                rffi.INT, compilation_info=eci)
prepare_stop = rffi.llexternal("uv_prepare_stop", [prepare_tp],
                               rffi.INT, compilation_info=eci)


def alloc_prepare():
    return lltype.malloc(cConfig["prepare_t"], flavor="raw", zero=True)


idle_cb = rffi.CCallback([idle_tp], lltype.Void)

idle_init = rffi.llexternal("uv_idle_init", [loop_tp, idle_tp], rffi.INT,
                            compilation_info=eci)
idle_start = rffi.llexternal("uv_idle_start", [loop_tp, idle_tp], rffi.INT,
                             compilation_info=eci)
idleStart = checking("idle_start", idle_start)
idle_stop = rffi.llexternal("uv_idle_stop", [loop_tp], rffi.INT,
                            compilation_info=eci)
idleStop = checking("idle_stop", idle_stop)


def alloc_idle(loop):
    idle = lltype.malloc(cConfig["idle_t"], flavor="raw", zero=True)
    check("idle_init", idle_init(loop, idle))
    return idle


class UVStream(object):
    """
    Wrapper for libuv stream_t structs.

    The primary purpose of this wrapper is to provide finalization services.
    """

    def __init__(self, stream, refCount):
        assert refCount > 0, "vampire"

        self._stream = stream
        self._refCount = refCount

    def release(self):
        self._refCount -= 1
        if not self._refCount:
            streamJanitor.streams.append(self._stream)


class StreamJanitor(object):

    def __init__(self):
        self.streams = []

    def cleanup(self):
        if not self.streams:
            return

        log(["uv"], u"Janitor closing %d streams" % len(self.streams))
        for stream in self.streams:
            closeAndFree(stream)
        self.streams = []

streamJanitor = StreamJanitor()


def wrapStream(stream, refCount):
    wrapper = UVStream(stream, refCount)
    return wrapper


_PROCESS_C = '''
#include <uv.h>

RPY_EXTERN
void
monte_helper_add_exit_cb(uv_process_options_t* options,
                        void (*uv_exit_cb)(uv_process_t*,
                                           int64_t exit_status,
                                           int term_signal))
{
    options->exit_cb = uv_exit_cb;
}

RPY_EXTERN
void
monte_helper_set_stdio_stream(uv_stdio_container_t *stdio,
                              uv_stream_t *stream)
{
    stdio->data.stream = stream;
}
'''

_helper_eci = ExternalCompilationInfo(
    includes=['uv.h'],
    include_dirs=envPaths("TYPHON_INCLUDE_PATH"),
    separate_module_sources=[_PROCESS_C])

exit_cb = rffi.CCallback([process_tp, rffi.LONG, rffi.INT], lltype.Void)
add_exit_cb = rffi.llexternal('monte_helper_add_exit_cb', [process_options_tp,
                                                           exit_cb],
                              lltype.Void,
                              compilation_info=_helper_eci)
set_stdio_stream = rffi.llexternal("monte_helper_set_stdio_stream",
                                   [stdio_container_tp, stream_tp],
                                   lltype.Void,
                                   compilation_info=_helper_eci)


def allocProcess():
    return lltype.malloc(cConfig["process_t"], flavor="raw", zero=True)


def processDiscard(process, exit_status, term_signal):
    vat, subprocess = unstashProcess(process)
    subprocess.exited(exit_status, term_signal)
    free(process)


UV_PROCESS_WINDOWS_HIDE = 1 << 4
UV_IGNORE = 0x00
UV_CREATE_PIPE = 0x01
UV_INHERIT_STREAM = 0x04
UV_READABLE_PIPE = 0x10
UV_WRITABLE_PIPE = 0x20
uv_spawn = rffi.llexternal("uv_spawn", [loop_tp, process_tp,
                                        process_options_tp], rffi.INT,
                           compilation_info=eci)


def spawn(loop, process, file, args, env, streams):
    """
    The file descriptor list should be a list of streams to wire up to FDs in
    the child. A None stream is mapped to UV_IGNORE.
    """

    with rffi.scoped_str2charp(file) as rawFile:
        rawArgs = rffi.liststr2charpp(args)
        rawEnv = rffi.liststr2charpp(env)
        with rffi.scoped_str2charp(".") as rawCWD:
            options = rffi.make(cConfig["process_options_t"], c_file=rawFile,
                                c_args=rawArgs, c_env=rawEnv, c_cwd=rawCWD)
            with lltype.scoped_alloc(rffi.CArray(stdio_container_t),
                                     len(streams)) as rawStreams:
                for i, stream in enumerate(streams):
                    if stream == lltype.nullptr(stream_t):
                        flags = UV_IGNORE
                    else:
                        flags = UV_CREATE_PIPE
                        if i == 0:
                            flags |= UV_READABLE_PIPE
                        elif i in (1, 2):
                            flags |= UV_WRITABLE_PIPE
                        if not we_are_translated():
                            # doing extra allocations here to work around ll2ctypes'
                            # desire to gratuitously copy arrays
                            with lltype.scoped_alloc(stdio_container_t) as con:
                                set_stdio_stream(con, stream)
                                for field in rawStreams[i]._T._names:
                                    setattr(rawStreams[i], field, getattr(con, field))
                        else:
                            set_stdio_stream(rawStreams[i], stream)
                    rffi.setintfield(rawStreams[i], "c_flags", flags)
                options.c_stdio = rawStreams
                rffi.setintfield(options, "c_stdio_count", len(streams))
                add_exit_cb(options, processDiscard)

                # On Windows, ask to *not* have one of those annoying
                # console/terminal windows pop up. ~ C.
                rffi.setintfield(options, "c_flags", UV_PROCESS_WINDOWS_HIDE)
                rv = uv_spawn(loop, process, options)
                free(options)
        rffi.free_charpp(rawEnv)
        rffi.free_charpp(rawArgs)

    check("spawn", rv)


read_cb = rffi.CCallback([stream_tp, rffi.SSIZE_T, buf_tp], lltype.Void)
write_cb = rffi.CCallback([write_tp, rffi.INT], lltype.Void)
connect_cb = rffi.CCallback([connect_tp, rffi.INT], lltype.Void)
shutdown_cb = rffi.CCallback([shutdown_tp, rffi.INT], lltype.Void)
connection_cb = rffi.CCallback([stream_tp, rffi.INT], lltype.Void)

shutdown = rffi.llexternal("uv_shutdown", [shutdown_tp, stream_tp,
                                           shutdown_cb],
                           rffi.INT, compilation_info=eci)
listen = rffi.llexternal("uv_listen", [stream_tp, rffi.INT, connection_cb],
                         rffi.INT, compilation_info=eci)
accept = rffi.llexternal("uv_accept", [stream_tp, stream_tp], rffi.INT,
                         compilation_info=eci)
read_start = rffi.llexternal("uv_read_start", [stream_tp, alloc_cb, read_cb],
                             rffi.INT, compilation_info=eci)
readStart = checking("read_start", read_start)
read_stop = rffi.llexternal("uv_read_stop", [stream_tp], rffi.INT,
                            compilation_info=eci)
readStop = checking("read_stop", read_stop)
uv_write = rffi.llexternal("uv_write", [write_tp, stream_tp, array_buf_t,
                                        rffi.UINT, write_cb],
                           rffi.INT, compilation_info=eci)
write = checking("write", uv_write)
try_write = rffi.llexternal("uv_try_write", [stream_tp, array_buf_t,
                                             rffi.UINT],
                            rffi.INT, compilation_info=eci)
tryWrite = checking("try_write", try_write)


def alloc_write():
    return lltype.malloc(cConfig["write_t"], flavor="raw", zero=True)


def alloc_connect():
    return lltype.malloc(cConfig["connect_t"], flavor="raw", zero=True)


def alloc_shutdown():
    return lltype.malloc(cConfig["shutdown_t"], flavor="raw", zero=True)


tcp_init = rffi.llexternal("uv_tcp_init", [loop_tp, tcp_tp], rffi.INT,
                           compilation_info=eci)
# Give up type safety on the sockaddrs. They already intentionally gave up on
# type safety. ~ C.
tcp_bind = rffi.llexternal("uv_tcp_bind", [tcp_tp, rffi.VOIDP, rffi.UINT],
                           rffi.INT, compilation_info=eci)
tcp_connect = rffi.llexternal("uv_tcp_connect", [connect_tp, tcp_tp,
                                                 rffi.VOIDP, connect_cb],
                              rffi.INT, compilation_info=eci)


def alloc_tcp(loop):
    tcp = lltype.malloc(cConfig["tcp_t"], flavor="raw", zero=True)
    check("tcp_init", tcp_init(loop, tcp))
    return tcp


sin = lltype.malloc(s.sockaddr_in, flavor="raw", zero=True)
af4 = (s.AF_INET, sin, "c_sin_addr", "c_sin_family", "c_sin_port")


def tcp4Bind(stream, address, port):
    inet, sin, s_addr, s_fam, s_port = af4

    rffi.setintfield(sin, s_fam, inet)
    rffi.setintfield(sin, s_port, s.htons(port))
    if inet_pton(inet, address, getattr(sin, s_addr)):
        print "tcp4Bind: inet_pton failed!?"
        assert False

    # No flags.
    rv = check("tcp_bind", tcp_bind(stream, sin, 0))
    return rv


sin6 = lltype.malloc(s.sockaddr_in6, flavor="raw", zero=True)
af6 = (s.AF_INET6, sin6, "c_sin6_addr", "c_sin6_family", "c_sin6_port")


def tcp6Bind(stream, address, port):
    inet, sin, s_addr, s_fam, s_port = af6

    rffi.setintfield(sin, s_fam, inet)
    rffi.setintfield(sin, s_port, s.htons(port))
    if inet_pton(inet, address, getattr(sin, s_addr)):
        print "tcp6Bind: inet_pton failed!?"
        assert False

    # No flags.
    rv = check("tcp_bind", tcp_bind(stream, sin, 0))
    return rv


@specialize.ll()
def tcp4Connect(stream, address, port, callback):
    inet, sin, s_addr, s_fam, s_port = af4

    connect = alloc_connect()
    rffi.setintfield(sin, s_fam, inet)
    rffi.setintfield(sin, s_port, s.htons(port))
    if inet_pton(inet, address, getattr(sin, s_addr)):
        print "tcp4Connect: inet_pton failed!?"
        assert False

    rv = check("tcp_connect", tcp_connect(connect, stream, sin, callback))
    return rv


@specialize.ll()
def tcp6Connect(stream, address, port, callback):
    inet, sin, s_addr, s_fam, s_port = af6

    connect = alloc_connect()
    rffi.setintfield(sin, s_fam, inet)
    rffi.setintfield(sin, s_port, s.htons(port))
    if inet_pton(inet, address, getattr(sin, s_addr)):
        print "tcp6Connect: inet_pton failed!?"
        assert False

    rv = check("tcp_connect", tcp_connect(connect, stream, sin, callback))
    return rv


pipe_init = rffi.llexternal("uv_pipe_init", [loop_tp, pipe_tp, rffi.INT],
                            rffi.INT, compilation_info=eci)


def alloc_pipe(loop):
    pipe = lltype.malloc(cConfig["pipe_t"], flavor="raw", zero=True)
    check("pipe_init", pipe_init(loop, pipe, 0))
    return pipe


TTY_MODE_NORMAL = 0x0
TTY_MODE_RAW = 0x1
TTY_MODE_IO = 0x2

tty_init = rffi.llexternal("uv_tty_init", [loop_tp, tty_tp, rffi.INT,
                                           rffi.INT],
                           rffi.INT, compilation_info=eci)
tty_set_mode = rffi.llexternal("uv_tty_set_mode", [tty_tp, rffi.INT],
                               rffi.INT, compilation_info=eci)
TTYSetMode = checking("tty_set_mode", tty_set_mode)
tty_reset_mode = rffi.llexternal("uv_tty_reset_mode", [], rffi.INT,
                                 compilation_info=eci)
TTYResetMode = checking("tty_reset_mode", tty_reset_mode)
tty_get_winsize = rffi.llexternal("uv_tty_get_winsize",
                                  [tty_tp, rffi.INTP, rffi.INTP], rffi.INT,
                                  compilation_info=eci)
TTYGetWinSize = checking("tty_get_winsize", tty_get_winsize)

def alloc_tty(loop, fd, readable):
    tty = lltype.malloc(cConfig["tty_t"], flavor="raw", zero=True)
    check("tty_init", tty_init(loop, tty, fd, readable))
    return tty

_guess_handle = rffi.llexternal("uv_guess_handle", [rffi.INT], rffi.INT,
                                compilation_info=eci)


def guess_handle(fd):
    return check("guess_handle", _guess_handle(fd))

fs_cb = rffi.CCallback([fs_tp], lltype.Void)

fs_req_cleanup = rffi.llexternal("uv_fs_req_cleanup", [fs_tp], lltype.Void,
                                 compilation_info=eci)
fs_close = rffi.llexternal("uv_fs_close", [loop_tp, fs_tp, rffi.INT, fs_cb],
                           rffi.INT, compilation_info=eci)
fsClose = checking("fs_close", fs_close)
fs_open = rffi.llexternal("uv_fs_open", [loop_tp, fs_tp, rffi.CCHARP,
                                         rffi.INT, rffi.INT, fs_cb],
                          rffi.INT, compilation_info=eci)
fsOpen = checking("fs_open", fs_open)
fs_read = rffi.llexternal("uv_fs_read", [loop_tp, fs_tp, rffi.INT,
                                         array_buf_t, rffi.UINT,
                                         rffi.LONGLONG, fs_cb],
                          rffi.INT, compilation_info=eci)
fsRead = checking("fs_read", fs_read)
fs_write = rffi.llexternal("uv_fs_write", [loop_tp, fs_tp, rffi.INT,
                                           array_buf_t, rffi.UINT,
                                           rffi.LONGLONG, fs_cb],
                           rffi.INT, compilation_info=eci)
fsWrite = checking("fs_write", fs_write)
fs_rename = rffi.llexternal("uv_fs_rename", [loop_tp, fs_tp, rffi.CCHARP,
                                             rffi.CCHARP, fs_cb],
                            rffi.INT, compilation_info=eci)
fsRename = checking("fs_rename", fs_rename)

fsRead_erase, fsRead_unerase = new_erasing_pair("fsRead")


class FSReadFutureCallback(object):
    pass


stashFS2, unstashFS2, unstashingFS2 = stashFor("fs2", fs_tp,
                                               initial=fsRead_erase(
                                                   FSReadFutureCallback()))


def magic_fsReadCB(fs):
    size = intmask(fs.c_result)
    state, v = unstashFS2(fs)
    k = fsRead_unerase(v)
    fsDiscard(fs)
    if not k:
        return
    if size > 0:
            # XXX is this coupling to state contents dangerous?
            data = rffi.charpsize2str(state.buf.c_base, size)
            k.do(state, Ok(data))
    elif size < 0:
        k.do(state, (ERR, "", formatError(size).decode("utf-8")))
    else:
        k.do(state, Ok(""))


class magic_fsRead(object):
    callbackType = FSReadFutureCallback
    def __init__(self, vat, fd, buf):
        self.vat = vat
        self.fd = fd
        self.buf = buf

    def run(self, state, k):
        fs = alloc_fs()
        stashFS2(fs, (state, fsRead_erase(k)))
        with lltype.scoped_alloc(rffi.CArray(buf_t), 1) as bufs:
            bufs[0].c_base = self.buf.c_base
            bufs[0].c_len = self.buf.c_len
            fsRead(self.vat.uv_loop, fs, self.fd, bufs, 1, -1,
                   magic_fsReadCB)


fsWrite_erase, fsWrite_unerase = new_erasing_pair("fsWrite")


class FSWriteFutureCallback(object):
    pass


def magic_fsWriteCB(fs):
    state, v = unstashFS2(fs)
    wb = fsWrite_unerase(v)
    size = intmask(fs.c_result)
    fsDiscard(fs)
    wb.deallocate()
    if not wb.k:
        return
    if size >= 0:
        wb.k.do(state, Ok(size))
    else:
        wb.k.do(state, (ERR, 0, formatError(size).decode("utf-8")))


class WriteBuf(scopedBufs):
    def __init__(self, data, k):
        self.data = [data]
        self.k = k
        self.scoping = lltype.scoped_alloc(rffi.CArray(buf_t), len(self.data))


class magic_fsWrite(object):
    callbackType = FSWriteFutureCallback
    def __init__(self, vat, fd, data):
        self.vat = vat
        self.fd = fd
        self.data = data

    def run(self, state, k):
        fs = alloc_fs()
        wb = WriteBuf(self.data, k)
        stashFS2(fs, (state, fsWrite_erase(wb)))
        bufs = wb.allocate()
        fsWrite(self.vat.uv_loop, fs, self.fd, bufs, 1, -1,
                magic_fsWriteCB)


fsOpen_erase, fsOpen_unerase = new_erasing_pair("fsOpen")


def magic_fsOpenCB(fs):
    fd = intmask(fs.c_result)
    state, v = unstashFS2(fs)
    k = fsOpen_unerase(v)
    fsDiscard(fs)
    if not k:
        return
    if fd < 0:
        msg = formatError(fd).decode("utf-8")
        k.do(state, (ERR, 0, msg))
    else:
        k.do(state, Ok(fd))


class FSOpenFutureCallback(object):
    pass


class magic_fsOpen(object):
    callbackType = FSOpenFutureCallback
    def __init__(self, vat, path, flags, mode):
        self.vat = vat
        self.path = path
        self.flags = flags
        self.mode = mode

    def run(self, state, k):
        fs = alloc_fs()
        stashFS2(fs, (state, fsOpen_erase(k)))
        fsOpen(self.vat.uv_loop, fs, self.path, self.flags, self.mode,
               magic_fsOpenCB)


def magic_fsCloseCB(fs):
    state, v = unstashFS2(fs)
    k = fsClose_unerase(v)
    fsDiscard(fs)
    if not k:
        return
    k.do(state, Ok(None))


fsClose_erase, fsClose_unerase = new_erasing_pair("fsClose")


class FSCloseFutureCallback(object):
    pass


class magic_fsClose(object):
    callbackType = FSCloseFutureCallback
    def __init__(self, vat, f):
        self.vat = vat
        self.f = f

    def run(self, state, k):
        fs = alloc_fs()
        stashFS2(fs, (state, fsClose_erase(k)))
        fsClose(self.vat.uv_loop, fs, self.f, magic_fsCloseCB)


fsRename_erase, fsRename_unerase = new_erasing_pair("fsRename")


class FSRenameFutureCallback(object):
    pass

class magic_fsRename(object):
    callbackType = FSRenameFutureCallback
    def __init__(self, vat, src, dest):
        self.vat = vat
        self.src = src
        self.dest = dest

    def run(self, state, k):
        fs = alloc_fs()
        stashFS2(fs, (state, fsRename_erase(k)))
        fsRename(self.vat.uv_loop, fs, self.src, self.dest, magic_fsRenameCB)


def magic_fsRenameCB(fs):
    success = intmask(fs.c_result)
    state, v = unstashFS2(fs)
    k = fsRename_unerase(v)
    fsDiscard(fs)
    if not k:
        return
    if success < 0:
        msg = formatError(success).decode("utf-8")
        k.do(state, (ERR, None, msg))
    else:
        k.do(state, Ok(None))


def alloc_fs():
    return lltype.malloc(cConfig["fs_t"], flavor="raw", zero=True)


def fsDiscard(fs):
    fs_req_cleanup(fs)
    free(fs)


def fsUnstashAndDiscard(fs):
    unstashFS(fs)
    fsDiscard(fs)


gai_cb = rffi.CCallback([gai_tp, rffi.INT, s.addrinfo_ptr], lltype.Void)

gai = rffi.llexternal("uv_getaddrinfo", [loop_tp, gai_tp, gai_cb, rffi.CCHARP,
                                         rffi.CCHARP, s.addrinfo_ptr],
                      rffi.INT, compilation_info=eci)
getAddrInfo = checking("getaddrinfo", gai)
freeAddrInfo = rffi.llexternal("uv_freeaddrinfo", [s.addrinfo_ptr],
                               lltype.Void, compilation_info=eci)


def alloc_gai():
    return lltype.malloc(cConfig["getaddrinfo_t"], flavor="raw", zero=True)


ip4_name = rffi.llexternal("uv_ip4_name", [s.sockaddr_ptr, rffi.CCHARP,
                                           rffi.SIZE_T],
                           rffi.INT, compilation_info=eci)
ip6_name = rffi.llexternal("uv_ip6_name", [s.sockaddr_ptr, rffi.CCHARP,
                                           rffi.SIZE_T],
                           rffi.INT, compilation_info=eci)
inet_ntop = rffi.llexternal("uv_inet_ntop", [rffi.INT, rffi.VOIDP,
                                             rffi.CCHARP, rffi.SIZE_T],
                            rffi.INT, compilation_info=eci)
inet_pton = rffi.llexternal("uv_inet_pton", [rffi.INT, rffi.CCHARP,
                                             rffi.VOIDP],
                            rffi.INT, compilation_info=eci)


def IP4Name(sockaddr):
    size = 16
    with rffi.scoped_alloc_buffer(size) as buf:
        check("ip4_name", ip4_name(sockaddr, buf.raw, size))
        return buf.str(size).split('\x00', 1)[0]


def IP6Name(sockaddr):
    size = 46
    with rffi.scoped_alloc_buffer(size) as buf:
        check("ip6_name", ip6_name(sockaddr, buf.raw, size))
        return buf.str(size).split('\x00', 1)[0]


def magic_gaiCB(gai, status, ai):
    status = intmask(status)
    state, k = unstashGAI(gai)
    if status < 0:
        msg = formatError(status).decode("utf-8")
        k.do(state, (ERR, lltype.nullptr(s.addrinfo), msg))
    else:
        k.do(state, Ok(ai))
    freeAddrInfo(ai)
    free(gai)


class GetAddrInfoCallback(object):
    pass


class magic_getAddrInfo(object):
    callbackType = GetAddrInfoCallback

    def __init__(self, vat, node, service):
        self.vat = vat
        self.node = node
        self.service = service

    def run(self, state, k):
        gai = alloc_gai()
        stashGAI(gai, (state, k))
        getAddrInfo(self.vat.uv_loop, gai, magic_gaiCB, self.node,
                    self.service, lltype.nullptr(s.addrinfo))


signal_cb = rffi.CCallback([signal_tp, rffi.INT], lltype.Void)
signal_init = rffi.llexternal("uv_signal_init", [loop_tp, signal_tp],
                              rffi.INT, compilation_info=eci)
SignalInit = checking("signal_init", signal_init)
signal_start = rffi.llexternal("uv_signal_start",
                               [signal_tp, signal_cb, rffi.INT],
                               rffi.INT, compilation_info=eci)
SignalStart = checking("signal_start", signal_start)
signal_stop = rffi.llexternal("uv_signal_stop", [signal_tp],
                              rffi.INT, compilation_info=eci)
SignalStop = checking("signal_stop", signal_stop)


def alloc_signal(loop):
    signal = lltype.malloc(cConfig["signal_t"], flavor="raw", zero=True)
    check("signal_init", signal_init(loop, signal))
    return signal


def cleanup():
    """
    Clean up any libuv resources that have been finalized.

    Must be called outside of evaluation, ideally during other I/O work.
    """

    streamJanitor.cleanup()
