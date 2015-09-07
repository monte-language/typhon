"""
libuv bindings.

I got sick of typing "uv_", so everything is missing it except where
absolutely required. You're welcome.

Import as `from typhon import ruv` and then use namespaced. Please.
"""
import os

from functools import wraps

from rpython.rlib import _rsocket_rffi as s
from rpython.rlib.objectmodel import specialize
from rpython.rlib.rarithmetic import intmask
from rpython.rlib.rawstorage import alloc_raw_storage, free_raw_storage
from rpython.rtyper.lltypesystem import lltype, rffi
from rpython.rtyper.tool import rffi_platform
from rpython.translator.tool.cbuild import ExternalCompilationInfo


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
        raise UVError(rv, message)
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


eci = ExternalCompilationInfo(includes=["uv.h"],
                              include_dirs=envPaths("TYPHON_INCLUDE_PATH"),
                              library_dirs=envPaths("TYPHON_LIBRARY_PATH"),
                              libraries=["nsl", "rt", "uv"])

class CConfig:
    _compilation_info_ = eci

    loop_t = rffi_platform.Struct("uv_loop_t", [("data", rffi.VOIDP)])
    handle_t = rffi_platform.Struct("uv_handle_t", [("data", rffi.VOIDP)])
    timer_t = rffi_platform.Struct("uv_timer_t", [("data", rffi.VOIDP)])
    prepare_t = rffi_platform.Struct("uv_prepare_t", [("data", rffi.VOIDP)])
    idle_t = rffi_platform.Struct("uv_idle_t", [("data", rffi.VOIDP)])
    stream_t = rffi_platform.Struct("uv_stream_t", [("data", rffi.VOIDP)])
    connect_t = rffi_platform.Struct("uv_connect_t",
                                     [("handle",
                                       lltype.Ptr(lltype.ForwardReference()))])
    shutdown_t = rffi_platform.Struct("uv_shutdown_t", [])
    write_t = rffi_platform.Struct("uv_write_t", [])
    tcp_t = rffi_platform.Struct("uv_tcp_t", [("data", rffi.VOIDP)])
    tty_t = rffi_platform.Struct("uv_tty_t", [("data", rffi.VOIDP)])
    fs_t = rffi_platform.Struct("uv_fs_t",
                                [("data", rffi.VOIDP),
                                 ("path", rffi.CONST_CCHARP),
                                 ("result", rffi.SSIZE_T),
                                 ("ptr", rffi.VOIDP)])
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
stream_tp = rffi.lltype.Ptr(cConfig["stream_t"])
connect_tp = rffi.lltype.Ptr(cConfig["connect_t"])
shutdown_tp = rffi.lltype.Ptr(cConfig["shutdown_t"])
write_tp = rffi.lltype.Ptr(cConfig["write_t"])
tcp_tp = rffi.lltype.Ptr(cConfig["tcp_t"])
tty_tp = rffi.lltype.Ptr(cConfig["tty_t"])
fs_tp = rffi.lltype.Ptr(cConfig["fs_t"])
buf_tp = lltype.Ptr(cConfig["buf_t"])

buf_t = cConfig["buf_t"]
array_buf_t = lltype.Ptr(lltype.Array(buf_t, hints={"nolength": True}))

# Forward references.
cConfig["connect_t"].c_handle.TO.become(cConfig["stream_t"])


def stashFor(struct):
    class Stash(object):
        """
        Like a weaklist, but keeps a strong reference to its elements.

        Beware: get and put aren't idempotent. A get will remove the object from
        the stash!

        Asynchronous code is weird, man. If you don't keep strong references, then
        the only references left might be in FFI or libc, which is not good. So we
        can't use weakrefs here.
        """

        def __init__(self, initialSize=4):
            self.freeList = range(initialSize)
            self.storage = [(None, None)] * initialSize

        def get(self, index):
            rv = self.storage[index]
            # Zero out the reference in storage so that the object doesn't live
            # too long.
            self.storage[index] = None, None
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
            newStorage = self.storage + [(None, None)] * extraSize
            self.freeList.extend(range(extraSize, extraSize * 2))
            self.storage = newStorage
            # We just extended freeList, so this should always be safe.
            return self.freeList.pop()

    theStash = Stash()

    def stash(uv_t, obj):
        # uv_t = rffi.cast(struct, uv_t)
        index = theStash.put(obj)
        uv_t.c_data = rffi.cast(rffi.VOIDP, index)

    def unstash(uv_t):
        # uv_t = rffi.cast(struct, uv_t)
        index = rffi.cast(rffi.INT, uv_t.c_data)
        return theStash.get(index)

    class unstashing(object):

        def __init__(self, uv_t):
            self.uv_t = uv_t

        def __enter__(self):
            self.unstashed = unstash(self.uv_t)
            return self.unstashed

        def __exit__(self, *args):
            stash(self.uv_t, self.unstashed)

    return stash, unstash, unstashing

