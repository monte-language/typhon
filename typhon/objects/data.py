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
from rpython.rlib.rbigint import BASE10, MASK, rbigint
from rpython.rlib.jit import elidable
from rpython.rlib.objectmodel import _hash_float, specialize
from rpython.rlib.rarithmetic import LONG_BIT, intmask, ovfcheck
from rpython.rlib.rfloat import DBL_EPSILON, erfc, lgamma
from rpython.rlib.rstring import StringBuilder, UnicodeBuilder, replace, split
from rpython.rlib.rstruct.ieee import float_pack
from rpython.rlib.unicodedata import unicodedb_13_0_0 as unicodedb

from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.errors import WrongType, userError
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.comparison import Incomparable
from typhon.objects.constants import NullObject, unwrapBool, wrapBool
from typhon.objects.root import Object, audited, runnable
from typhon.spans import Span
from typhon.prelude import getGlobalValue
from typhon.quoting import quoteChar, quoteStr


RUN_6 = getAtom(u"run", 6)


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
        """
        Add to this object's code point, producing another character.

        'c' + 2 == 'e'
        """

        return self.withOffset(other)

    @method("Int")
    def asInteger(self):
        """
        The code point for this object.

        'M'.asInteger() == 77
        """

        return ord(self._c)

    @method("Str")
    def asString(self):
        return unicode(self._c)

    @method("Str")
    def getCategory(self):
        """
        The Unicode category of this object's code point.
        """

        return unicode(unicodedb.category(ord(self._c)))

    @method("Char", "Char")
    def max(self, other):
        """
        The greater code point of two characters.
        """

        return max(self._c, other)

    @method("Char", "Char")
    def min(self, other):
        """
        The lesser code point of two characters.
        """

        return min(self._c, other)

    @method("Char")
    def next(self):
        """
        The next code point.

        'n'.next() == 'o'
        """

        return self.withOffset(1)

    @method("Char")
    def previous(self):
        """
        The preceding code point.
        """

        return self.withOffset(-1)

    @method("Int", "Char")
    def op__cmp(self, other):
        """
        General comparison of characters.
        """

        return cmp(self._c, other)

    @method("Str")
    def quote(self):
        """
        A string quoting this object.

        'q'.quote() == "'q'"
        """

        return quoteChar(self._c)

    @method("Char", "Int")
    def subtract(self, other):
        """
        Subtract from this object's code point, producing another character.

        'c' - 2 == 'a'
        """

        return self.withOffset(-other)

    def withOffset(self, offset):
        i = ord(self._c) + offset
        try:
            return unichr(i)
        except ValueError:
            raise userError(u"Couldn't convert %d to Unicode code point" % i)

    def getChar(self):
        return self._c


def unwrapChar(o):
    from typhon.objects.refs import resolution
    c = resolution(o)
    if isinstance(c, CharObject):
        return c.getChar()
    raise WrongType(u"Specimen is not Char: " + c.toString())

def wrapChar(c):
    return CharObject(c)

def isChar(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), CharObject)


def isNegative(d):
    # Python thinks 0.0 == -0.0. Our plan is to use copysign here onto a
    # basic float (1.0), and then to compare it to 0.0. The only edge case is
    # if d is NaN, in which case copysign returns 1.0 and we return False.
    return math.copysign(1.0, d) < 0.0

INF = float("inf")
NEG_INF = float("-inf")
NAN = float("nan")
def mathLog(d):
    if isNegative(d):
        raise userError(u"Cannot take natural logarithm of non-positive %f" %
                        d)
    # Python won't do math.log(0.0) so we have to special-case it.
    elif d == 0.0:
        return NEG_INF
    else:
        return math.log(d)

def runPoly(A, x):
    rv = 0.0
    for a in A:
        rv *= x
        rv += a
    return rv

def cumBeta(x, a, b):
    # First, symmetry. We need to be in the convergent region. If not
    # x < (a + 1) / (a + b + 2)
    # then we use
    # I_x(a, b) = 1 - I_(1-x)(b, a)
    # to rewrite and become convergent.
    w = 1.0 - x
    flip = x * (a + b + 2) >= a + 1
    if flip:
        x, w = w, x
        a, b = b, a

    # The scaling factor in front. Work logarithmically to avoid overflow.
    lbeta = lgamma(a) + lgamma(b) - lgamma(a + b)
    # NB: If x = 0 or x = 1 then ValueError!
    scale = math.exp(math.log(x) * a + math.log(w) * b
                     - math.log(a) - lbeta)

    # Lentz's algorithm to find the continued-fraction approximant.
    # The first coefficient is always 1, which has been inlined here.
    d = 1.0
    c = 2.0
    f = 2.0

    # The coefficients are generated in pairs, so we have to check the
    # parity of m and decompose into 2k or 2k + 1. The number of
    # coefficients to generate comes from Cephes.
    for m in range(1, 300):
        bot = (a + m) * (a + m - 1)
        k = m >> 1
        top = -1 * (a + k) * (a + b + k) if m & 1 else k * (b - k)
        ai = top * x / bot

        d = 1.0 / (1.0 + ai * d)
        c = 1.0 + (ai / c)
        f *= c * d

        # This stopping threshold is from Cephes.
        if abs(1.0 - c * d) < 3 * DBL_EPSILON:
            break

    # The continued fraction has a leading edge that we need to remove.
    rv = (f - 1.0) * scale

    # Finally, do we need to flip?
    return 1.0 - rv if flip else rv

