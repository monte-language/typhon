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

from rpython.rlib.jit import unroll_safe

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import BoolObject, NullObject, wrapBool
from typhon.objects.data import (BigInt, CharObject, DoubleObject, IntObject,
                                 StrObject)
from typhon.objects.refs import EVENTUAL, Promise, resolution
from typhon.objects.root import Object


ISSETTLED_1 = getAtom(u"isSettled", 1)
OPTSAME_2 = getAtom(u"optSame", 2)
SAMEEVER_2 = getAtom(u"sameEver", 2)
SAMEYET_2 = getAtom(u"sameYet", 2)


class Equality(object):
    def __init__(self, label):
        self._label = label

    def __repr__(self):
        return self._label


EQUAL = Equality("EQUAL")
INEQUAL = Equality("INEQUAL")
NOTYET = Equality("NOTYET")


def eq(b):
    return EQUAL if b else INEQUAL


def isSettled(o):
    if isinstance(o, Promise):
        return o.state() is not EVENTUAL
    return True


@unroll_safe
def optSame(first, second, cache=None):
    """
    Determine whether two objects are equal, returning None if a decision
    cannot be reached.

    This is a complex topic; expect lots of comments.
    """

    # We need to see whether our objects are settled. If not, then give up.
    if not isSettled(first) or not isSettled(second):
        # Well, actually, there's one chance that they could be equal, if
        # they're the same object. But if they aren't, then we can't tell
        # anything else about them, so we'll call it quits.
        return EQUAL if first is second else NOTYET

    # Our objects are settled. Thus, we should be able to ask for their
    # resolutions.
    first = resolution(first)
    second = resolution(second)

    # Are we structurally recursive? If so, return the already-calculated
    # value.
    if cache is not None and (first, second) in cache:
        return cache[first, second]

    # Null.
    if first is NullObject:
        return eq(second is NullObject)

    # Bools. This should probably be covered by the identity case already,
    # but it's included for completeness.
    if isinstance(first, BoolObject):
        return eq(isinstance(second, BoolObject)
                and first.isTrue() == second.isTrue())

    # Chars.
    if isinstance(first, CharObject):
        return eq(isinstance(second, CharObject) and first._c == second._c)

    # Doubles.
    if isinstance(first, DoubleObject):
        return eq(isinstance(second, DoubleObject)
                and first.getDouble() == second.getDouble())

    # Ints.
    if isinstance(first, IntObject):
        if isinstance(second, IntObject):
            return eq(first.getInt() == second.getInt())
        if isinstance(second, BigInt):
            return eq(second.bi.int_eq(first.getInt()))
    if isinstance(first, BigInt):
        if isinstance(second, IntObject):
            return eq(first.bi.int_eq(second.getInt()))
        if isinstance(second, BigInt):
            return eq(first.bi.eq(second.bi))

    # Strings.
    if isinstance(first, StrObject):
        return eq(isinstance(second, StrObject) and first._s == second._s)

    # Lists.
    if isinstance(first, ConstList):
        if not isinstance(second, ConstList):
            return INEQUAL

        firstList = unwrapList(first)
        secondList = unwrapList(second)

        # No point wasting time if the lists are obviously different.
        if len(firstList) != len(secondList):
            return INEQUAL

        # Iterate and use a cache of already-seen objects to avoid recursive
        # problems.
        if cache is None:
            cache = {}

        cache[first, second] = EQUAL

        # I miss zip().
        for i, x in enumerate(firstList):
            y = secondList[i]

            # Recurse.
            equal = optSame(x, y, cache)

            # Note the equality for the rest of this invocation.
            cache[x, y] = equal

            # And terminate on the first failure.
            if equal is not EQUAL:
                return equal
        # Well, nothing failed, so it would seem that they must be equal.
        return EQUAL

    # Let's request an uncall from each specimen and compare those.
    try:
        # This could recurse.
        if cache is None:
            cache = {}
        cache[first, second] = INEQUAL

        left = first.call(u"_uncall", [])
        right = second.call(u"_uncall", [])

        # Recurse, add the new value to the cache, and return. However, we
        # can't let Miranda uncalls (which return null) through, so check for
        # those first.
        if left is not NullObject and right is not NullObject:
            rv = optSame(left, right, cache)
            cache[first, second] = rv
            return rv
    except Refused:
        pass

    # Two identical objects are equal.
    if first is second:
        return EQUAL

    # By default, objects are not equal.
    return INEQUAL


@autohelp
class Equalizer(Object):
    """
    A perceiver of identity.

    This object can discern whether any two objects are distinct from each
    other.
    """

    stamps = [deepFrozenStamp]

    def recv(self, atom, args):
        if atom is ISSETTLED_1:
            return wrapBool(isSettled(args[0]))

        if atom is OPTSAME_2:
            first, second = args
            result = optSame(first, second)
            if result is NOTYET:
                return NullObject
            return wrapBool(result is EQUAL)

        if atom is SAMEEVER_2:
            first, second = args
            result = optSame(first, second)
            if result is NOTYET:
                raise userError(u"Not yet settled!")
            return wrapBool(result is EQUAL)

        if atom is SAMEYET_2:
            first, second = args
            result = optSame(first, second)
            return wrapBool(result is EQUAL)

        raise Refused(self, atom, args)
