# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import math

from rpython.rlib.jit import elidable
from rpython.rlib.objectmodel import specialize
from rpython.rlib.rarithmetic import ovfcheck
from rpython.rlib.rstring import UnicodeBuilder, split
from rpython.rlib.unicodedata import unicodedb_6_2_0 as unicodedb

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.auditors import DeepFrozenStamp
from typhon.objects.constants import wrapBool
from typhon.objects.root import Object
from typhon.quoting import quoteChar, quoteStr


ABOVEZERO_0 = getAtom(u"aboveZero", 0)
ABS_0 = getAtom(u"abs", 0)
ADD_1 = getAtom(u"add", 1)
AND_1 = getAtom(u"and", 1)
APPROXDIVIDE_1 = getAtom(u"approxDivide", 1)
ASINTEGER_0 = getAtom(u"asInteger", 0)
ASSTRING_0 = getAtom(u"asString", 0)
ATLEASTZERO_0 = getAtom(u"atLeastZero", 0)
ATMOSTZERO_0 = getAtom(u"atMostZero", 0)
BELOWZERO_0 = getAtom(u"belowZero", 0)
CONTAINS_1 = getAtom(u"contains", 1)
COS_0 = getAtom(u"cos", 0)
FLOORDIVIDE_1 = getAtom(u"floorDivide", 1)
GETCATEGORY_0 = getAtom(u"getCategory", 0)
GET_1 = getAtom(u"get", 1)
ISZERO_0 = getAtom(u"isZero", 0)
JOIN_1 = getAtom(u"join", 1)
MAX_1 = getAtom(u"max", 1)
MIN_1 = getAtom(u"min", 1)
MOD_1 = getAtom(u"mod", 1)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEGATE_0 = getAtom(u"negate", 0)
NEXT_0 = getAtom(u"next", 0)
NEXT_1 = getAtom(u"next", 1)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
POW_1 = getAtom(u"pow", 1)
PREVIOUS_0 = getAtom(u"previous", 0)
SHIFTLEFT_1 = getAtom(u"shiftLeft", 1)
SHIFTRIGHT_1 = getAtom(u"shiftRight", 1)
SIN_0 = getAtom(u"sin", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SPLIT_1 = getAtom(u"split", 1)
SPLIT_2 = getAtom(u"split", 2)
SQRT_0 = getAtom(u"sqrt", 0)
SUBTRACT_1 = getAtom(u"subtract", 1)
TAN_0 = getAtom(u"tan", 0)
TOLOWERCASE_0 = getAtom(u"toLowerCase", 0)
TOUPPERCASE_0 = getAtom(u"toUpperCase", 0)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)


class CharObject(Object):

    _immutable_fields_ = "stamps", "_c"

    stamps = [DeepFrozenStamp]

    def __init__(self, c):
        # RPython needs to be reminded that, no matter what, we are always
        # using a single character here.
        self._c = c[0]

    def toString(self):
        return unicode(self._c)

    def toQuote(self):
        return quoteChar(self._c)

    def recv(self, atom, args):
        if atom is ADD_1:
            other = unwrapInt(args[0])
            return self.withOffset(other)

        if atom is ASINTEGER_0:
            return IntObject(ord(self._c))

        if atom is ASSTRING_0:
            return StrObject(unicode(self._c))

        if atom is GETCATEGORY_0:
            return StrObject(unicode(unicodedb.category(ord(self._c))))

        if atom is MAX_1:
            other = unwrapChar(args[0])
            return self if self._c > other else args[0]

        if atom is MIN_1:
            other = unwrapChar(args[0])
            return self if self._c < other else args[0]

        if atom is NEXT_0:
            return self.withOffset(1)

        if atom is PREVIOUS_0:
            return self.withOffset(-1)

        if atom is SUBTRACT_1:
            other = unwrapInt(args[0])
            return self.withOffset(-other)

        raise Refused(self, atom, args)

    def withOffset(self, offset):
        return CharObject(unichr(ord(self._c) + offset))

    def getChar(self):
        return self._c


def unwrapChar(o):
    from typhon.objects.refs import resolution
    c = resolution(o)
    if isinstance(c, CharObject):
        return c.getChar()
    raise userError(u"Not a char!")


def promoteToDouble(o):
    from typhon.objects.refs import resolution
    n = resolution(o)
    if isinstance(n, IntObject):
        return float(n.getInt())
    if isinstance(n, DoubleObject):
        return n.getDouble()
    raise userError(u"Failed to promote to double")