def cumGamma(x, a):
    # There are four regimes and we must use different techniques in each
    # of them. What's implemented currently is technique PT, which works
    # well for the thin strip of small-x unbounded-a values that are
    # typically used in statistics. Cephes switches to technique CF when
    # both x > 1.0 and x > a. We could implement up to all four; see
    # https://arxiv.org/abs/1306.1754

    # https://www.maths.lancs.ac.uk/jameson/gammainc.pdf
    # This is largely a copy of Proposition 6, as implemented by Cephes.
    if x <= 0.0 or a < 0.0:
        return 0.0

    # We work under logs for speed and dynamic range, pulling apart
    # multiplicative terms. The first term is x ** a * e ** -x and
    # we also will add in our 1/gamma(x) scale as well.
    scale = math.exp(math.log(x) * a - x - lgamma(a))

    r = a
    acc = 1.0
    s = 1.0
    # The stopping condition is when machine epsilon dominates the next
    # additional term. This can be much quicker than computing all ~20
    # terms for which 1/n! > epsilon, and handles more cases.
    while acc / s > DBL_EPSILON:
        r += 1.0
        acc *= x / r
        s += acc

    # And we're done. Assemble our creation.
    return scale * s / a

def quantNormal(x):
    # http://csg.sph.umich.edu/abecasis/gas_power_calculator/algorithm-as-241-the-percentage-points-of-the-normal-distribution.pdf
    A = [2.5090809287301226727e3, 3.3430575583588128105e4,
         6.7265770927008700853e4, 4.5921953931549871457e4,
         1.3731693765509461125e4, 1.9715909503065514427e3,
         1.3314166789178437745e2, 3.3871328727963666080e0]
    B = [5.2264952788528545610e3, 2.8729085735721942674e4,
         3.9307895800092710610e4, 2.1213794301586595867e4,
         5.3941960214247511077e3, 6.8718700749205790830e2,
         4.2313330701600911252e1, 1.0]
    C = [7.74545014278341407640e-4, 2.27238449892691845833e-2,
         2.41780725177450611770e-1, 1.27045825245236838258e0,
         3.64784832476320460504e0, 5.76949722146069140550e0,
         4.63033784615654529590e0, 1.42343711074968357734e0]
    D = [1.05075007164441684324e-9, 5.47593808499534494600e-4,
         1.51986665636164571966e-2, 1.48103976427480074590e-1,
         6.89767334985100004550e-1, 1.67638483018380384940e0,
         2.05319162663775882187e0, 1.0]
    E = [2.01033439929228813265e-7, 2.71155556874348757815e-5,
         1.24266094738807843860e-3, 2.65321895265761230930e-2,
         2.96560571828504891230e-1, 1.78482653991729133580e0,
         5.46378491116411436990e0, 6.65790464350110377720e0]
    F = [2.04426310338993978564e-15, 1.42151175831644588870e-7,
         1.84631831751005468180e-5, 7.86869131145613259100e-4,
         1.48753612908506148525e-2, 1.36929880922735805310e-1,
         5.99832206555887937690e-1, 1.0]

    q = x - 0.5
    if abs(q) <= 0.425:
        # NB: 0.180625 = 0.425 ** 2
        x = 0.180625 - q * q
        return q * runPoly(A, x) / runPoly(B, x)
    else:
        r = math.sqrt(-math.log(min(x, 1.0 - x)))
        if r <= 5.0:
            x = r - 1.6
            return math.copysign(runPoly(C, x) / runPoly(D, x), q)
        else:
            x = r - 5.0
            return math.copysign(runPoly(E, x) / runPoly(F, x), q)


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

    # Doubles are related to each other.

    @method("Double", "Double")
    def min(self, other):
        return min(self._d, other)

    @method("Double", "Double")
    def max(self, other):
        return max(self._d, other)

    @method("Double", "Double")
    def withSignOf(self, other):
        "This double, but with the sign of its argument."
        return math.copysign(self._d, other)

    @method("Double")
    def abs(self):
        return abs(self._d)

    @method("Int")
    def floor(self):
        if math.isnan(self._d):
            raise userError(u".floor/0: No Int is the smallest Int less than NaN")
        return int(math.floor(self._d))

    @method("Double")
    def negate(self):
        return -self._d

    @method("Double", "Double")
    def approxDivide(self, divisor):
        try:
            return self._d / divisor
        except ZeroDivisionError:
            return NAN

    @method("Double", "Int", _verb="approxDivide")
    def approxDivideInt(self, divisor):
        try:
            return self._d / divisor
        except ZeroDivisionError:
            return NAN

    @method("Double", "BigInt", _verb="approxDivide")
    def approxDivideBigInt(self, divisor):
        try:
            return self._d / divisor.tofloat()
        except ZeroDivisionError:
            return NAN

    @method("Int", "Double")
    def floorDivide(self, divisor):
        try:
            return int(math.floor(self._d / divisor))
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("Int", "Int", _verb="floorDivide")
    def floorDivideInt(self, divisor):
        try:
            return int(math.floor(self._d / divisor))
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("Int", "BigInt", _verb="floorDivide")
    def floorDivideBigInt(self, divisor):
        try:
            return int(math.floor(self._d / divisor.tofloat()))
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("Double", "Double")
    def mod(self, divisor):
        try:
            return self._d - divisor * math.floor(self._d / divisor)
        except ZeroDivisionError:
            return NAN

    @method("Double", "Double")
    def pow(self, exponent):
        "This number exponentiated to `exponent`."

        try:
            return math.pow(self._d, exponent)
        # ValueError here means negative number raised to non-integral power
        except (OverflowError, ValueError):
            raise userError(u"Cannot raise %f to exponent %f" % (self._d,
                exponent))

    @method("Double", "Int", _verb="pow")
    def powInt(self, exponent):
        "This number exponentiated to `exponent`."

        try:
            return math.pow(self._d, exponent)
        except OverflowError:
            raise userError(u"Cannot raise %f to exponent %d" % (self._d,
                exponent))

    @method("Double")
    def squareRoot(self):
        # Python thinks math.sqrt(-0.0) == -0.0. Whoops! We have to guard for
        # it ourselves.
        if isNegative(self._d):
            raise userError(u"Cannot take negative square root of %f" %
                            self._d)
        return math.sqrt(self._d)

    # Intermediate arithmetic building blocks.

    @method.py("Double")
    def reciprocal(self):
        "This number's multiplicative inverse."

        # Ugh. Python 0.0 == -0.0, which worked out well earlier for the
        # comparison methods, but here it means that we need to copysign. Why
        # are we doing this, you might ask? Division by zero here is like
        # division by a number too small to represent, but still positive; its
        # multiplicative inverse is a number too large to represent, but still
        # positive; that is, Infinity.
        if self._d == 0.0:
            return math.copysign(INF, self._d)
        else:
            return 1.0 / self._d

    @method("Double", "Double")
    def euclidean(self, other):
        "The L² or Euclidean metric in the plane."

        # Herbie's regime analysis gives us bounds for x (us), and we can
        # extend those bounds to y (them) by symmetry. Beyond these bounds, x
        # (symmetrically y) is so big/small, and thus its square so big, that
        # 1) We will overflow to Infinity if we take its square
        # 2) Well, maybe not, but if we add in y² then yes overflow
        # 3) Well, maybe not if y is small, but then we'll be insensitive to
        #    the actual value of y since y « x
        # The only hitch here is that if both and x and y are beyond the
        # bounds, then we need to pick whichever is closer to the actual
        # value. To draw a picture:
        # 0 --- x --- y -|- Infinity --- x² --- y² ----|--------
        #                |                             ^ x² + y²
        #                ^ x < y < sqrt(x² + y²)
        # This inequality suggests that max(|x|, |y|) is closest.
        MIN = -3.3032099476572043e+84
        MAX = 1.943934747643532e+128
        if MIN <= self._d < MAX and MIN <= other < MAX:
            return math.sqrt(self._d * self._d + other * other)
        else:
            return max(abs(self._d), abs(other))

    # Logarithms.

    @method("Any")
    def exponential(self):
        "Euler's constant ℯ exponentiated to this number."

        try:
            return DoubleObject(math.exp(self._d))
        except OverflowError:
            # We are so large that our exponential can't be represented
            # accurately. But we can smoothly go to infinity.
            return Infinity

    @method("Double")
    def logarithm(self):
        """
        This number's natural logarithm.
        """

        return mathLog(self._d)

    @method("Double", "Double", _verb="logarithm")
    def logBase(self, base):
        "This number's logarithm in `base`."

        # Avoid division by zero.
        if base == 1.0:
            raise userError(u"Cannot take logarithm base 1")
        return mathLog(self._d) / mathLog(base)

    @method("Double", "Int", _verb="logarithm")
    def logBaseInt(self, base):
        "This number's logarithm in `base`."

        # Avoid division by zero.
        if base == 1:
            raise userError(u"Cannot take logarithm base 1")
        return mathLog(self._d) / mathLog(float(base))

    # Trigonometry.

    @method("Double")
    def sine(self):
        try:
            return math.sin(self._d)
        except ValueError:
            raise userError(u".sine/0: %f out of range" % self._d)

    @method("Double")
    def cosine(self):
        try:
            return math.cos(self._d)
        except ValueError:
            raise userError(u".cosine/0: %f out of range" % self._d)

    @method("Double")
    def tangent(self):
        try:
            return math.tan(self._d)
        except ValueError:
            raise userError(u".tangent/0: %f out of range" % self._d)

    @method("Double")
    def cosecant(self):
        try:
            return 1.0 / math.sin(self._d)
        except ValueError:
            raise userError(u".cosecant/0: %f out of range" % self._d)

    @method("Double")
    def secant(self):
        try:
            return 1.0 / math.cos(self._d)
        except ValueError:
            raise userError(u".secant/0: %f out of range" % self._d)

    @method("Double")
    def cotangent(self):
        try:
            return 1.0 / math.tan(self._d)
        except ValueError:
            raise userError(u".cotangent/0: %f out of range" % self._d)

    # NB: Inverse trig functions have restricted ranges.

    @method("Double")
    def arcSine(self):
        try:
            return math.asin(self._d)
        except ValueError:
            raise userError(u".arcSine/0: %f out of range" % self._d)

    @method("Double")
    def arcCosine(self):
        try:
            return math.acos(self._d)
        except ValueError:
            raise userError(u".arcCosine/0: %f out of range" % self._d)

    @method("Double", "Double")
    def arcTangent(self, x):
        return math.atan2(self._d, x)

    @method("Double")
    def arcCosecant(self):
        try:
            return math.asin(self.reciprocal())
        except ValueError:
            raise userError(u".arcCosecant/0: %f out of range" % self._d)

    @method("Double")
    def arcSecant(self):
        try:
            return math.acos(self.reciprocal())
        except ValueError:
            raise userError(u".arcSecant/0: %f out of range" % self._d)

    @method("Double", "Double")
    def arcCotangent(self, x):
        return math.atan2(x, self._d)

    # Statistics helpers.
    # Elusive Eight: https://www.evanmiller.org/statistical-shortcomings-in-standard-math-libraries.html

    @method("Double", "Double", "Double")
    def cumulativeBeta(self, a, b):
        """
        The cumulative probability of the beta distribution on two parameters.

        This is also known as the regularized incomplete beta function.
        """

        # https://codeplea.com/incomplete-beta-function-c
        # https://dlmf.nist.gov/8.17
        x = self._d

        # Preconditions.
        if x == 0.0:
            return 0.0
        if x == 1.0:
            return 1.0
        if not (0.0 < x < 1.0):
            raise userError(u".cumulativeBeta/2: %f out of range" % self._d)

        return cumBeta(x, a, b)

    @method("Double", "Double", "Double")
    def quantileBeta(self, a, b):
        """
        The quantile of the beta distribution on two parameters.
        """

        # https://core.ac.uk/download/pdf/82140723.pdf
        # https://www.boost.org/doc/libs/1_74_0/libs/math/doc/html/math_toolkit/sf_beta/ibeta_inv_function.html
        # Halley's method.
        # Guess: 0.5
        # First derivative: x ** (a - 1) * (1 - x) ** (b - 1) / beta(a, b)
        # Second derivative: x ** (a - 2) * (1 - x) ** (b - 2) *
        #                    (x * (2 - a - b) - 1) / beta(a, b)
        # f''/f': (x * (2 - a - b) - 1) / x * (1 - x)
        y = self._d

        if a <= 0.0 or b <= 0.0:
            return 0.0

        if y <= 0.0:
            return 0.0
        elif y >= 1.0:
            return 1.0

        # Log of beta, for scaling the derivative.
        lb = lgamma(a) + lgamma(b) - lgamma(a + b)

        # Initial guess. Since we're stuck between 0 and 1, we can use
        # bisection to gain 1 bit/loop for the first few loops, and then
        # switch to Halley's method once we have 3-5 good bits.
        x = 0.5

        # Bisection.
        bias = 0.25
        for i in range(10):
            f0 = cumBeta(x, a, b) - y
            x = x - bias if f0 > 0.0 else x + bias
            bias *= 0.5

        # And Halley iteration.
        for i in range(10):
            # f, f', f/f'
            f0 = cumBeta(x, a, b) - y
            f1 = math.exp(math.log(x) * (a - 1) + math.log(1 - x) * (b - 1) - lb)
            f01 = f0 / f1
            # f''/2f'
            f21 = (x * (2 - a - b) - 1) / 2 * x * (1 - x)
            # Halley's error term.
            err = f01 / (1 - f01 * f21)
            if abs(err) < 1e-16:
                break
            x -= err
            # If we somehow slip over the edge, then don't panic and just
            # assume that we underflowed and got bad luck on rounding.
            if x < 0.0:
                return 0.0
            elif x > 1.0:
                return 1.0

        return x

    @method("Double", "Double")
    def cumulativeGamma(self, a):
        """
        The cumulative probability of the gamma distribution on one parameter.

        This is also known as the regularized lower incomplete gamma function.
        """

        return cumGamma(self._d, a)

    @method("Double", "Double")
    def quantileGamma(self, a):
        """
        The quantile of the gamma distribution on one parameter.
        """

        # XXX better guesses possible, see https://arxiv.org/abs/1306.1754

        # Halley's method.
        # Guess: let d = 1 / (9 * a) in
        #        a * (1.0 - d - y.quantileNormal() * d.squareRoot()) ** 3
        # First derivative: x ** (a - 1) * e ** -x / gamma(a)
        # Second derivative: e ** -x * ((a - 1) * x ** (a - 2) - x ** (a - 1)) / gamma(a)
        # f''/f': ((a - 1) / x) - 1
        y = self._d

        if a <= 0.0:
            return 0.0

        if not (0.0 < y < 1.0):
            raise userError(u".quantileGamma/1: %f out of range" % y)

        lg = lgamma(a)

        # A reasonable guess, based on Cephes. When a is small, x can start
        # below -1, so we clamp to something small but positive.
        d = 1.0 / (9 * a)
        t = 1.0 - d - quantNormal(y) * math.sqrt(d)
        x = max(a * t * t * t, 1e-8)

        # The guess often overshoots, so we'll bisect until it's not
        # overshooting.
        for i in range(10):
            f0 = cumGamma(x, a) - y
            if f0 > 0.0:
                x *= 0.5
            else:
                break

        # And iterate until it's good enough. We do a hybrid of Halley and
        # bisection; if the Halley step would take us below 0, then bisect
        # downwards instead.
        for i in range(10):
            # f, f', f/f'
            f0 = cumGamma(x, a) - y
            f1 = math.exp(math.log(x) * (a - 1) - x - lg)
            f01 = f0 / f1
            # f''/2f'
            f21 = (((a - 1) / x) - 1) / 2
            # Halley's error term.
            err = f01 / (1 - f01 * f21)
            if abs(err) < 1e-16:
                break
            # Would we go negative?
            if x - err < 0.0:
                x *= 0.5
            else:
                x -= err
        return x

    @method("Double")
    def cumulativeNormal(self):
        """
        The cumulative probability of the normal distribution.
        """

        z = 1.0 / math.sqrt(2.0)
        return 1.0 - erfc(self._d * z) * 0.5

    @method("Double")
    def quantileNormal(self):
        """
        The quantile of the normal distribution.
        """

        if not (0.0 < self._d < 1.0):
            raise userError(u".quantileNormal/0: %f out of range" % self._d)

        return quantNormal(self._d)

    @method("Double", "Double")
    def besselFirst(self, v):
        """
        The Bessel function of the first kind of degree `v`.

        There are many Bessel functions; these are the ones traditionally
        notated as J, not Y.
        """

        # https://dlmf.nist.gov/10.2
        # Power series.
        # XXX when z is large, then we need to switch to Henkel's series. But,
        # like, how large? Really large, apparently?
        z = self._d

        # Special values.
        if z == 0.0:
            return 1.0 if v == 0.0 else 0.0

        scale = math.pow(z * 0.5, v)
        a = math.log(0.25 * z * z)

        rv = 0.0
        for i in range(100):
            # Work under logs so we can lgamma().
            term = math.exp(a * i - lgamma(i + 1) - lgamma(v + i + 1))
            rv = rv - term if i & 1 else rv + term
            if term < 1e-16:
                break
            # print "rv", rv, "term", term

        return scale * rv

    # Decompositions.

    @method("List")
    def normalizedExponent(self):
        """
        The unique [m, e] such that this number equals m`m * 2 ** e`.

        The significand m is a Double and the exponent e is an Int.
        """
        m, e = math.frexp(self._d)
        return [DoubleObject(m), IntObject(e)]

    @method("Bytes")
    def asBytes(self):
        "The IEEE 754 packed representation of this number."
        # float_pack() takes a double and gives us the packed integer; we need
        # to reinterpret it as packed ASCII and repack into bytes.
        x = float_pack(self._d, 8)
        return "".join([chr(x >> ((7 - i) * 8) & 0xff) for i in range(8)])

    # And basic arithmetic.

    @method("Double", "Double")
    def add(self, other):
        return self._d + other

    @method("Double", "Int", _verb="add")
    def addInt(self, other):
        return self._d + other

    @method("Double", "BigInt", _verb="add")
    def addBigInt(self, other):
        return self._d + other.tofloat()

    @method("Double", "Double")
    def multiply(self, other):
        return self._d * other

    @method("Double", "Int", _verb="multiply")
    def multiplyInt(self, other):
        return self._d * other

    @method("Double", "BigInt", _verb="multiply")
    def multiplyBigInt(self, other):
        return self._d * other.tofloat()

    @method("Double", "Double")
    def subtract(self, other):
        return self._d - other

    @method("Double", "Int", _verb="subtract")
    def subtractInt(self, other):
        return self._d - other

    @method("Double", "BigInt", _verb="subtract")
    def subtractBigInt(self, other):
        return self._d - other.tofloat()

    def getDouble(self):
        return self._d


