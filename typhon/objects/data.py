# encoding: utf-8
#
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
import string

from rpython.rlib import rgc
from rpython.rlib.rbigint import BASE10, rbigint
from rpython.rlib.jit import elidable
from rpython.rlib.objectmodel import _hash_float, specialize
from rpython.rlib.rarithmetic import LONG_BIT, intmask, ovfcheck
from rpython.rlib.rstring import StringBuilder, UnicodeBuilder, replace, split
from rpython.rlib.rstruct.ieee import pack_float
from rpython.rlib.unicodedata import unicodedb_6_2_0 as unicodedb

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import Refused, WrongType, userError
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.comparison import Incomparable
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.root import Object, audited, runnable
from typhon.prelude import getGlobalValue
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
COMBINE_1 = getAtom(u"combine", 1)
COMPLEMENT_0 = getAtom(u"complement", 0)
CONTAINS_1 = getAtom(u"contains", 1)
COS_0 = getAtom(u"cos", 0)
ENDSWITH_1 = getAtom(u"endsWith", 1)
FLOORDIVIDE_1 = getAtom(u"floorDivide", 1)
FLOOR_0 = getAtom(u"floor", 0)
GETCATEGORY_0 = getAtom(u"getCategory", 0)
GET_1 = getAtom(u"get", 1)
GETSPAN_0 = getAtom(u"getSpan", 0)
GETSTARTCOL_0 = getAtom(u"getStartCol", 0)
GETENDCOL_0 = getAtom(u"getEndCol", 0)
GETSTARTLINE_0 = getAtom(u"getStartLine", 0)
GETENDLINE_0 = getAtom(u"getEndLine", 0)
INDEXOF_1 = getAtom(u"indexOf", 1)
INDEXOF_2 = getAtom(u"indexOf", 2)
ISONETOONE_0 = getAtom(u"isOneToOne", 0)
ISZERO_0 = getAtom(u"isZero", 0)
JOIN_1 = getAtom(u"join", 1)
LASTINDEXOF_1 = getAtom(u"lastIndexOf", 1)
LOG_0 = getAtom(u"log", 0)
LOG_1 = getAtom(u"log", 1)
MAX_1 = getAtom(u"max", 1)
MIN_1 = getAtom(u"min", 1)
MODPOW_2 = getAtom(u"modPow", 2)
MOD_1 = getAtom(u"mod", 1)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEGATE_0 = getAtom(u"negate", 0)
NEXT_0 = getAtom(u"next", 0)
NEXT_1 = getAtom(u"next", 1)
NOTONETOONE_0 = getAtom(u"notOneToOne", 0)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
POW_1 = getAtom(u"pow", 1)
PREVIOUS_0 = getAtom(u"previous", 0)
REPLACE_2 = getAtom(u"replace", 2)
RUN_6 = getAtom(u"run", 6)
QUOTE_0 = getAtom(u"quote", 0)
SHIFTLEFT_1 = getAtom(u"shiftLeft", 1)
SHIFTRIGHT_1 = getAtom(u"shiftRight", 1)
SIN_0 = getAtom(u"sin", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SPLIT_1 = getAtom(u"split", 1)
SPLIT_2 = getAtom(u"split", 2)
SQRT_0 = getAtom(u"sqrt", 0)
STARTSWITH_1 = getAtom(u"startsWith", 1)
SUBTRACT_1 = getAtom(u"subtract", 1)
TAN_0 = getAtom(u"tan", 0)
TOLOWERCASE_0 = getAtom(u"toLowerCase", 0)
TOUPPERCASE_0 = getAtom(u"toUpperCase", 0)
TOBYTES_0 = getAtom(u"toBytes", 0)
TRIM_0 = getAtom(u"trim", 0)
WITH_1 = getAtom(u"with", 1)
XOR_1 = getAtom(u"xor", 1)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_UNCALL_0 = getAtom(u"_uncall", 0)


@specialize.argtype(0, 1)
def cmp(l, r):
    if l < r:
        return -1
    elif l > r:
        return 1
    else:
        return 0

@specialize.argtype(0, 1)
def polyCmp(l, r):
    if l < r:
        return IntObject(-1)
    elif l > r:
        return IntObject(1)
    else:
        return IntObject(0)


@autohelp
@audited.DFSelfless
class CharObject(Object):
    """
    A Unicode code point.
    """

    _immutable_fields_ = "_c",

    def __init__(self, c):
        # RPython needs to be reminded that, no matter what, we are always
        # using a single character here.
        self._c = c[0]

    def toString(self):
        return unicode(self._c)

    def toQuote(self):
        return quoteChar(self._c)

    def computeHash(self, depth):
        # Don't waste time with the traditional string hash.
        return ord(self._c)

    def optInterface(self):
        return getGlobalValue(u"Char")

    @method("Char", "Int")
    def add(self, other):
        return self.withOffset(other)

    @method("Int")
    def asInteger(self):
        return ord(self._c)

    @method("Str")
    def asString(self):
        return unicode(self._c)

    @method("Str")
    def getCategory(self):
        return unicode(unicodedb.category(ord(self._c)))

    @method("Char", "Char")
    def max(self, other):
        return max(self._c, other)

    @method("Char", "Char")
    def min(self, other):
        return min(self._c, other)

    @method("Char")
    def next(self):
        return self.withOffset(1)

    @method("Char")
    def previous(self):
        return self.withOffset(-1)

    @method("Int", "Char")
    def op__cmp(self, other):
        return cmp(self._c, other)

    @method("Str")
    def quote(self):
        return quoteChar(self._c)

    @method("Char", "Int")
    def subtract(self, other):
        return self.withOffset(-other)

    def withOffset(self, offset):
        return unichr(ord(self._c) + offset)

    def getChar(self):
        return self._c


def unwrapChar(o):
    from typhon.objects.refs import resolution
    c = resolution(o)
    if isinstance(c, CharObject):
        return c.getChar()
    raise WrongType(u"Not a char!")

def wrapChar(c):
    return CharObject(c)

def isChar(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), CharObject)