@specialize.argtype(0, 1)
def polyCmp(l, r):
    if l < r:
        return IntObject(-1)
    elif l > r:
        return IntObject(1)
    else:
        return IntObject(0)


class DoubleObject(Object):

    _immutable_fields_ = "stamps", "_d"

    stamps = [DeepFrozenStamp]

    def __init__(self, d):
        self._d = d

    def toString(self):
        return u"%f" % (self._d,)

    def recv(self, atom, args):
        # Doubles can be compared.
        if atom is OP__CMP_1:
            other = promoteToDouble(args[0])
            return polyCmp(self._d, other)

        if atom is ABS_0:
            return DoubleObject(abs(self._d))

        if atom is ADD_1:
            return self.add(args[0])

        if atom is MULTIPLY_1:
            return self.mul(args[0])

        if atom is NEGATE_0:
            return DoubleObject(-self._d)

        if atom is SQRT_0:
            return DoubleObject(math.sqrt(self._d))

        if atom is SUBTRACT_1:
            return self.subtract(args[0])

        # Trigonometry.

        if atom is SIN_0:
            return DoubleObject(math.sin(self._d))

        if atom is COS_0:
            return DoubleObject(math.cos(self._d))

        if atom is TAN_0:
            return DoubleObject(math.tan(self._d))

        raise Refused(self, atom, args)

    @elidable
    def add(self, other):
        return DoubleObject(self._d + promoteToDouble(other))

    @elidable
    def mul(self, other):
        return DoubleObject(self._d * promoteToDouble(other))

    @elidable
    def subtract(self, other):
        return DoubleObject(self._d - promoteToDouble(other))

    def getDouble(self):
        return self._d