# These double objects are prebuilt (and free to use), since building
# on-the-fly floats from strings doesn't work in RPython.
Infinity = DoubleObject(INF)
NaN = DoubleObject(NAN)


def unwrapDouble(o):
    from typhon.objects.refs import resolution
    d = resolution(o)
    if isinstance(d, DoubleObject):
        return d.getDouble()
    raise WrongType(u"Specimen is not Double: " + d.toString())

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

# For popcount, we need to generate a series of masks based on a maximum size,
# which will be the first power of two greater than MASK. We then unroll them
# to implement the fast algorithm sketched at WP:
# https://en.wikipedia.org/wiki/Hamming_weight#Efficient_implementation
HAMMING_WIDTH = 1
while 2 ** HAMMING_WIDTH < MASK:
    HAMMING_WIDTH += 1
HAMMING_WIDTH = HAMMING_WIDTH.bit_length()
def hammingMask(i, width):
    m = 2 ** i
    r = 2 ** (width - i - 1)
    return int(('0' * m + '1' * m) * r, 2)
HAMMING_MASKS = [hammingMask(i, HAMMING_WIDTH) for i in range(HAMMING_WIDTH)]
def hammingWord(w):
    i = 1
    rv = w
    for mask in HAMMING_MASKS:
        x = (rv >> i) & mask
        rv &= mask
        rv += x
        i *= 2
    return rv

