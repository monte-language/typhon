"""
Miscellaneous makers in the safe scope.
"""

from rpython.rlib.rbigint import rbigint
from rpython.rlib.rstring import ParseStringError
from rpython.rlib.rstruct.ieee import unpack_float

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import (listFromIterable, unwrapList,
                                              wrapList)
from typhon.objects.collections.maps import ConstMap
from typhon.objects.data import (BigInt, BytesObject, DoubleObject, StrObject,
                                 bytesToString, unwrapBytes, unwrapInt,
                                 unwrapStr, unwrapChar)
from typhon.objects.root import Object, audited, runnable
from typhon.profile import profileTyphon

FROMBYTES_1 = getAtom(u"fromBytes", 1)
FROMBYTES_2 = getAtom(u"fromBytes", 2)
FROMCHARS_1 = getAtom(u"fromChars", 1)
FROMINTS_1 = getAtom(u"fromInts", 1)
FROMITERABLE_1 = getAtom(u"fromIterable", 1)
FROMPAIRS_1 = getAtom(u"fromPairs", 1)
FROMSTRING_1 = getAtom(u"fromString", 1)
FROMSTRING_2 = getAtom(u"fromString", 2)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


@autohelp
@audited.DF
class MakeBytes(Object):
    """
    The maker of `Bytes`.
    """

    def toString(self):
        return u"<makeBytes>"

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            return BytesObject("".join([chr(ord(c))
                                        for c in unwrapStr(args[0])]))

        if atom is FROMINTS_1:
            data = unwrapList(args[0])
            return BytesObject("".join([chr(unwrapInt(i)) for i in data]))

        raise Refused(self, atom, args)
theMakeBytes = MakeBytes()


@autohelp
@audited.DF
class MakeDouble(Object):
    """
    The maker of `Double`s.
    """

    def toString(self):
        return u"<makeDouble>"

    def recv(self, atom, args):
        if atom is RUN_1:
            return DoubleObject(float(unwrapStr(args[0]).encode('utf-8')))

        if atom is FROMBYTES_1:
            bs = unwrapBytes(args[0])
            try:
                return DoubleObject(unpack_float(bs, True))
            except ValueError:
                raise userError(u"Couldn't unpack invalid IEEE 754 double")

        raise Refused(self, atom, args)
theMakeDouble = MakeDouble()


@autohelp
@audited.DF
class MakeInt(Object):
    """
    The maker of `Int`s.
    """

    def toString(self):
        return u"<makeInt>"

    @staticmethod
    @profileTyphon("_makeInt.fromBytes/2")
    def fromBytes(bs, radix):
        # Ruby-style underscores are legal here but can't be handled by
        # RPython, so remove them.
        bs = ''.join([c for c in bs if c != '_'])
        try:
            return rbigint.fromstr(bs, radix)
        except ParseStringError:
            raise userError(u"Couldn't parse int from string")

    def recv(self, atom, args):
        if atom is RUN_1:
            bs = unwrapStr(args[0]).encode("utf-8")
            return BigInt(self.fromBytes(bs, 10))

        if atom is RUN_2:
            inp = unwrapStr(args[0])
            bs = inp.encode("utf-8")
            radix = unwrapInt(args[1])
            try:
                return BigInt(self.fromBytes(bs, radix))
            except ValueError:
                raise userError(u"Invalid literal for base %d: %s" %
                                (radix, inp))

        if atom is FROMBYTES_1:
            bs = unwrapBytes(args[0])
            return BigInt(self.fromBytes(bs, 10))

        if atom is FROMBYTES_2:
            bs = unwrapBytes(args[0])
            radix = unwrapInt(args[1])
            try:
                return BigInt(self.fromBytes(bs, radix))
            except ValueError:
                raise userError(u"Invalid literal for base %d: %s" %
                                (radix, bytesToString(bs)))

        raise Refused(self, atom, args)
theMakeInt = MakeInt()


@autohelp
@audited.DF
class MakeList(Object):
    """
    The maker of `List`s.
    """

    def toString(self):
        return u"<makeList>"

    def recv(self, atom, args):
        if atom.verb == u"run":
            return wrapList(args)

        if atom is FROMITERABLE_1:
            return wrapList(listFromIterable(args[0])[:])

        raise Refused(self, atom, args)
theMakeList = MakeList()


@runnable(FROMPAIRS_1, [deepFrozenStamp])
def makeMap(pairs):
    """
    Given a `List[Pair]`, produce a `Map`.
    """

    return ConstMap.fromPairs(pairs)
theMakeMap = makeMap()


@autohelp
@audited.DF
class MakeStr(Object):
    """
    The maker of `Str`s.
    """

    def toString(self):
        return u"<makeStr>"

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            # XXX handle twineishness
            return args[0]

        if atom is FROMSTRING_2:
            # XXX handle twineishness
            return args[0]

        if atom is FROMCHARS_1:
            data = unwrapList(args[0])
            return StrObject(u"".join([unwrapChar(c) for c in data]))

        raise Refused(self, atom, args)
theMakeStr = MakeStr()
