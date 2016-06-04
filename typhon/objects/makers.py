"""
Miscellaneous makers in the safe scope.
"""

from rpython.rlib.rbigint import rbigint
from rpython.rlib.rstring import ParseStringError
from rpython.rlib.rstruct.ieee import unpack_float

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.log import deprecated
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import (listFromIterable, unwrapList,
                                              wrapList)
from typhon.objects.collections.maps import ConstMap
from typhon.objects.data import (BigInt, BytesObject, DoubleObject, StrObject,
                                 bytesToString, unwrapBytes, unwrapInt,
                                 unwrapStr, unwrapChar)
from typhon.objects.ejectors import throw
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
FROMSTR_1 = getAtom(u"fromStr", 1)
FROMSTR_2 = getAtom(u"fromStr", 2)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)
WITHRADIX_1 = getAtom(u"withRadix", 1)


@autohelp
@audited.DF
class MakeBytes(Object):
    """
    The maker of `Bytes`.
    """

    def toString(self):
        return u"<makeBytes>"

    @deprecated(u"_makeBytes.fromString/1: Use .fromStr/1 instead")
    def fromString(self, s):
        return self.fromStr(s)

    def fromStr(self, s):
        return BytesObject("".join([chr(ord(c)) for c in s]))

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            return self.fromString(unwrapStr(args[0]))

        if atom is FROMSTR_1:
            return self.fromStr(unwrapStr(args[0]))

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

    def run(self, bs, ej):
        try:
            return DoubleObject(float(bs))
        except ValueError:
            throw(ej, StrObject(u"Couldn't parse floating-point number"))

    def fromBytes(self, bs, ej):
        try:
            return DoubleObject(unpack_float(bs, True))
        except ValueError:
            throw(ej, StrObject(u"Couldn't unpack invalid IEEE 754 double"))

    def recv(self, atom, args):
        if atom is RUN_1:
            return self.run(unwrapStr(args[0]).encode("utf-8"), None)

        if atom is RUN_2:
            return self.run(unwrapStr(args[0]).encode("utf-8"), args[1])

        if atom is FROMBYTES_1:
            return self.fromBytes(unwrapBytes(args[0]), None)

        if atom is FROMBYTES_2:
            return self.fromBytes(unwrapBytes(args[0]), args[1])

        raise Refused(self, atom, args)
theMakeDouble = MakeDouble()


@autohelp
@audited.DF
class MakeInt(Object):
    """
    A maker of `Int`s.
    """

    _immutable_fields_ = "radix",

    def __init__(self, radix):
        self.radix = radix

    def toString(self):
        return u"<makeInt(radix %d)>" % (self.radix,)

    def withRadix(self, radix):
        return MakeInt(radix)

    @profileTyphon("_makeInt.fromBytes/2")
    def fromBytes(self, bs, ej):
        # Ruby-style underscores are legal here but can't be handled by
        # RPython, so remove them.
        bs = ''.join([c for c in bs if c != '_'])
        try:
            return rbigint.fromstr(bs, self.radix)
        except ParseStringError:
            throw(ej, StrObject(u"_makeInt: Couldn't make int in radix %d from %s" %
                (self.radix, bytesToString(bs))))

    def recv(self, atom, args):
        if atom is WITHRADIX_1:
            radix = unwrapInt(args[0])
            return self.withRadix(radix)

        if atom is RUN_1:
            bs = unwrapStr(args[0]).encode("utf-8")
            return BigInt(self.fromBytes(bs, None))

        if atom is RUN_2:
            bs = unwrapStr(args[0]).encode("utf-8")
            return BigInt(self.fromBytes(bs, args[1]))

        if atom is FROMBYTES_1:
            bs = unwrapBytes(args[0])
            return BigInt(self.fromBytes(bs, None))

        if atom is FROMBYTES_2:
            bs = unwrapBytes(args[0])
            return BigInt(self.fromBytes(bs, args[1]))

        raise Refused(self, atom, args)
theMakeInt = MakeInt(10)


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

    @deprecated(u"_makeStr.fromString/1: Use .fromStr/1 instead")
    def fromString(self, s):
        return self.fromStr(s)

    def fromStr(self, s):
        return StrObject(s)

    def recv(self, atom, args):
        if atom is FROMSTRING_1:
            return self.fromString(unwrapStr(args[0]))

        if atom is FROMSTR_1:
            return self.fromStr(unwrapStr(args[0]))

        if atom is FROMSTRING_2:
            # XXX handle twineishness
            return self.fromString(unwrapStr(args[0]))

        if atom is FROMSTR_2:
            # XXX handle twineishness
            return self.fromStr(unwrapStr(args[0]))

        if atom is FROMCHARS_1:
            data = unwrapList(args[0])
            return StrObject(u"".join([unwrapChar(c) for c in data]))

        raise Refused(self, atom, args)
theMakeStr = MakeStr()