# Numeric multimethods behave in a really *really* specific way: If you want
# to match both BigInts and Ints, then the BigInt methods must be listed
# first. Don't say that I didn't document it. ~ C.

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

    @method("Int")
    def abs(self):
        return abs(self._i)

    @method("Double")
    def asDouble(self):
        return float(self._i)

    @method("Any", "Double", _verb="op__cmp")
    def op__cmpDouble(self, other):
        if math.isnan(other):
            # Whoa there! Gotta watch out for those pesky NaNs.
            return NaN
        return polyCmp(self._i, other)

    @method("Int", "BigInt", _verb="op__cmp")
    def op__cmpBigInt(self, other):
        # This has to be switched around.
        if other.int_lt(self._i):
            return 1
        elif other.int_gt(self._i):
            return -1
        else:
            # Using a property of integers here.
            return 0

    @method("Int", "Int")
    def op__cmp(self, other):
        return cmp(self._i, other)

    @method("Bool")
    def aboveZero(self):
        return self._i > 0

    @method("Bool")
    def atLeastZero(self):
        return self._i >= 0

    @method("Bool")
    def atMostZero(self):
        return self._i <= 0

    @method("Bool")
    def belowZero(self):
        return self._i < 0

    @method("Bool")
    def isZero(self):
        return self._i == 0

    @method("Double", "Double", _verb="add")
    def addDouble(self, other):
        return self._i + other

    @method("BigInt", "BigInt", _verb="add")
    def addBigInt(self, other):
        # Addition commutes.
        return other.int_add(self._i)

    @method("Any", "Int")
    def add(self, other):
        try:
            return IntObject(ovfcheck(self._i + other))
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).int_add(other))

    @method("BigInt", "BigInt", _verb="and")
    def andBigInt(self, other):
        # AND commutes.
        return other.int_and_(self._i)

    @method("Int", "Int", _verb="and")
    def _and(self, other):
        return self._i & other

    @method("Double", "Any")
    def approxDivide(self, other):
        """
        Promote this object to `Double` and perform division with a given
        divisor, returning the quotient.
        """

        divisor = promoteToDouble(other)
        try:
            return float(self._i) / divisor
        except ZeroDivisionError:
            # We tried to divide by zero.
            return NAN

    @method("Int")
    def complement(self):
        return ~self._i

    @method("BigInt", "BigInt", _verb="floorDivide")
    def floorDivideBigInt(self, divisor):
        return rbigint.fromint(self._i).floordiv(divisor)

    @method("Int", "Int")
    def floorDivide(self, divisor):
        try:
            return self._i // divisor
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("Int", "Int")
    def max(self, other):
        return max(self._i, other)

    @method("Int", "Int")
    def min(self, other):
        return min(self._i, other)

    @method("Any", "Int", "Int")
    def modPow(self, exponent, modulus):
        try:
            return self.intModPow(exponent, modulus)
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).pow(rbigint.fromint(exponent),
                                                       rbigint.fromint(modulus)))

    @method("BigInt", "BigInt", _verb="mod")
    def modBigInt(self, modulus):
        try:
            return rbigint.fromint(self._i).mod(modulus)
        except ZeroDivisionError:
            raise userError(u"mod/1: Integer division by zero")

    @method("Int", "Int")
    def mod(self, modulus):
        try:
            return self._i % modulus
        except ZeroDivisionError:
            raise userError(u"mod/1: Integer division by zero")

    @method("List", "BigInt", _verb="divMod")
    def divModBigInt(self, modulus):
        try:
            q, r = rbigint.fromint(self._i).divmod(modulus)
            return [BigInt(q), BigInt(r)]
        except ZeroDivisionError:
            raise userError(u"divMod/1: Integer division by zero")

    @method("List", "Int")
    def divMod(self, modulus):
        """
        Compute the pair `[quotient, remainder]` such that `modulus *
        quotient + remainder` is this integer and `remainder < modulus` for
        positive moduli or `remainder > modulus` for negative moduli.
        """

        try:
            q = self._i // modulus
            r = self._i % modulus
            return [IntObject(q), IntObject(r)]
        except ZeroDivisionError:
            raise userError(u"divMod/1: Integer division by zero")

    @method("Double", "Double", _verb="multiply")
    def multiplyDouble(self, other):
        return self._i * other

    @method("BigInt", "BigInt", _verb="multiply")
    def multiplyBigInt(self, other):
        # Multiplication commutes.
        return other.int_mul(self._i)

    @method("Any", "Int")
    def multiply(self, other):
        try:
            return IntObject(ovfcheck(self._i * other))
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).int_mul(other))

    @method("Any")
    def negate(self):
        try:
            return IntObject(ovfcheck(-self._i))
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).neg())

    @method("Int")
    def next(self):
        return self._i + 1

    @method("BigInt", "BigInt", _verb="or")
    def orBigInt(self, other):
        # OR commutes.
        return other.int_or_(self._i)

    @method("Int", "Int", _verb="or")
    def _or(self, other):
        return self._i | other

    @method("Any", "Int")
    def pow(self, exponent):
        try:
            return self.intPow(exponent)
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).pow(rbigint.fromint(exponent)))

    @method("Int")
    def previous(self):
        return self._i - 1

    @method("Any", "Int")
    def shiftLeft(self, other):
        try:
            if other >= LONG_BIT:
                # Definite overflow won't always be detected by
                # ovfcheck(). Raise manually in this case.
                raise OverflowError
            return IntObject(ovfcheck(self._i << other))
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).lshift(other))

    @method("Int", "Int")
    def shiftRight(self, other):
        if other >= LONG_BIT:
            # This'll underflow, returning who-knows-what when translated.
            # To keep things reasonable, we define an int that has been
            # right-shifted past word width to be 0, since every bit has
            # been shifted off.
            return 0
        return self._i >> other

    @method("Double", "Double", _verb="subtract")
    def subtractDouble(self, other):
        return self._i - other

    @method("BigInt", "BigInt", _verb="subtract")
    def subtractBigInt(self, other):
        # Subtraction doesn't commute, so we have to work a little harder.
        return rbigint.fromint(self._i).sub(other)

    @method("Any", "Int")
    def subtract(self, other):
        try:
            return IntObject(ovfcheck(self._i - other))
        except OverflowError:
            return BigInt(rbigint.fromint(self._i).int_sub(other))

    @method("BigInt", "BigInt", _verb="xor")
    def xorBigInt(self, other):
        # XOR commutes.
        return other.int_xor(self._i)

    @method("Int", "Int")
    def xor(self, other):
        return self._i ^ other

    def getInt(self):
        return self._i

    @method("Int")
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

    @method("Int")
    @elidable
    def bitSum(self):
        return hammingWord(self._i)

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
            raise WrongType(u"Specimen is Int but too wide")
    raise WrongType(u"Specimen is not Int: " + i.toString())

