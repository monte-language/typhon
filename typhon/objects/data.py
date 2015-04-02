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

from rpython.rlib.rbigint import BASE10, rbigint
from rpython.rlib.jit import elidable
from rpython.rlib.objectmodel import _hash_float, specialize
from rpython.rlib.rarithmetic import LONG_BIT, intmask, ovfcheck
from rpython.rlib.rstring import UnicodeBuilder, split
from rpython.rlib.unicodedata import unicodedb_6_2_0 as unicodedb

from typhon.atoms import getAtom
from typhon.errors import Refused, WrongType, userError
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
ASLIST_0 = getAtom(u"asList", 0)
ASSET_0 = getAtom(u"asSet", 0)
ASSTRING_0 = getAtom(u"asString", 0)
ATLEASTZERO_0 = getAtom(u"atLeastZero", 0)
ATMOSTZERO_0 = getAtom(u"atMostZero", 0)
BELOWZERO_0 = getAtom(u"belowZero", 0)
BITLENGTH_0 = getAtom(u"bitLength", 0)
COMPLEMENT_0 = getAtom(u"complement", 0)
CONTAINS_1 = getAtom(u"contains", 1)
COS_0 = getAtom(u"cos", 0)
FLOORDIVIDE_1 = getAtom(u"floorDivide", 1)
GETCATEGORY_0 = getAtom(u"getCategory", 0)
GET_1 = getAtom(u"get", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
ISZERO_0 = getAtom(u"isZero", 0)
JOIN_1 = getAtom(u"join", 1)
LASTINDEXOF_1 = getAtom(u"lastIndexOf", 1)
MAX_1 = getAtom(u"max", 1)
MIN_1 = getAtom(u"min", 1)
MODPOW_2 = getAtom(u"modPow", 2)
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
XOR_1 = getAtom(u"xor", 1)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)


@specialize.argtype(0, 1)
def polyCmp(l, r):
    if l < r:
        return IntObject(-1)
    elif l > r:
        return IntObject(1)
    else:
        return IntObject(0)


class CharObject(Object):

    _immutable_fields_ = "stamps", "_c"

    displayName = u"CharObject"

    stamps = [DeepFrozenStamp]

    def __init__(self, c):
        # RPython needs to be reminded that, no matter what, we are always
        # using a single character here.
        self._c = c[0]

    def toString(self):
        return unicode(self._c)

    def toQuote(self):
        return quoteChar(self._c)

    def hash(self):
        # Don't waste time with the traditional string hash.
        return ord(self._c)

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

        if atom is OP__CMP_1:
            return polyCmp(self._c, unwrapChar(args[0]))

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
    raise WrongType(u"Not a char!")


class DoubleObject(Object):

    _immutable_fields_ = "stamps", "_d"

    displayName = u"DoubleObject"

    stamps = [DeepFrozenStamp]

    def __init__(self, d):
        self._d = d

    def toString(self):
        return u"%f" % (self._d,)

    def hash(self):
        return _hash_float(self._d)

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


def unwrapDouble(o):
    from typhon.objects.refs import resolution
    d = resolution(o)
    if isinstance(d, DoubleObject):
        return d.getDouble()
    raise WrongType(u"Not a double!")


def promoteToDouble(o):
    from typhon.objects.refs import resolution
    n = resolution(o)
    if isinstance(n, IntObject):
        return float(n.getInt())
    if isinstance(n, DoubleObject):
        return n.getDouble()
    raise WrongType(u"Failed to promote to double")


