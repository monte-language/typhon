"""
Some cryptographic services.
"""

from rpython.rlib.rarithmetic import intmask

from typhon import log, rsodium
from typhon.autohelp import autohelp, method
from typhon.errors import WrongType, userError
from typhon.objects.data import BytesObject, IntObject
from typhon.objects.root import Object


@autohelp
class SecureEntropy(Object):
    """
    Entropy via libsodium's randombytes_random() API.
    """

    @method("Str")
    def getAlgorithm(self):
        return u"CSPRNG (libsodium)"

    @method("List")
    def getEntropy(self):
        # uint32_t in the FFI, so exactly 32 bits every time.
        return [IntObject(32),
                IntObject(intmask(rsodium.randombytesRandom()))]


@autohelp
class PublicKey(Object):
    """
    A public key.

    Pair this object with a secret key to get a sealer/unsealer.
    """

    _immutable_fields_ = "publicKey",

    def __init__(self, publicKey):
        self.publicKey = publicKey

    @method("Bytes")
    def asBytes(self):
        return self.publicKey

    @method("Any", "Any")
    def pairWith(self, secret):
        if not isinstance(secret, SecretKey):
            raise WrongType(u"Not a secret key!")
        return KeyPair(self.publicKey, secret.secretKey)


@autohelp
class SecretKey(Object):
    """
    A secret key.

    Pair this object with a public key to get a sealer/unsealer.
    """

    _immutable_fields_ = "secretKey",

    def __init__(self, secretKey):
        self.secretKey = secretKey

    @method("Bytes")
    def asBytes(self):
        # XXX should figure this out
        log.log(["sodium"], u"asBytes/0: Revealing secret key")
        return self.secretKey

    @method("Any", "Any")
    def pairWith(self, public):
        if not isinstance(public, PublicKey):
            raise WrongType(u"Not a public key!")
        return KeyPair(public.publicKey, self.secretKey)

    @method("Any")
    def publicKey(self):
        publicKey = rsodium.regenerateKey(self.secretKey)
        return PublicKey(publicKey)


@autohelp
class KeyPair(Object):
    """
    An entangled public and secret key.

    This object can seal and unseal boxes; the boxes can be exchanged with a
    keypair of the corresponding secret and public keys.
    """

    _immutable_fields_ = "publicKey", "secretKey"

    def __init__(self, publicKey, secretKey):
        self.publicKey = publicKey
        self.secretKey = secretKey

    @method("List", "Bytes")
    def seal(self, message):
        nonce = rsodium.freshNonce()
        cipher = rsodium.boxSeal(message, nonce, self.publicKey,
                                 self.secretKey)
        return [BytesObject(cipher), BytesObject(nonce)]

    @method("Bytes", "Bytes", "Bytes")
    def unseal(self, cipher, nonce):
        try:
            message = rsodium.boxUnseal(cipher, nonce, self.publicKey,
                                        self.secretKey)
        except rsodium.SodiumError:
            raise userError(u"unseal/2: Couldn't open this box")
        return message


@autohelp
class KeyMaker(Object):
    """
    Public-key cryptography via libsodium.
    """

    @method("Any", "Bytes")
    def fromPublicBytes(self, publicKey):
        expectedSize = intmask(rsodium.cryptoBoxPublickeybytes())
        if len(publicKey) != expectedSize:
            message = u"Expected key length of %d bytes, not %d" % (
                expectedSize, len(publicKey))
            raise userError(message)
        return PublicKey(publicKey)

    @method("Any", "Bytes")
    def fromSecretBytes(self, secretKey):
        expectedSize = intmask(rsodium.cryptoBoxSecretkeybytes())
        if len(secretKey) != expectedSize:
            message = u"Expected key length of %d bytes, not %d" % (
                expectedSize, len(secretKey))
            raise userError(message)
        return SecretKey(secretKey)

    @method("List")
    def run(self):
        public, secret = rsodium.freshKeypair()
        return [PublicKey(public), SecretKey(secret)]

theKeyMaker = KeyMaker()


@autohelp
class Crypt(Object):
    """
    A libsodium-backed cryptographic service provider.
    """

    @method("Any")
    def makeSecureEntropy(self):
        return SecureEntropy()

    @method("Any")
    def keyMaker(self):
        return theKeyMaker
