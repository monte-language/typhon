"""
RPython-friendly POSIX message queue bindings.
"""

import os

from rpython.rlib.rposix import get_saved_errno
from rpython.rtyper.lltypesystem import lltype, rffi
from rpython.translator.tool.cbuild import ExternalCompilationInfo

eci = ExternalCompilationInfo(includes=["mqueue.h"], libraries=["rt"])

mqd_t = rffi.platform.inttype("mqd_t", "mqd_t", True,
                              add_source="#include <mqueue.h>")

mq_attr = rffi.CStruct("mq_attr", ("mq_flags", rffi.LONG),
                       ("mq_maxmsg", rffi.LONG), ("mq_msgsize", rffi.LONG),
                       ("mq_curmsgs", rffi.LONG))
mq_attrp = rffi.lltype.Ptr(mq_attr)

mq_open = rffi.llexternal("mq_open",
                          [rffi.CCHARP, rffi.INT, rffi.MODE_T, mq_attrp],
                          mqd_t, compilation_info=eci,
                          save_err=rffi.RFFI_SAVE_ERRNO)

mq_close = rffi.llexternal("mq_close", [mqd_t], rffi.INT,
                           compilation_info=eci,
                           save_err=rffi.RFFI_SAVE_ERRNO)

mq_unlink = rffi.llexternal("mq_unlink", [rffi.CCHARP], rffi.INT,
                            compilation_info=eci,
                            save_err=rffi.RFFI_SAVE_ERRNO)

mq_getattr = rffi.llexternal("mq_getattr", [mqd_t, mq_attrp], rffi.INT,
                             compilation_info=eci,
                             save_err=rffi.RFFI_SAVE_ERRNO)

mq_setattr = rffi.llexternal("mq_setattr", [mqd_t, mq_attrp, mq_attrp],
                             rffi.INT, compilation_info=eci,
                             save_err=rffi.RFFI_SAVE_ERRNO)

mq_send = rffi.llexternal("mq_send",
                          [mqd_t, rffi.CCHARP, rffi.SIZE_T, rffi.UINT],
                          rffi.INT, compilation_info=eci,
                          save_err=rffi.RFFI_SAVE_ERRNO)

mq_receive = rffi.llexternal("mq_receive",
                             [mqd_t, rffi.CCHARP, rffi.SIZE_T, rffi.UINTP],
                             rffi.INT, compilation_info=eci,
                             save_err=rffi.RFFI_SAVE_ERRNO)


def check_call(rv, msg):
    if rv == -1:
        errno = get_saved_errno()
        raise OSError(errno, "%s: %s" % (msg, os.strerror(errno)))
    return rv


def alloc_mq_attr():
    return rffi.make(mq_attr)


def free_mq_attr(mqstat):
    lltype.free(mqstat, flavor="raw")


def unlink_mqueue(name):
    """
    Destroys a message queue.

    Semantics are documented in man pages. Destroying a queue does not
    invalidate any of its existing descriptors, but it does immediately remove
    the name from the list of extant queues.
    """

    check_call(mq_unlink(name), "mq_unlink")


class MQueue(object):
    """
    A POSIX message queue.

    For an overview, read the mq_overview man page.
    """

    closed = False

    def __init__(self, name, flags, mode=0777, attributes=None):
        """
        Open a descriptor to an mqueue.

        Permissible flags are described in mq_open()'s documentation. If it's
        allowed for open(), it's probably allowed for mq_open().
        """

        self.mqd = check_call(mq_open(name, flags, mode, attributes),
                              "mq_open")
        self._getattr()

    def _getattr(self):
        with lltype.scoped_alloc(mq_attr) as mqstat:
            check_call(mq_getattr(self.mqd, mqstat), "mq_getattr")
            self.flags = mqstat.c_mq_flags
            self.maxmsg = mqstat.c_mq_maxmsg
            self.msgsize = mqstat.c_mq_msgsize
            self.curmsgs = mqstat.c_mq_curmsgs

    def close(self):
        check_call(mq_close(self.mqd), "mq_close")
        self.closed = True
        self.mqd = -1

    def receive(self):
        msgsize = self.msgsize
        with rffi.scoped_alloc_buffer(msgsize) as msg_ptr:
            with lltype.scoped_alloc(rffi.UINTP.TO, 1) as msg_prio:
                size = check_call(mq_receive(self.mqd, msg_ptr.raw, msgsize,
                                             msg_prio),
                                  "mq_receive")
                return msg_ptr.str(size), msg_prio[0]

    def send(self, msg, prio):
        with rffi.scoped_nonmovingbuffer(msg) as msg_ptr:
            check_call(mq_send(self.mqd, msg_ptr, len(msg), prio), "mq_send")
