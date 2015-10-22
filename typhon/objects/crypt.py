"""
Some cryptographic services.
"""

from rpython.rlib.rarithmetic import intmask

from typhon import rsodium
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.collections import ConstList
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object


GETALGORITHM_0 = getAtom(u"getAlgorithm", 0)
GETENTROPY_0 = getAtom(u"getEntropy", 0)
MAKESECUREENTROPY_0 = getAtom(u"makeSecureEntropy", 0)


@autohelp
class SecureEntropy(Object):
    """
    Entropy via libsodium's randombytes_random() API.
    """

    def recv(self, atom, args):
        if atom is GETALGORITHM_0:
            return StrObject(u"CSPRNG (libsodium)")

        if atom is GETENTROPY_0:
            # uint32_t in the FFI, so exactly 32 bits every time.
            return ConstList([IntObject(32),
                              IntObject(intmask(rsodium.randombytesRandom()))])

        raise Refused(self, atom, args)


@autohelp
class Crypt(Object):
    """
    A libsodium-backed cryptographic service provider.
    """

    def recv(self, atom, args):
        if atom is MAKESECUREENTROPY_0:
            return SecureEntropy()

        raise Refused(self, atom, args)
