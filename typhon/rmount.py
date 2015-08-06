"""
The mount() syscall/libc wrapper.

Also wrapped is umount().
"""

import os

from rpython.rlib.rposix import get_saved_errno
from rpython.rtyper.lltypesystem import lltype, rffi
from rpython.translator.tool.cbuild import ExternalCompilationInfo

eci = ExternalCompilationInfo()

_mount = rffi.llexternal("mount",
                         [rffi.CCHARP, rffi.CCHARP, rffi.CCHARP, rffi.ULONG,
                          rffi.CCHARP],
                         rffi.INT, compilation_info=eci,
                         save_err=rffi.RFFI_SAVE_ERRNO)

_umount = rffi.llexternal("umount", [rffi.CCHARP], rffi.INT,
                          compilation_info=eci, save_err=rffi.RFFI_SAVE_ERRNO)


def check_call(rv, msg):
    if rv == -1:
        errno = get_saved_errno()
        raise OSError(errno, "%s: %s" % (msg, os.strerror(errno)))
    return rv


def mount(source, target, type, flags, data):
    return check_call(_mount(source, target, type, flags, data), "mount")

def umount(target):
    return check_call(_umount(target), "umount")