@autohelp
@audited.DFSelfless
class DoubleObject(Object):
    """
    An IEEE 754 floating-point number with at least double precision.
    """

    _immutable_fields_ = "_d",

    def __init__(self, d):
        self._d = d

    def toString(self):
        if math.isinf(self._d):
            return u"Infinity" if self._d > 0 else u"-Infinity"
        elif math.isnan(self._d):
            return u"NaN"
        else:
            return u"%f" % (self._d,)

    def computeHash(self, depth):
        return _hash_float(self._d)

    def optInterface(self):
        return getGlobalValue(u"Double")

    @method("Any", "Any")
    def op__cmp(self, other):
        # Doubles can be compared.
        other = promoteToDouble(other)
        # NaN cannot compare equal to any float.
        if math.isnan(self._d) or math.isnan(other):
            return Incomparable
        return polyCmp(self._d, other)

    # Doubles are related to zero.

    @method("Bool")
    def aboveZero(self):
        return self._d > 0.0

    @method("Bool")
    def atLeastZero(self):
        return self._d >= 0.0

    @method("Bool")
    def atMostZero(self):
        return self._d <= 0.0

    @method("Bool")
    def belowZero(self):
        return self._d < 0.0

    @method("Bool")
    def isZero(self):
        return self._d == 0.0

    @method("Double")
    def abs(self):
        return abs(self._d)

    @method("Int")
    def floor(self):
        return int(self._d)

    @method("Double")
    def negate(self):
        return -self._d

    @method("Double")
    def sqrt(self):
        return math.sqrt(self._d)

    @method("Double", "Double")
    def approxDivide(self, divisor):
        return self._d / divisor

    @method("Double", "Int", _verb="approxDivide")
    def approxDivideInt(self, divisor):
        return self._d / divisor

    @method("Int", "Double")
    def floorDivide(self, divisor):
        return int(math.floor(self._d / divisor))

    @method("Int", "Int", _verb="floorDivide")
    def floorDivideInt(self, divisor):
        return int(math.floor(self._d / divisor))

    @method("Double", "Double")
    def pow(self, exponent):
        return math.pow(self._d, exponent)

    @method("Double", "Int", _verb="pow")
    def powInt(self, exponent):
        return math.pow(self._d, exponent)

    # Logarithms.

    @method("Double")
    def log(self):
        return math.log(self._d)

    @method("Double", "Double", _verb="log")
    def logBase(self, base):
        return math.log(self._d) / math.log(base)

    @method("Double", "Int", _verb="log")
    def logBaseInt(self, base):
        return math.log(self._d) / math.log(base)

    # Trigonometry.

    @method("Double")
    def sin(self):
        return math.sin(self._d)

    @method("Double")
    def cos(self):
        return math.cos(self._d)

    @method("Double")
    def tan(self):
        return math.tan(self._d)

    @method("Bytes")
    def toBytes(self):
        result = []
        pack_float(result, self._d, 8, True)
        return result[0]

    @method("Double", "Double")
    def add(self, other):
        return self._d + other

    @method("Double", "Int", _verb="add")
    def addInt(self, other):
        return self._d + other

    @method("Double", "Double")
    def mul(self, other):
        return self._d * other

    @method("Double", "Int", _verb="mul")
    def mulInt(self, other):
        return self._d * other

    @method("Double", "Double")
    def subtract(self, other):
        return self._d - other

    @method("Double", "Int", _verb="subtract")
    def subtractInt(self, other):
        return self._d - other

    def getDouble(self):
        return self._d


