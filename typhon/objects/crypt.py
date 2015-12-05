"""
Some cryptographic services.
"""

from rpython.rlib.rarithmetic import intmask

from typhon import log, rsodium
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, WrongType, userError
from typhon.objects.collections.lists import ConstList
from typhon.objects.data import (BytesObject, IntObject, StrObject,
                                 unwrapBytes)
from typhon.objects.root import Object


ASBYTES_0 = getAtom(u"asBytes", 0)
GETALGORITHM_0 = getAtom(u"getAlgorithm", 0)
GETENTROPY_0 = getAtom(u"getEntropy", 0)
KEYMAKER_0 = getAtom(u"keyMaker", 0)
MAKESECUREENTROPY_0 = getAtom(u"makeSecureEntropy", 0)
PAIRWITH_1 = getAtom(u"pairWith", 1)
PUBLICKEY_0 = getAtom(u"publicKey", 0)
RUN_0 = getAtom(u"run", 0)
SEAL_1 = getAtom(u"seal", 1)
UNSEAL_2 = getAtom(u"unseal", 2)


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
class PublicKey(Object):
    """
    A public key.

    Pair this object with a secret key to get a sealer/unsealer.
    """

    _immutable_ = True

    def __init__(self, publicKey):
        self.publicKey = publicKey

    def recv(self, atom, args):
        if atom is ASBYTES_0:
            return BytesObject(self.publicKey)

        if atom is PAIRWITH_1:
            secret = args[0]
            if not isinstance(secret, SecretKey):
                raise WrongType(u"Not a secret key!")
            return KeyPair(self.publicKey, secret.secretKey)

        raise Refused(self, atom, args)


@autohelp
class SecretKey(Object):
    """
    A secret key.

    Pair this object with a public key to get a sealer/unsealer.
    """

    _immutable_ = True

    def __init__(self, secretKey):
        self.secretKey = secretKey

    def recv(self, atom, args):
        if atom is ASBYTES_0:
            # XXX should figure this out
            log.log(["sodium"], u"asBytes/0: Revealing secret key")
            return BytesObject(self.secretKey)

        if atom is PAIRWITH_1:
            public = args[0]
            if not isinstance(public, PublicKey):
                raise WrongType(u"Not a public key!")
            return KeyPair(public.publicKey, self.secretKey)

        if atom is PUBLICKEY_0:
            publicKey = rsodium.regenerateKey(self.secretKey)
            return PublicKey(publicKey)

        raise Refused(self, atom, args)


@autohelp
class KeyPair(Object):
    """
    An entangled public and secret key.

    This object can seal and unseal boxes; the boxes can be exchanged with a
    keypair of the corresponding secret and public keys.
    """

    _immutable_ = True

    def __init__(self, publicKey, secretKey):
        self.publicKey = publicKey
        self.secretKey = secretKey

    def recv(self, atom, args):
        if atom is SEAL_1:
            message = unwrapBytes(args[0])
            nonce = rsodium.freshNonce()
            cipher = rsodium.boxSeal(message, nonce, self.publicKey,
                                     self.secretKey)
            return ConstList([BytesObject(cipher), BytesObject(nonce)])

        if atom is UNSEAL_2:
            cipher = unwrapBytes(args[0])
            nonce = unwrapBytes(args[1])
            try:
                message = rsodium.boxUnseal(cipher, nonce, self.publicKey,
                                            self.secretKey)
            except rsodium.SodiumError:
                raise userError(u"unseal/2: Couldn't open this box")
            return BytesObject(message)

        raise Refused(self, atom, args)


@autohelp
class KeyMaker(Object):
    """
    Public-key cryptography via libsodium.
    """

    def recv(self, atom, args):
        if atom is RUN_0:
            public, secret = rsodium.freshKeypair()
            return ConstList([PublicKey(public), SecretKey(secret)])

        raise Refused(self, atom, args)

theKeyMaker = KeyMaker()


@autohelp
class Crypt(Object):
    """
    A libsodium-backed cryptographic service provider.
    """

    def recv(self, atom, args):
        if atom is MAKESECUREENTROPY_0:
            return SecureEntropy()

        if atom is KEYMAKER_0:
            return theKeyMaker

        raise Refused(self, atom, args)
