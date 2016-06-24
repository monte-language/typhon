"""
Miscellaneous makers in the safe scope.
"""

from rpython.rlib.rbigint import rbigint
from rpython.rlib.rstring import ParseStringError
from rpython.rlib.rstruct.ieee import unpack_float

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import listFromIterable
from typhon.objects.collections.maps import ConstMap
from typhon.objects.data import (StrObject, bytesToString, unwrapInt,
        unwrapChar)
from typhon.objects.ejectors import throw
from typhon.objects.root import Object, audited, runnable
from typhon.profile import profileTyphon


FROMPAIRS_1 = getAtom(u"fromPairs", 1)


@autohelp
@audited.DF
class MakeBytes(Object):
    """
    The maker of `Bytes`.
    """

    def toString(self):
        return u"<makeBytes>"

    @method("Bytes", "Str")
    def fromStr(self, s):
        return "".join([chr(ord(c)) for c in s])

    @method("Bytes", "List")
    def fromInts(self, data):
        return "".join([chr(unwrapInt(i)) for i in data])

theMakeBytes = MakeBytes()


@autohelp
@audited.DF
class MakeDouble(Object):
    """
    The maker of `Double`s.
    """

    def toString(self):
        return u"<makeDouble>"

    @method.py("Double", "Str", "Any")
    def run(self, s, ej):
        try:
            return float(s.encode("utf-8"))
        except ValueError:
            throw(ej, StrObject(u"Couldn't parse floating-point number"))

    @method("Double", "Str", _verb="run")
    def _run(self, s):
        return self.run(s, None)

    @method.py("Double", "Bytes", "Any")
    def fromBytes(self, bs, ej):
        try:
            return unpack_float(bs, True)
        except ValueError:
            throw(ej, StrObject(u"Couldn't unpack invalid IEEE 754 double"))

    @method("Double", "Bytes", _verb="fromBytes")
    def _fromBytes(self, bs):
        return self.fromBytes(bs, None)

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

    @method("Any", "Int")
    def withRadix(self, radix):
        return MakeInt(radix)

    @method("BigInt", "Str", _verb="run")
    def runThrow(self, s):
        bs = s.encode("utf-8")
        return self.fromBytes(bs, None)

    @method("BigInt", "Str", "Any")
    def run(self, s, ej):
        bs = s.encode("utf-8")
        return self.fromBytes(bs, ej)

    @method("BigInt", "Bytes", _verb="fromBytes")
    def fromBytesThrow(self, bs):
        return self.fromBytes(bs, None)

    @method("BigInt", "Bytes", "Any", _verb="fromBytes")
    def fromBytesEj(self, bs, ej):
        return self.fromBytes(bs, ej)

theMakeInt = MakeInt(10)


@autohelp
@audited.DF
class MakeList(Object):
    """
    The maker of `List`s.
    """

    def toString(self):
        return u"<makeList>"

    @method("List", "*Any")
    def run(self, args):
        return args

    @method("List", "Any")
    def fromIterable(self, iterable):
        return listFromIterable(iterable)

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

    @method("Str", "Str")
    def fromStr(self, s):
        return s

    @method("Str", "Str", "Any", _verb="fromStr")
    def fromStrSpan(self, s, span):
        # XXX handle twineishness
        return s

    @method("Str", "List")
    def fromChars(self, data):
        return u"".join([unwrapChar(c) for c in data])

theMakeStr = MakeStr()