# These double objects are prebuilt (and free to use), since building
# on-the-fly floats from strings doesn't work in RPython.
Infinity = DoubleObject(float("inf"))
NaN = DoubleObject(float("nan"))


def unwrapDouble(o):
    from typhon.objects.refs import resolution
    d = resolution(o)
    if isinstance(d, DoubleObject):
        return d.getDouble()
    raise WrongType(u"Not a double!")

def wrapDouble(d):
    return DoubleObject(d)

def isDouble(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), DoubleObject)


def promoteToDouble(o):
    from typhon.objects.refs import resolution
    n = resolution(o)
    if isinstance(n, IntObject):
        return float(n.getInt())
    if isinstance(n, DoubleObject):
        return n.getDouble()
    if isinstance(n, BigInt):
        return n.bi.tofloat()
    raise WrongType(u"Failed to promote to double")


@autohelp
@audited.DFSelfless
class IntObject(Object):
    """
    A numeric value in ℤ.
    """

    _immutable_fields_ = "_i",

    def __init__(self, i):
        self._i = i

    def toString(self):
        return u"%d" % self._i

    def computeHash(self, depth):
        # This is what CPython and RPython do.
        return self._i

    def optInterface(self):
        return getGlobalValue(u"Int")

    def recv(self, atom, args):
        # Ints can be compared to ints and also to doubles.
        if atom is OP__CMP_1:
            try:
                other = unwrapInt(args[0])
                return polyCmp(self._i, other)
            except WrongType:
                try:
                    other = unwrapBigInt(args[0])
                    # This has to be switched around.
                    if other.int_lt(self._i):
                        return IntObject(1)
                    elif other.int_gt(self._i):
                        return IntObject(-1)
                    else:
                        # Using a property of integers here.
                        return IntObject(0)
                except WrongType:
                    other = unwrapDouble(args[0])
                    if math.isnan(other):
                        # Whoa there! Gotta watch out for those pesky NaNs.
                        return Incomparable
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
            try:
                return DoubleObject(d / other)
            except ZeroDivisionError:
                # We tried to divide by zero.
                return NaN

        if atom is BITLENGTH_0:
            # bitLength/0: The number of bits required to store this integer.
            # Cribbed from PyPy.
            return IntObject(self.bitLength())

        if atom is COMPLEMENT_0:
            return IntObject(~self._i)

        if atom is FLOORDIVIDE_1:
            try:
                other = unwrapInt(args[0])
                return IntObject(self._i // other)
            except WrongType:
                other = unwrapBigInt(args[0])
                bi = rbigint.fromint(self._i)
                return BigInt(bi.floordiv(other))
            except ZeroDivisionError:
                raise userError(u"Integer division by zero")

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
                if other >= LONG_BIT:
                    # Definite overflow won't always be detected by
                    # ovfcheck(). Raise manually in this case.
                    raise OverflowError
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

    @elidable
    def bitLength(self):
        i = self._i
        rv = 0
        if i < 0:
            i = -((i + 1) >> 1)
            rv = 1
        while i:
            rv += 1
            i >>= 1
        return rv

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

def wrapInt(i):
    return IntObject(i)

def isInt(obj):
    from typhon.objects.refs import resolution
    obj = resolution(obj)
    return isinstance(obj, IntObject) or isinstance(obj, BigInt)


@autohelp
@audited.DFSelfless
class BigInt(Object):

    __doc__ = IntObject.__doc__

    _immutable_fields_ = "_bi",

    def __init__(self, bi):
        self.bi = bi

    def toString(self):
        return self.bi.format(BASE10).decode("utf-8")

    def computeHash(self, depth):
        return self.bi.hash()

    def optInterface(self):
        return getGlobalValue(u"Int")

    def sizeOf(self):
        return (rgc.get_rpy_memory_usage(self) +
                rgc.get_rpy_memory_usage(self.bi))

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
            # The actual division is performed within the bigint.
            try:
                other = promoteToBigInt(args[0])
                d = self.bi.truediv(other)
                return DoubleObject(d)
            except WrongType:
                # Other object is a double, maybe?
                other = unwrapDouble(args[0])
                return DoubleObject(self.bi.tofloat() / other)
            except ZeroDivisionError:
                # Tried to divide by zero.
                return NaN

        if atom is BITLENGTH_0:
            return IntObject(self.bi.bit_length())

        if atom is COMPLEMENT_0:
            return BigInt(self.bi.invert())

        if atom is FLOORDIVIDE_1:
            other = promoteToBigInt(args[0])
            try:
                return BigInt(self.bi.floordiv(other))
            except ZeroDivisionError:
                raise userError(u"Integer division by zero")

        if atom is MAX_1:
            # XXX could specialize for ints
            other = promoteToBigInt(args[0])
            return self if self.bi.gt(other) else args[0]

        if atom is MIN_1:
            # XXX could specialize for ints
            other = promoteToBigInt(args[0])
            return self if self.bi.lt(other) else args[0]

        if atom is MODPOW_2:
            exponent = unwrapInt(args[0])
            modulus = unwrapInt(args[1])
            return BigInt(self.bi.pow(rbigint.fromint(exponent),
                                      rbigint.fromint(modulus)))

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


@runnable(RUN_6, [deepFrozenStamp])
def _makeSourceSpan(uri, isOneToOne, startLine, startCol, endLine, endCol):
    return SourceSpan(uri, unwrapBool(isOneToOne),
                      unwrapInt(startLine), unwrapInt(startCol),
                      unwrapInt(endLine), unwrapInt(endCol))

makeSourceSpan = _makeSourceSpan()

# XXX not DF?
@autohelp
@audited.Transparent
class SourceSpan(Object):
    """
    Information about the original location of a span of text. Twines use
    this to remember where they came from.

    uri: Name of document this text came from.

    isOneToOne: Whether each character in that Twine maps to the
    corresponding source character position.

    startLine, endLine: Line numbers for the beginning and end of the
    span. Line numbers start at 1.

    startCol, endCol: Column numbers for the beginning and end of the
    span. Column numbers start at 0.

    """

    def __init__(self, uri, isOneToOne, startLine, startCol,
                 endLine, endCol):
        self.uri = uri
        self._isOneToOne = isOneToOne
        self.startLine = startLine
        self.startCol = startCol
        self.endLine = endLine
        self.endCol = endCol

    @method("Any")
    def notOneToOne(self):
        """
        Return a new SourceSpan for the same text that doesn't claim
        one-to-one correspondence.
        """
        return SourceSpan(self.uri, False,
                          self.startLine, self.startCol,
                          self.endLine, self.endCol)

    @method("Bool")
    def isOneToOne(self):
        return self._isOneToOne

    @method("Int")
    def getStartLine(self):
        return self.startLine

    @method("Int")
    def getStartCol(self):
        return self.startCol

    @method("Int")
    def getEndLine(self):
        return self.endLine

    @method("Int")
    def getEndCol(self):
        return self.endCol

    def toString(self):
        return u"<%s#:%s::%s>" % (
            self.uri.toString(),
            u"span" if self._isOneToOne else u"blob",
            u":".join([str(self.startLine).decode('ascii'),
                       str(self.startCol).decode('ascii'),
                       str(self.endLine).decode('ascii'),
                       str(self.endCol).decode('ascii')]))

    @method("Any", "Any")
    def combine(self, other):
        if not isinstance(other, SourceSpan):
            raise userError(u"Not a SourceSpan")
        return spanCover(self, other)

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.lists import wrapList
        from typhon.objects.collections.maps import EMPTY_MAP
        return [
            makeSourceSpan, StrObject(u"run"),
            wrapList([wrapBool(self._isOneToOne), IntObject(self.startLine),
                       IntObject(self.startCol), IntObject(self.endLine),
                       IntObject(self.endCol)]), EMPTY_MAP]


def spanCover(a, b):
    """
    Create a new SourceSpan that covers spans `a` and `b`.
    """
    if a is NullObject or b is NullObject:
        return NullObject
    if a.uri != b.uri:
        return NullObject
    if ((a._isOneToOne and b._isOneToOne
         and a.endLine == b.startLine
         and a.endCol + 1) == b.startCol):
        # These spans are adjacent.
        return SourceSpan(a.uri, True,
                          a.startLine, a.startCol,
                          b.endLine, b.endCol)

    # find the earlier start point
    if a.startLine < b.startLine:
        startLine = a.startLine
        startCol = a.startCol
    elif a.startLine == b.startLine:
        startLine = a.startLine
        startCol = min(a.startCol, b.startCol)
    else:
        startLine = b.startLine
        startCol = b.startCol

    # find the later end point
    if b.endLine > a.endLine:
        endLine = b.endLine
        endCol = b.endCol
    elif a.endLine == b.endLine:
        endLine = a.endLine
        endCol = max(a.endCol, b.endCol)
    else:
        endLine = a.endLine
        endCol = a.endCol

    return SourceSpan(a.uri, False, startLine, startCol, endLine, endCol)


@autohelp
class strIterator(Object):
    """
    An iterator on a string, producing characters.
    """

    _immutable_fields_ = "s",

    _index = 0

    def __init__(self, s):
        self.s = s

    @method("List", "Any")
    def next(self, ej):
        if self._index < len(self.s):
            rv = [IntObject(self._index), CharObject(self.s[self._index])]
            self._index += 1
            return rv
        else:
            # XXX incorrect throw
            ej.call(u"run", [StrObject(u"Iterator exhausted")])


@autohelp
@audited.DFSelfless
class StrObject(Object):
    """
    A string of Unicode text.
    """

    _immutable_fields_ = "_s",

    def __init__(self, s):
        self._s = s

    def toString(self):
        return self._s

    def toQuote(self):
        return quoteStr(self._s)

    def computeHash(self, depth):
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

    def sizeOf(self):
        return (rgc.get_rpy_memory_usage(self) +
                rgc.get_rpy_memory_usage(self._s))

    def optInterface(self):
        return getGlobalValue(u"Str")

    @method("Str", "Any")
    def add(self, other):
        if isinstance(other, StrObject):
            return self._s + other._s
        if isinstance(other, CharObject):
            return self._s + unicode(other._c)
        raise WrongType(u"Not a string or char!")

    @method("Bool", "Any")
    def contains(self, needle):
        if isinstance(needle, CharObject):
            return needle._c in self._s
        if isinstance(needle, StrObject):
            return needle._s in self._s
        raise WrongType(u"Not a string or char!")

    @method("Bool", "Str")
    def startsWith(self, s):
        return self._s.startswith(s)

    @method("Bool", "Str")
    def endsWith(self, s):
        return self._s.endswith(s)

    @method("Char", "Int")
    def get(self, index):
        if not 0 <= index < len(self._s):
            raise userError(u"string.get/1: Index out of bounds: %d" % index)
        return self._s[index]

    @method("Void")
    def getSpan(self):
        pass

    @method("Int", "Str")
    def indexOf(self, needle):
        return self._s.find(needle)

    @method("Int", "Str", "Int", _verb="indexOf")
    def _indexOf(self, needle, offset):
        if offset < 0:
            raise userError(u"indexOf/2: Negative offset %d not supported"
                            % offset)
        return self._s.find(needle, offset)

    @method("Int", "Str")
    def lastIndexOf(self, needle):
        return self._s.rfind(needle)

    @method("Str", "Int")
    def multiply(self, amount):
        return self._s * amount

    @method("Int", "Str")
    def op__cmp(self, other):
        return cmp(self._s, other)

    @method("Str", "Str", "Str")
    def replace(self, src, dest):
        return replace(self._s, src, dest)

    @method("Str")
    def quote(self):
        return quoteStr(self._s)

    @method("Int")
    def size(self):
        return len(self._s)

    @method("Str", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"Slice start cannot be negative")
        return self._s[start:]

    @method("Str", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"Slice start cannot be negative")
        if stop < 0:
            raise userError(u"Slice stop cannot be negative")
        return self._s[start:stop]

    @method("Str", "Char", _verb="with")
    def _with(self, c):
        return self._s + c

    @method("Any")
    def _makeIterator(self):
        return strIterator(self._s)

    def getString(self):
        return self._s

    @method("List")
    def asList(self):
        return [CharObject(c) for c in self._s]

    @method("Set")
    def asSet(self):
        from typhon.objects.collections.sets import monteSet
        d = monteSet()
        for c in self._s:
            d[CharObject(c)] = None
        return d

    @method("Str", "List")
    def join(self, pieces):
        ub = UnicodeBuilder()
        first = True
        for s in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                ub.append(self._s)

            string = unwrapStr(s)

            ub.append(string)
        return ub.build()

    @method("List", "Str")
    def split(self, splitter):
        return [StrObject(s) for s in split(self._s, splitter)]

    @method("List", "Str", "Int", _verb="split")
    def _split(self, splitter, splits=-1):
        return [StrObject(s) for s in split(self._s, splitter, splits)]

    @method("Str")
    def toLowerCase(self):
        # Use current size as a size hint. In the best case, characters
        # are one-to-one; in the next-best case, we overestimate and end
        # up with a couple bytes of slop.
        ub = UnicodeBuilder(len(self._s))
        for char in self._s:
            ub.append(unichr(unicodedb.tolower(ord(char))))
        return ub.build()

    @method("Str")
    def toUpperCase(self):
        # Same as toLowerCase().
        ub = UnicodeBuilder(len(self._s))
        for char in self._s:
            ub.append(unichr(unicodedb.toupper(ord(char))))
        return ub.build()

    @method("Str")
    def trim(self):
        if len(self._s) == 0:
            return u""

        left = 0
        right = len(self._s)

        while left < right and unicodedb.isspace(ord(self._s[left])):
            left += 1

        while left < right and unicodedb.isspace(ord(self._s[right - 1])):
            right -= 1

        assert right >= 0, "StrObject.trim/0: Proven impossible"
        return self._s[left:right]


def unwrapStr(o):
    from typhon.objects.refs import resolution
    s = resolution(o)
    if isinstance(s, StrObject):
        return s.getString()
    raise WrongType(u"Not a string!")

def wrapStr(s):
    return StrObject(s)

def isStr(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), StrObject)


