"""
libsodium bindings.

Import as `from typhon import rsodium` and then use namespaced.
"""

import os

from rpython.rtyper.lltypesystem import rffi
from rpython.rtyper.tool import rffi_platform
from rpython.translator.tool.cbuild import ExternalCompilationInfo

def envPaths(name):
    val = os.getenv(name)
    if val is None:
        return []
    else:
        return val.split(':')


eci = ExternalCompilationInfo(includes=["sodium.h"],
                              include_dirs=envPaths("TYPHON_INCLUDE_PATH"),
                              library_dirs=envPaths("TYPHON_LIBRARY_PATH"),
                              libraries=["sodium"])


class CConfig:
    _compilation_info_ = eci

cConfig = rffi_platform.configure(CConfig)

init = rffi.llexternal("sodium_init", [], rffi.INT, compilation_info=eci)

randombytesRandom = rffi.llexternal("randombytes_random", [], rffi.UINT,
                                    compilation_info=eci)

def randomBytes():
    r = randombytesRandom()
    return "".join(chr((r >> i) & 0xff) for i in range(0, 32, 8))

hexList = ["%02x" % i for i in range(256)]

def randomHex():
    r = randomBytes()
    return "".join(hexList[ord(i)] for i in r)