def wrapInt(i):
    return IntObject(i)

def isInt(obj):
    from typhon.objects.refs import resolution
    obj = resolution(obj)
    if isinstance(obj, IntObject):
        return True
    if isinstance(obj, BigInt):
        try:
            obj.bi.toint()
            return True
        except OverflowError:
            return False
    return False


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

    @method("Double")
    def asDouble(self):
        return self.bi.tofloat()

    @method("Bool")
    def aboveZero(self):
        return self.bi.int_gt(0)

    @method("Bool")
    def atLeastZero(self):
        return self.bi.int_ge(0)

    @method("Bool")
    def atMostZero(self):
        return self.bi.int_le(0)

    @method("Bool")
    def belowZero(self):
        return self.bi.int_lt(0)

    @method("Bool")
    def isZero(self):
        return self.bi.int_eq(0)

    @method("BigInt")
    def abs(self):
        return self.bi.abs()

    @method("Double", "Double", _verb="add")
    def addDouble(self, other):
        return self.bi.tofloat() + other

    @method("BigInt", "BigInt")
    def add(self, other):
        return self.bi.add(other)

    @method("BigInt", "Int", _verb="add")
    def addInt(self, other):
        return self.bi.int_add(other)

    @method("BigInt", "BigInt", _verb="and")
    def _and(self, other):
        return self.bi.and_(other)

    @method("BigInt", "Int", _verb="and")
    def _andInt(self, other):
        return self.bi.int_and_(other)

    @method("Double", "Double", _verb="approxDivide")
    def approxDivideDouble(self, other):
        return self.bi.tofloat() / other

    @method("Double", "BigInt")
    def approxDivide(self, other):
        try:
            return self.bi.truediv(other)
        except ZeroDivisionError:
            return NAN

    @method("Double", "Int", _verb="approxDivide")
    def approxDivideInt(self, other):
        try:
            return self.bi.truediv(rbigint.fromint(other))
        except ZeroDivisionError:
            return NAN
        except OverflowError:
            # Trade overflow for reduced dynamic range.
            negate = self.bi.get_sign() < 0 ^ other < 0
            return NEG_INF if negate else INF

    @method("BigInt", "Double", _verb="floorDivide")
    def floorDivideDouble(self, other):
        # Of the two ways to lose precision, we had to choose one. ~ C.
        return rbigint.fromfloat(self.bi.tofloat() / other)

    @method("BigInt", "BigInt")
    def floorDivide(self, other):
        try:
            return self.bi.floordiv(other)
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("BigInt", "Int", _verb="floorDivide")
    def floorDivideInt(self, other):
        try:
            return self.bi.floordiv(rbigint.fromint(other))
        except ZeroDivisionError:
            raise userError(u"floorDivide/1: Integer division by zero")

    @method("Int")
    def bitLength(self):
        """
        The number of bits required to store this object's value.
        """

        return self.bi.bit_length()

    @method("Int")
    def bitSum(self):
        """
        The number of bits set in this object.

        Also known as population count or Hamming weight.
        """

        rv = 0
        for d in self.bi._digits:
            rv += hammingWord(d)
        return rv

    @method("BigInt")
    def complement(self):
        return self.bi.invert()

    @method("BigInt", "BigInt")
    def max(self, other):
        return self.bi if self.bi.gt(other) else other

    @method("BigInt", "Int", _verb="max")
    def maxInt(self, other):
        return self.bi if self.bi.int_gt(other) else rbigint.fromint(other)

    @method("BigInt", "BigInt")
    def min(self, other):
        return self.bi if self.bi.lt(other) else other

    @method("BigInt", "Int", _verb="min")
    def minInt(self, other):
        return self.bi if self.bi.int_lt(other) else rbigint.fromint(other)

    # We do not bother with supporting bigint exponents. If an exponent cannot
    # be coerced into an int, then it is too big for the machine that we're
    # currently running on. ~ C.

    @method("BigInt", "Int", "BigInt")
    def modPow(self, exponent, modulus):
        return self.bi.pow(rbigint.fromint(exponent), modulus)

    @method("BigInt", "Int", "Int", _verb="modPow")
    def modPowInt(self, exponent, modulus):
        return self.bi.pow(rbigint.fromint(exponent),
                rbigint.fromint(modulus))

    @method("BigInt", "Int")
    def pow(self, exponent):
        return self.bi.pow(rbigint.fromint(exponent))

    @method("BigInt", "BigInt")
    def mod(self, modulus):
        try:
            return self.bi.mod(modulus)
        except ZeroDivisionError:
            raise userError(u"mod/1: Integer division by zero")

    @method("BigInt", "Int", _verb="mod")
    def modInt(self, modulus):
        try:
            return self.bi.int_mod(modulus)
        except ZeroDivisionError:
            raise userError(u"mod/1: Integer division by zero")

    def _divMod(self, modulus):
        try:
            q, r = self.bi.divmod(modulus)
            return [BigInt(q), BigInt(r)]
        except ZeroDivisionError:
            raise userError(u"divMod/1: Integer division by zero")

    @method("List", "BigInt")
    def divMod(self, modulus):
        return self._divMod(modulus)

    @method("List", "Int", _verb="divMod")
    def divModInt(self, modulus):
        return self._divMod(rbigint.fromint(modulus))

    @method("Double", "Double", _verb="multiply")
    def multiplyDouble(self, other):
        return self.bi.tofloat() * other

    @method("BigInt", "BigInt")
    def multiply(self, other):
        return self.bi.mul(other)

    @method("BigInt", "Int", _verb="multiply")
    def multiplyInt(self, other):
        return self.bi.int_mul(other)

    @method("BigInt")
    def negate(self):
        return self.bi.neg()

    @method("BigInt")
    def next(self):
        return self.bi.int_add(1)

    @method("BigInt", "BigInt", _verb="or")
    def _or(self, other):
        return self.bi.or_(other)

    @method("BigInt", "Int", _verb="or")
    def orInt(self, other):
        return self.bi.int_or_(other)

    @method("BigInt")
    def previous(self):
        return self.bi.int_sub(1)

    @method("BigInt", "Int")
    def shiftLeft(self, other):
        return self.bi.lshift(other)

    @method("BigInt", "Int")
    def shiftRight(self, other):
        return self.bi.rshift(other)

    @method("Double", "Double", _verb="subtract")
    def subtractDouble(self, other):
        return self.bi.tofloat() - other

    @method("BigInt", "BigInt")
    def subtract(self, other):
        return self.bi.sub(other)

    @method("BigInt", "Int", _verb="subtract")
    def subtractInt(self, other):
        return self.bi.int_sub(other)

    @method("BigInt", "BigInt")
    def xor(self, other):
        return self.bi.xor(other)

    @method("BigInt", "Int", _verb="xor")
    def xorInt(self, other):
        return self.bi.int_xor(other)

    @method("Int", "BigInt")
    def op__cmp(self, other):
        if self.bi.lt(other):
            return -1
        elif self.bi.gt(other):
            return 1
        else:
            # Using a property of integers here.
            return 0

    @method("Int", "Int", _verb="op__cmp")
    def op__cmpInt(self, other):
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
    raise WrongType(u"Specimen is not (wide) Int: " + bi.toString())