stashTimer, unstashTimer, unstashingTimer = stashFor(timer_tp)
stashStream, unstashStream, unstashingStream = stashFor(stream_tp)
stashFS, unstashFS, unstashingFS = stashFor(fs_tp)


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

# This is almost certainly the right thing to pass to alloc_cb.
def allocCB(handle, size, buf):
    buf.c_base = alloc_raw_storage(size)
    rffi.setintfield(buf, "c_len", size)

class scopedBufs(object):

    def __init__(self, data):
        self.data = data
        self.scoping = lltype.scoped_alloc(rffi.CArray(buf_t), len(self.data))

    def __enter__(self):
        bufs = self.scoping.__enter__()
        self.metabufs = []
        for i, datum in enumerate(self.data):
            # get_nonmovingbuffer tries its hardest to avoid copies. Don't
            # forget that we have to deallocate each one later.
            charp, pinned, copied = rffi.get_nonmovingbuffer(datum)
            bufs[i].c_base = charp
            rffi.setintfield(bufs[i], "c_len", len(datum))
            # Store the original strs to keep them alive and make iteration
            # easier later.
            self.metabufs.append((datum, charp, pinned, copied))
        return bufs

    def __exit__(self, *args):
        # Deallocate. Can't forget to do this, or else we could fill the
        # GC with pinned crap.
        for datum, charp, pinned, copied in self.metabufs:
            rffi.free_nonmovingbuffer(datum, charp, pinned, copied)
        self.scoping.__exit__(*args)


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
uv_close = rffi.llexternal("uv_close", [handle_tp, close_cb], lltype.Void,
                           compilation_info=eci)
def close(handleish, cb):
    uv_close(rffi.cast(handle_tp, handleish), cb)


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
tcp_bind = rffi.llexternal("uv_tcp_bind", [tcp_tp, s.sockaddr_ptr, rffi.UINT],
                           rffi.INT, compilation_info=eci)
tcp_connect = rffi.llexternal("uv_tcp_connect", [connect_tp, tcp_tp,
                                                 s.sockaddr_ptr, connect_cb],
                              rffi.INT, compilation_info=eci)

def alloc_tcp(loop):
    tcp = lltype.malloc(cConfig["tcp_t"], flavor="raw", zero=True)
    check("tcp_init", tcp_init(loop, tcp))
    return tcp

def tcpBind(stream, address, port):
    with lltype.scoped_alloc(s.sockaddr_in) as sockaddr:
        rffi.setintfield(sockaddr, "c_sin_family", s.AF_INET)
        sockaddr.c_sin_port = s.htons(port)
        s.inet_pton(s.AF_INET, address, sockaddr.c_sin_addr)
        # No flags.
        sa = rffi.cast(lltype.Ptr(s.sockaddr), sockaddr)
        return check("tcp_bind", tcp_bind(stream, sa, 0))

def tcpConnect(stream, address, port, callback):
    connect = alloc_connect()
    with lltype.scoped_alloc(s.sockaddr_in) as sockaddr:
        rffi.setintfield(sockaddr, "c_sin_family", s.AF_INET)
        sockaddr.c_sin_port = s.htons(port)
        s.inet_pton(s.AF_INET, address, sockaddr.c_sin_addr)
        sa = rffi.cast(lltype.Ptr(s.sockaddr), sockaddr)
        return check("tcp_connect", tcp_connect(connect, stream, sa,
                                                callback))


tty_init = rffi.llexternal("uv_tty_init", [loop_tp, tty_tp, rffi.INT,
                                           rffi.INT],
                           rffi.INT, compilation_info=eci)

def alloc_tty(loop, fd, readable):
    tty = lltype.malloc(cConfig["tty_t"], flavor="raw", zero=True)
    check("tty_init", tty_init(loop, tty, fd, readable))
    return tty


fs_cb = rffi.CCallback([fs_tp], lltype.Void)

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

def alloc_fs():
    return lltype.malloc(cConfig["fs_t"], flavor="raw", zero=True)