@autohelp
class bytesIterator(Object):
    """
    An iterator on a bytestring, producing integers.
    """

    _immutable_fields_ = "s",

    _index = 0

    def __init__(self, s):
        self.s = s

    @method("List", "Any")
    def next(self, ej):
        if self._index < len(self.s):
            rv = [IntObject(self._index), IntObject(ord(self.s[self._index]))]
            self._index += 1
            return rv
        else:
            ej.call(u"run", [StrObject(u"Iterator exhausted")])


def bytesToString(bs):
    d = {
        '\r': u"$\\r",
        '\n': u"$\\n",
    }
    pieces = []
    for char in bs:
        if 0x20 <= ord(char) < 0x7f:
            pieces.append(unicode(unichr(ord(char))))
        elif char in d:
            pieces.append(d[char])
        elif ord(char) < 0x10:
            pieces.append(u"$\\x0%x" % ord(char))
        else:
            pieces.append(u"$\\x%x" % ord(char))
    return u"b`%s`" % u"".join(pieces)


@autohelp
@audited.DFSelfless
class BytesObject(Object):
    """
    A string of bytes.
    """

    _immutable_fields_ = "_bs",

    def __init__(self, s):
        self._bs = s

    def toString(self):
        return bytesToString(self._bs)

    def computeHash(self, depth):
        # Cribbed from RPython's _hash_string.
        length = len(self._bs)
        if length == 0:
            return -1
        x = ord(self._bs[0]) << 7
        i = 0
        while i < length:
            x = intmask((1000003 * x) ^ ord(self._bs[i]))
            i += 1
        x ^= length
        return intmask(x)

    def sizeOf(self):
        return (rgc.get_rpy_memory_usage(self) +
                rgc.get_rpy_memory_usage(self._bs))

    def optInterface(self):
        return getGlobalValue(u"Bytes")

    @method("Bytes", "Any")
    def add(self, other):
        if isinstance(other, BytesObject):
            return self._bs + other._bs
        if isinstance(other, IntObject):
            return self._bs + str(chr(other._i))
        raise WrongType(u"Not an int or bytestring!")

    @method("Bool", "Any")
    def contains(self, needle):
        if isinstance(needle, IntObject):
            return chr(needle._i) in self._bs
        if isinstance(needle, BytesObject):
            return needle._bs in self._bs
        raise WrongType(u"Not an int or bytestring!")

    @method("Int", "Int")
    def get(self, index):
        if not 0 <= index < len(self._bs):
            raise userError(u"string.get/1: Index out of bounds: %d" %
                            index)
        return ord(self._bs[index])

    @method("Int", "Bytes")
    def indexOf(self, needle):
        return self._bs.find(needle)

    @method("Int", "Bytes", "Int", _verb="indexOf")
    def _indexOf(self, needle, offset):
        if offset < 0:
            raise userError(u"indexOf/2: Negative offset %d not supported"
                            % offset)
        return self._bs.find(needle, offset)

    @method("Int", "Bytes")
    def lastIndexOf(self, needle):
        return self._bs.rfind(needle)

    @method("Bytes", "Int")
    def multiply(self, amount):
        return self._bs * amount

    @method("Int", "Bytes")
    def op__cmp(self, other):
        return cmp(self._bs, other)

    @method("Bytes", "Bytes", "Bytes")
    def replace(self, src, dest):
        return replace(self._bs, src, dest)

    @method("Int")
    def size(self):
        return len(self._bs)

    @method("Bytes", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"Slice start cannot be negative")
        return self._bs[start:]

    @method("Bytes", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"Slice start cannot be negative")
        if stop < 0:
            raise userError(u"Slice stop cannot be negative")
        return self._bs[start:stop]

    @method("Bytes", "Int", _verb="with")
    def _with(self, i):
        return self._bs + chr(i)

    @method("Any")
    def _makeIterator(self):
        return bytesIterator(self._bs)

    def getBytes(self):
        return self._bs

    @method("List")
    def asList(self):
        return [IntObject(ord(c)) for c in self._bs]

    @method("Set")
    def asSet(self):
        from typhon.objects.collections.sets import monteSet
        d = monteSet()
        for c in self._bs:
            d[IntObject(ord(c))] = None
        return d

    @method("Bytes", "List")
    def join(self, pieces):
        sb = StringBuilder()
        first = True
        for s in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                sb.append(self._bs)

            string = unwrapBytes(s)

            sb.append(string)
        return sb.build()

    @method("List", "Bytes")
    def split(self, splitter):
        return [BytesObject(s) for s in split(self._bs, splitter)]

    @method("List", "Bytes", "Int", _verb="split")
    def _split(self, splitter, splits):
        return [BytesObject(s) for s in split(self._bs, splitter, splits)]

    @method("Bytes")
    def toLowerCase(self):
        return self._bs.lower()

    @method("Bytes")
    def toUpperCase(self):
        return self._bs.upper()

    @method("Bytes")
    def trim(self):
        if len(self._bs) == 0:
            return ""

        left = 0
        right = len(self._bs)

        while left < right and self._bs[left] in string.whitespace:
            left += 1

        while left < right and self._bs[right - 1] in string.whitespace:
            right -= 1

        assert right >= 0, "BytesObject.trim/0: Proven impossible"
        return self._bs[left:right]


def unwrapBytes(o):
    from typhon.objects.refs import resolution
    s = resolution(o)
    if isinstance(s, BytesObject):
        return s.getBytes()
    raise WrongType(u"Not a bytestring!")

def wrapBytes(bs):
    return BytesObject(bs)

def isBytes(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), BytesObject)
