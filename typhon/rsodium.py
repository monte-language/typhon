"""
libsodium bindings.

Import as `from typhon import rsodium` and then use namespaced.
"""

import os

from rpython.rlib.rarithmetic import intmask
from rpython.rtyper.lltypesystem import lltype, rffi
from rpython.rtyper.tool import rffi_platform
from rpython.translator.tool.cbuild import ExternalCompilationInfo

class SodiumError(Exception):
    """
    libsodium was unhappy.
    """

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
randombytesBuf = rffi.llexternal("randombytes_buf",
                                 [rffi.CCHARP, rffi.SIZE_T], lltype.Void,
                                 compilation_info=eci)

def randomBytes():
    r = randombytesRandom()
    return "".join([chr((r >> i) & 0xff) for i in range(0, 32, 8)])

hexList = ["%02x" % i for i in range(256)]

def randomHex():
    r = randomBytes()
    return "".join([hexList[ord(i)] for i in r])

cryptoBoxPublickeybytes = rffi.llexternal("crypto_box_publickeybytes", [],
                                          rffi.SIZE_T, compilation_info=eci)
cryptoBoxSecretkeybytes = rffi.llexternal("crypto_box_secretkeybytes", [],
                                          rffi.SIZE_T, compilation_info=eci)
cryptoBoxNoncebytes = rffi.llexternal("crypto_box_noncebytes", [],
                                      rffi.SIZE_T, compilation_info=eci)
cryptoBoxMacbytes = rffi.llexternal("crypto_box_macbytes", [], rffi.SIZE_T,
                                    compilation_info=eci)
cryptoBoxKeypair = rffi.llexternal("crypto_box_keypair",
                                   [rffi.CCHARP, rffi.CCHARP], rffi.INT,
                                   compilation_info=eci)
cryptoBoxEasy = rffi.llexternal("crypto_box_easy",
                                [rffi.CCHARP, rffi.CCHARP, rffi.ULONGLONG,
                                 rffi.CCHARP, rffi.CCHARP, rffi.CCHARP],
                                rffi.INT, compilation_info=eci)
cryptoBoxOpenEasy = rffi.llexternal("crypto_box_open_easy",
                                    [rffi.CCHARP, rffi.CCHARP, rffi.ULONGLONG,
                                     rffi.CCHARP, rffi.CCHARP, rffi.CCHARP],
                                    rffi.INT, compilation_info=eci)

def freshKeypair():
    """
    Make a fresh keypair.
    """

    publicSize = intmask(cryptoBoxPublickeybytes())
    secretSize = intmask(cryptoBoxSecretkeybytes())

    with rffi.scoped_alloc_buffer(publicSize) as public:
        with rffi.scoped_alloc_buffer(secretSize) as secret:
            rv = cryptoBoxKeypair(public.raw, secret.raw)
            if rv:
                raise SodiumError("crypto_box_keypair: %d" % rv)
            return public.str(publicSize), secret.str(secretSize)

def freshNonce():
    """
    Make a fresh nonce.
    """

    nonceSize = intmask(cryptoBoxNoncebytes())

    with rffi.scoped_alloc_buffer(nonceSize) as nonce:
        randombytesBuf(nonce.raw, nonceSize)
        return nonce.str(nonceSize)

def boxSeal(message, nonce, public, secret):
    cipherSize = len(message) + intmask(cryptoBoxMacbytes())

    with rffi.scoped_alloc_buffer(cipherSize) as cipher:
        with rffi.scoped_str2charp(message) as rawMessage:
            with rffi.scoped_str2charp(nonce) as rawNonce:
                with rffi.scoped_str2charp(public) as rawPublic:
                    with rffi.scoped_str2charp(secret) as rawSecret:
                        rv = cryptoBoxEasy(cipher.raw, rawMessage,
                                           len(message), rawNonce, rawPublic,
                                           rawSecret)
                        if rv:
                            raise SodiumError("crypto_box_easy: %d" % rv)
                        return cipher.str(cipherSize)

def boxUnseal(cipher, nonce, public, secret):
    messageSize = len(cipher) - intmask(cryptoBoxMacbytes())
    assert messageSize >= 0

    with rffi.scoped_alloc_buffer(messageSize) as message:
        with rffi.scoped_str2charp(cipher) as rawCipher:
            with rffi.scoped_str2charp(nonce) as rawNonce:
                with rffi.scoped_str2charp(public) as rawPublic:
                    with rffi.scoped_str2charp(secret) as rawSecret:
                        rv = cryptoBoxOpenEasy(message.raw, rawCipher,
                                               len(cipher), rawNonce,
                                               rawPublic, rawSecret)
                        if rv:
                            raise SodiumError("crypto_box_open_easy: %d" % rv)
                        return message.str(messageSize)