class IntObject(Object):

    _immutable_fields_ = "stamps", "_i"

    _i = 0

    stamps = [DeepFrozenStamp]

    def __init__(self, i=0):
        self._i = i

    def toString(self):
        return u"%d" % self._i

    def recv(self, atom, args):
        # Ints can be compared.
        if atom is OP__CMP_1:
            other = unwrapInt(args[0])
            return polyCmp(self._i, other)

        # Ints are usually used to store the results of comparisons.
        if atom is ABOVEZERO_0:
            return wrapBool(self._i > 0)
        if atom is ATLEASTZERO_0:
            return wrapBool(self._i >= 0)
        if atom is ATMOSTZERO_0:
            return wrapBool(self._i <= 0)
        if atom is BELOWZERO_0:
            return wrapBool(self._i < 0)
        if atom is ISZERO_0:
            return wrapBool(self._i == 0)

        if atom is ADD_1:
            other = args[0]
            if isinstance(other, DoubleObject):
                # Addition commutes.
                return other.add(self)
            return IntObject(self._i + unwrapInt(other))

        if atom is AND_1:
            other = unwrapInt(args[0])
            return IntObject(self._i & other)

        if atom is APPROXDIVIDE_1:
            # approxDivide/1: Promote both this int and its argument to
            # double, then perform division.
            d = float(self._i)
            other = promoteToDouble(args[0])
            return DoubleObject(d / other)

        if atom is FLOORDIVIDE_1:
            other = unwrapInt(args[0])
            return IntObject(self._i // other)

        if atom is MAX_1:
            other = unwrapInt(args[0])
            return self if self._i > other else args[0]

        if atom is MIN_1:
            other = unwrapInt(args[0])
            return self if self._i < other else args[0]

        if atom is MOD_1:
            other = unwrapInt(args[0])
            return IntObject(self._i % other)

        if atom is MULTIPLY_1:
            other = args[0]
            if isinstance(other, DoubleObject):
                # Multiplication commutes.
                return other.mul(self)
            return IntObject(self._i * unwrapInt(other))

        if atom is NEGATE_0:
            return IntObject(-self._i)

        if atom is NEXT_0:
            return IntObject(self._i + 1)

        if atom is OR_1:
            other = unwrapInt(args[0])
            return IntObject(self._i | other)

        if atom is POW_1:
            other = unwrapInt(args[0])
            return self.intPow(other)

        if atom is PREVIOUS_0:
            return IntObject(self._i - 1)

        if atom is SHIFTLEFT_1:
            other = unwrapInt(args[0])
            return IntObject(self._i << other)

        if atom is SHIFTRIGHT_1:
            other = unwrapInt(args[0])
            return IntObject(self._i >> other)

        if atom is SUBTRACT_1:
            other = args[0]
            if isinstance(other, DoubleObject):
                # Promote ourselves to double and retry.
                return DoubleObject(float(self._i)).subtract(other)
            return IntObject(self._i - unwrapInt(other))

        raise Refused(self, atom, args)

    def getInt(self):
        return self._i

    def intPow(self, exponent):
        # XXX implement the algo in pypy.objspace.std.intobject, or
        # port it to rlib (per arigato)
        accumulator = 1
        # XXX only correct for positive exponents
        while (exponent > 0):
            accumulator = ovfcheck(accumulator * self._i)
            exponent -= 1
        return IntObject(accumulator)


def unwrapInt(o):
    from typhon.objects.refs import resolution
    i = resolution(o)
    if isinstance(i, IntObject):
        return i.getInt()
    raise userError(u"Not an integer!")


class strIterator(Object):

    _immutable_fields_ = "s",

    _index = 0

    def __init__(self, s):
        self.s = s

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < len(self.s):
                from typhon.objects.collections import ConstList
                rv = [IntObject(self._index), CharObject(self.s[self._index])]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


class StrObject(Object):

    _immutable_fields_ = "stamps[*]", "_s"

    stamps = [DeepFrozenStamp]

    def __init__(self, s):
        self._s = s

    def toString(self):
        return self._s

    def toQuote(self):
        return quoteStr(self._s)

    def recv(self, atom, args):
        if atom is ADD_1:
            other = args[0]
            if isinstance(other, StrObject):
                return StrObject(self._s + other._s)
            if isinstance(other, CharObject):
                return StrObject(self._s + unicode(other._c))

        if atom is CONTAINS_1:
            needle = args[0]
            if isinstance(needle, CharObject):
                return wrapBool(needle._c in self._s)
            if isinstance(needle, StrObject):
                return wrapBool(needle._s in self._s)

        if atom is GET_1:
            index = unwrapInt(args[0])
            if not 0 <= index < len(self._s):
                raise userError(u"string.get/1: Index out of bounds: %d" %
                                index)
            return CharObject(self._s[index])

        if atom is JOIN_1:
            l = args[0]
            from typhon.objects.collections import ConstList, unwrapList
            if isinstance(l, ConstList):
                ub = UnicodeBuilder()
                strs = []
                first = True
                for s in unwrapList(l):
                    # For all iterations except the first, append a copy of
                    # ourselves.
                    if first:
                        first = False
                    else:
                        ub.append(self._s)

                    string = unwrapStr(s)
                    ub.append(string)
                return StrObject(ub.build())

        if atom is MULTIPLY_1:
            amount = args[0]
            if isinstance(amount, IntObject):
                return StrObject(self._s * amount._i)

        if atom is SIZE_0:
            return IntObject(len(self._s))

        if atom is SLICE_1:
            start = unwrapInt(args[0])
            if start < 0:
                raise userError(u"Slice start cannot be negative")
            return StrObject(self._s[start:])

        if atom is SLICE_2:
            start = unwrapInt(args[0])
            stop = unwrapInt(args[1])
            if start < 0:
                raise userError(u"Slice start cannot be negative")
            if stop < 0:
                raise userError(u"Slice stop cannot be negative")
            return StrObject(self._s[start:stop])

        if atom is SPLIT_1:
            from typhon.objects.collections import ConstList
            splitter = unwrapStr(args[0])
            strings = [StrObject(s) for s in split(self._s, splitter)]
            return ConstList(strings)

        if atom is SPLIT_2:
            splitter = unwrapStr(args[0])
            splits = unwrapInt(args[1])
            from typhon.objects.collections import ConstList
            strings = [StrObject(s) for s in split(self._s, splitter, splits)]
            return ConstList(strings)

        if atom is TOLOWERCASE_0:
            # Use current size as a size hint. In the best case, characters
            # are one-to-one; in the next-best case, we overestimate and end
            # up with a couple bytes of slop.
            ub = UnicodeBuilder(len(self._s))
            for char in self._s:
                ub.append(unichr(unicodedb.tolower(ord(char))))
            return StrObject(ub.build())

        if atom is TOUPPERCASE_0:
            ub = UnicodeBuilder(len(self._s))
            for char in self._s:
                ub.append(unichr(unicodedb.toupper(ord(char))))
            return StrObject(ub.build())

        if atom is _MAKEITERATOR_0:
            return strIterator(self._s)

        raise Refused(self, atom, args)

    def getString(self):
        return self._s


def unwrapStr(o):
    from typhon.objects.refs import resolution
    s = resolution(o)
    if isinstance(s, StrObject):
        return s.getString()
    raise userError(u"Not a string!")