def wrapBigInt(bi):
    try:
        return IntObject(bi.toint())
    except OverflowError:
        return BigInt(bi)

def isBigInt(o):
    from typhon.objects.refs import resolution
    bi = resolution(o)
    return isinstance(bi, BigInt)


def isAnyInt(o):
    from typhon.objects.refs import resolution
    bi = resolution(o)
    return isinstance(bi, BigInt) or isinstance(bi, IntObject)


def unwrapAnyInt(o):
    from typhon.objects.refs import resolution
    i = resolution(o)
    if isinstance(i, BigInt):
        return i.bi
    if isinstance(i, IntObject):
        return rbigint.fromint(i.getInt())
    raise WrongType(
            u"Specimen is not Int (even after coercion): " + i.toString())


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
    Information about the original location of a span of text. Twines use this
    to remember where they came from.

    uri: Name of document this text came from.

    isOneToOne: Whether each character in that Twine maps to the corresponding
    source character position.

    startLine, endLine: Line numbers for the beginning and end of the span.
    Line numbers start at 1.

    startCol, endCol: Column numbers for the beginning and end of the span.
    Column numbers start at 0.
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
        Return a SourceSpan for the same text as this object, but which
        doesn't claim one-to-one correspondence.
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
            wrapList([self.uri, wrapBool(self._isOneToOne),
                      IntObject(self.startLine), IntObject(self.startCol),
                      IntObject(self.endLine), IntObject(self.endCol)]),
            EMPTY_MAP]

    def toSpan(self):
        return Span(self.uri.toString(), self._isOneToOne,
                    self.startLine, self.startCol,
                    self.endLine, self.endCol)

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
            from typhon.objects.ejectors import throwStr
            throwStr(ej, u"next/1: Iterator exhausted")


@autohelp
@audited.DFSelfless
class StrObject(Object):
    """
    A string of Unicode text.
    """

    _immutable_fields_ = "_s",

    def __init__(self, s):
        assert s is not None, "perverse"
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
        "Whether this string has `s` as a prefix."
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

    @method("Bool")
    def isEmpty(self):
        return not self._s

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
    raise WrongType(u"Specimen is not Str: " + s.toString())

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
            from typhon.objects.ejectors import throwStr
            throwStr(ej, u"next/1: Iterator exhausted")


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

    @method("List")
    def _uncall(self):
        from typhon.objects.makers import theMakeBytes
        from typhon.objects.collections.lists import wrapList
        from typhon.objects.collections.maps import EMPTY_MAP
        ints = [IntObject(ord(c)) for c in self._bs]
        return [theMakeBytes, StrObject(u"fromInts"),
                wrapList([wrapList(ints)]), EMPTY_MAP]

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

    @method("Bool")
    def isEmpty(self):
        return not self._bs

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
    raise WrongType(u"Specimen is not Bytes: " + s.toString())

def wrapBytes(bs):
    return BytesObject(bs)

def isBytes(obj):
    from typhon.objects.refs import resolution
    return isinstance(resolution(obj), BytesObject)
