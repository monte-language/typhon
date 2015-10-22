"""
libsodium bindings.

Import as `from typhon import rsodium` and then use namespaced.
"""

import os

from rpython.rtyper.lltypesystem import lltype, rffi
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