class IntObject(Object):

    _immutable_fields_ = "stamps", "_i"

    displayName = u"IntObject"

    _i = 0

    stamps = [DeepFrozenStamp]

    def __init__(self, i):
        self._i = i

    def toString(self):
        return u"%d" % self._i

    def hash(self):
        # This is what CPython and RPython do.
        return self._i

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
            try:
                i = unwrapInt(other)
                return IntObject(ovfcheck(self._i + i))
            except OverflowError:
                i = unwrapInt(other)
                return BigInt(rbigint.fromint(self._i).int_add(i))
            except WrongType:
                try:
                    # Addition commutes.
                    return BigInt(unwrapBigInt(other).int_add(self._i))
                except WrongType:
                    return DoubleObject(self._i + unwrapDouble(other))

        if atom is AND_1:
            try:
                other = unwrapInt(args[0])
                return IntObject(self._i & other)
            except WrongType:
                other = unwrapBigInt(args[0])
                return BigInt(other.int_and_(self._i))

        if atom is APPROXDIVIDE_1:
            # approxDivide/1: Promote both this int and its argument to
            # double, then perform division.
            d = float(self._i)
            other = promoteToDouble(args[0])
            return DoubleObject(d / other)

        if atom is BITLENGTH_0:
            # bitLength/0: The number of bits required to store this integer.
            # Cribbed from PyPy.
            i = self._i
            rv = 0
            if i < 0:
                i = -((i + 1) >> 1)
                rv = 1
            while i:
                rv += 1
                i >>= 1
            return IntObject(rv)

        if atom is COMPLEMENT_0:
            return IntObject(~self._i)

        if atom is FLOORDIVIDE_1:
            other = unwrapInt(args[0])
            return IntObject(self._i // other)

        if atom is MAX_1:
            other = unwrapInt(args[0])
            return self if self._i > other else args[0]

        if atom is MIN_1:
            other = unwrapInt(args[0])
            return self if self._i < other else args[0]

        if atom is MODPOW_2:
            exponent = unwrapInt(args[0])
            modulus = unwrapInt(args[1])
            try:
                return self.intModPow(exponent, modulus)
            except OverflowError:
                return BigInt(rbigint.fromint(self._i).pow(rbigint.fromint(exponent),
                                                           rbigint.fromint(modulus)))

        if atom is MOD_1:
            other = unwrapInt(args[0])
            return IntObject(self._i % other)

        if atom is MULTIPLY_1:
            other = args[0]
            try:
                i = unwrapInt(other)
                return IntObject(ovfcheck(self._i * i))
            except OverflowError:
                i = unwrapInt(other)
                return BigInt(rbigint.fromint(self._i).int_mul(i))
            except WrongType:
                try:
                    # Multiplication commutes.
                    return BigInt(unwrapBigInt(other).int_mul(self._i))
                except WrongType:
                    return DoubleObject(self._i * unwrapDouble(other))

        if atom is NEGATE_0:
            return IntObject(-self._i)

        if atom is NEXT_0:
            return IntObject(self._i + 1)

        if atom is OR_1:
            try:
                other = unwrapInt(args[0])
                return IntObject(self._i | other)
            except WrongType:
                other = unwrapBigInt(args[0])
                return BigInt(other.int_or_(self._i))

        if atom is POW_1:
            other = unwrapInt(args[0])
            try:
                return self.intPow(other)
            except OverflowError:
                return BigInt(rbigint.fromint(self._i).pow(rbigint.fromint(other)))

        if atom is PREVIOUS_0:
            return IntObject(self._i - 1)

        if atom is SHIFTLEFT_1:
            other = unwrapInt(args[0])
            try:
                return IntObject(ovfcheck(self._i << other))
            except OverflowError:
                return BigInt(rbigint.fromint(self._i).lshift(other))

        if atom is SHIFTRIGHT_1:
            other = unwrapInt(args[0])
            if other >= LONG_BIT:
                # This'll underflow, returning who-knows-what when translated.
                # To keep things reasonable, we define an int that has been
                # right-shifted past word width to be 0, since every bit has
                # been shifted off.
                return IntObject(0)
            return IntObject(self._i >> other)

        if atom is SUBTRACT_1:
            other = args[0]
            try:
                i = unwrapInt(other)
                return IntObject(ovfcheck(self._i - i))
            except OverflowError:
                i = unwrapInt(other)
                return BigInt(rbigint.fromint(self._i).int_sub(i))
            except WrongType:
                try:
                    # Subtraction doesn't commute, so we have to work a little
                    # harder.
                    bi = unwrapBigInt(other)
                    return BigInt(rbigint.fromint(self._i).sub(bi))
                except WrongType:
                    return DoubleObject(self._i - unwrapDouble(other))

        if atom is XOR_1:
            try:
                other = unwrapInt(args[0])
                return IntObject(self._i ^ other)
            except WrongType:
                other = unwrapBigInt(args[0])
                return BigInt(other.int_xor(self._i))

        raise Refused(self, atom, args)

    def getInt(self):
        return self._i

    def intPow(self, exponent):
        accumulator = 1
        multiplier = self._i
        while exponent > 0:
            if exponent & 1:
                # Odd bit.
                accumulator = ovfcheck(accumulator * multiplier)
            exponent >>= 1
            if not exponent:
                break
            multiplier = ovfcheck(multiplier * multiplier)
        return IntObject(accumulator)

    def intModPow(self, exponent, modulus):
        accumulator = 1
        multiplier = self._i % modulus
        while exponent > 0:
            if exponent & 1:
                # Odd bit.
                accumulator = ovfcheck(accumulator * multiplier) % modulus
            exponent >>= 1
            if not exponent:
                break
            multiplier = ovfcheck(multiplier * multiplier) % modulus
        return IntObject(accumulator)


def unwrapInt(o):
    from typhon.objects.refs import resolution
    i = resolution(o)
    if isinstance(i, IntObject):
        return i.getInt()
    if isinstance(i, BigInt):
        try:
            return i.bi.toint()
        except OverflowError:
            pass
    raise WrongType(u"Not an integer!")


class BigInt(Object):
    """
    An arbitrarily large integer object which is indistinguishable from an
    ordinary IntObject at the Monte application level.
    """

    _immutable_ = True
    _immutable_fields_ = "stamps[*]", "bi"

    displayName = u"BigInt"
    stamps = [DeepFrozenStamp]

    def __init__(self, bi):
        self.bi = bi

    def toString(self):
        return self.bi.format(BASE10).decode("utf-8")

    def hash(self):
        return self.bi.hash()

    def recv(self, atom, args):
        # Bigints can be compared with bigints and ints.
        if atom is OP__CMP_1:
            other = args[0]
            try:
                return IntObject(self.cmp(unwrapBigInt(other)))
            except WrongType:
                return IntObject(self.cmpInt(unwrapInt(other)))

        # Nothing prevents bigints from being returned from comparisons, but
        # I'd like to avoid generating this code for now. ~ C.
        # if atom is ABOVEZERO_0:
        #     return wrapBool(self._i > 0)
        # if atom is ATLEASTZERO_0:
        #     return wrapBool(self._i >= 0)
        # if atom is ATMOSTZERO_0:
        #     return wrapBool(self._i <= 0)
        # if atom is BELOWZERO_0:
        #     return wrapBool(self._i < 0)
        # if atom is ISZERO_0:
        #     return wrapBool(self._i == 0)

        if atom is ABS_0:
            return BigInt(self.bi.abs())

        if atom is ADD_1:
            other = args[0]
            try:
                return BigInt(self.bi.add(unwrapBigInt(other)))
            except WrongType:
                try:
                    return BigInt(self.bi.int_add(unwrapInt(other)))
                except WrongType:
                    return DoubleObject(self.bi.tofloat() +
                                        unwrapDouble(other))

        if atom is AND_1:
            other = args[0]
            try:
                return BigInt(self.bi.and_(unwrapBigInt(other)))
            except WrongType:
                return BigInt(self.bi.int_and_(unwrapInt(other)))

        if atom is APPROXDIVIDE_1:
            # approxDivide/1: Promote both this int and its argument to
            # double, then perform division.
            other = promoteToBigInt(args[0])
            # The actual division is performed within the bigint.
            d = self.bi.truediv(other)
            return DoubleObject(d)

        if atom is BITLENGTH_0:
            return IntObject(self.bi.bit_length())

        if atom is COMPLEMENT_0:
            return BigInt(self.bi.invert())

        if atom is FLOORDIVIDE_1:
            other = promoteToBigInt(args[0])
            return BigInt(self.bi.floordiv(other))

        if atom is MAX_1:
            # XXX could specialize for ints
            other = promoteToBigInt(args[0])
            return self if self.bi.gt(other) else args[0]

        if atom is MIN_1:
            # XXX could specialize for ints
            other = promoteToBigInt(args[0])
            return self if self.bi.lt(other) else args[0]

        if atom is MOD_1:
            other = args[0]
            try:
                return BigInt(self.bi.mod(unwrapBigInt(other)))
            except WrongType:
                return BigInt(self.bi.int_mod(unwrapInt(other)))

        if atom is MULTIPLY_1:
            # XXX doubles
            other = args[0]
            try:
                return BigInt(self.bi.mul(unwrapBigInt(other)))
            except WrongType:
                return BigInt(self.bi.int_mul(unwrapInt(other)))

        if atom is NEGATE_0:
            return BigInt(self.bi.neg())

        if atom is NEXT_0:
            return BigInt(self.bi.int_add(1))

        if atom is OR_1:
            other = args[0]
            try:
                return BigInt(self.bi.or_(unwrapBigInt(other)))
            except WrongType:
                return BigInt(self.bi.int_or_(unwrapInt(other)))

        if atom is POW_1:
            other = promoteToBigInt(args[0])
            return BigInt(self.bi.pow(other))

        if atom is PREVIOUS_0:
            return BigInt(self.bi.int_sub(1))

        if atom is SHIFTLEFT_1:
            other = unwrapInt(args[0])
            return BigInt(self.bi.lshift(other))

        if atom is SHIFTRIGHT_1:
            other = unwrapInt(args[0])
            return BigInt(self.bi.rshift(other))

        if atom is SUBTRACT_1:
            other = args[0]
            try:
                return BigInt(self.bi.sub(unwrapBigInt(other)))
            except WrongType:
                try:
                    return BigInt(self.bi.int_sub(unwrapInt(other)))
                except WrongType:
                    return DoubleObject(self.bi.tofloat() -
                                        unwrapDouble(other))

        if atom is XOR_1:
            other = args[0]
            try:
                return BigInt(self.bi.xor(unwrapBigInt(other)))
            except WrongType:
                return BigInt(self.bi.int_xor(unwrapInt(other)))

        raise Refused(self, atom, args)

    def cmp(self, other):
        if self.bi.lt(other):
            return -1
        elif self.bi.gt(other):
            return 1
        else:
            # Using a property of integers here.
            return 0

    def cmpInt(self, other):
        if self.bi.int_lt(other):
            return -1
        elif self.bi.int_gt(other):
            return 1
        else:
            # Using a property of integers here.
            return 0


def unwrapBigInt(o):
    from typhon.objects.refs import resolution
    bi = resolution(o)
    if isinstance(bi, BigInt):
        return bi.bi
    raise WrongType(u"Not a big integer!")


def promoteToBigInt(o):
    from typhon.objects.refs import resolution
    i = resolution(o)
    if isinstance(i, BigInt):
        return i.bi
    if isinstance(i, IntObject):
        return rbigint.fromint(i.getInt())
    raise WrongType(u"Not promotable to big integer!")


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

    displayName = u"StrObject"

    stamps = [DeepFrozenStamp]

    def __init__(self, s):
        self._s = s

    def toString(self):
        return self._s

    def toQuote(self):
        return quoteStr(self._s)

    def hash(self):
        # Cribbed from RPython's _hash_string.
        length = len(self._s)
        if length == 0:
            return -1
        x = ord(self._s[0]) << 7
        i = 0
        while i < length:
            x = intmask((1000003 * x) ^ ord(self._s[i]))
            i += 1
        x ^= length
        return intmask(x)

    def recv(self, atom, args):
        if atom is ADD_1:
            other = args[0]
            if isinstance(other, StrObject):
                return StrObject(self._s + other._s)
            if isinstance(other, CharObject):
                return StrObject(self._s + unicode(other._c))

        if atom is ASLIST_0:
            from typhon.objects.collections import ConstList
            return ConstList([CharObject(c) for c in self._s])

        if atom is ASSET_0:
            from typhon.objects.collections import ConstSet, monteDict
            d = monteDict()
            for c in self._s:
                d[CharObject(c)] = None
            return ConstSet(d)

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

        if atom is INDEXOF_1:
            needle = unwrapStr(args[0])
            return IntObject(self._s.find(needle))

        if atom is JOIN_1:
            from typhon.objects.collections import unwrapList
            l = unwrapList(args[0])
            ub = UnicodeBuilder()
            first = True
            for s in l:
                # For all iterations except the first, append a copy of
                # ourselves.
                if first:
                    first = False
                else:
                    ub.append(self._s)

                string = unwrapStr(s)

                ub.append(string)
            return StrObject(ub.build())

        if atom is LASTINDEXOF_1:
            needle = unwrapStr(args[0])
            return IntObject(self._s.rfind(needle))

        if atom is MULTIPLY_1:
            amount = args[0]
            if isinstance(amount, IntObject):
                return StrObject(self._s * amount._i)

        if atom is OP__CMP_1:
            return polyCmp(self._s, unwrapStr(args[0]))

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
    raise WrongType(u"Not a string!")
