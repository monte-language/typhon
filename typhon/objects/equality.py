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

from rpython.rlib.objectmodel import compute_identity_hash

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.collections.lists import ConstList, unwrapList
from typhon.objects.collections.maps import ConstMap
from typhon.objects.constants import BoolObject, NullObject, wrapBool
from typhon.objects.data import (BigInt, BytesObject, CharObject,
                                 DoubleObject, IntObject, StrObject)
from typhon.objects.refs import resolution, isResolved
from typhon.objects.root import Object, audited


ISSETTLED_1 = getAtom(u"isSettled", 1)
MAKETRAVERSALKEY_1 = getAtom(u"makeTraversalKey", 1)
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


def isSameEver(first, second):
    result = optSame(first, second)
    if result is NOTYET:
        raise userError(u"Not yet settled!")
    return result is EQUAL


def fringeEq(first, second):
    if len(first) != len(second):
        return False
    for i in range(len(first)):
        if not first[i].eq(second[i]):
            return False
    return True


def listEq(first, second, cache):
    # I miss zip().
    for i, x in enumerate(first):
        y = second[i]

        # Recurse.
        equal = optSame(x, y, cache)

        # Note the equality for the rest of this invocation.
        cache[x, y] = equal

        # And terminate on the first failure.
        if equal is not EQUAL:
            return equal
    # Well, nothing failed, so it would seem that they must be equal.
    return EQUAL


def optSame(first, second, cache=None):
    """
    Determine whether two objects are equal, returning None if a decision
    cannot be reached.

    This is a complex topic; expect lots of comments.
    """

    # We need to see whether our objects are settled. If not, then give up.
    if not first.isSettled() or not second.isSettled():
        # Well, actually, there's one chance that they could be equal, if
        # they're the same object. But if they aren't, then we can't tell
        # anything else about them, so we'll call it quits.
        return EQUAL if first is second else NOTYET

    # Our objects are settled. Thus, we should be able to ask for their
    # resolutions.
    first = resolution(first)
    second = resolution(second)

    # Two identical objects are equal.
    if first is second:
        return EQUAL

    # Are we structurally recursive? If so, return the already-calculated
    # value.
    if cache is not None and (first, second) in cache:
        return cache[first, second]
    if cache is not None and (second, first) in cache:
        return cache[second, first]

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
        if isinstance(second, DoubleObject):
            fd = first.getDouble()
            sd = second.getDouble()
            # NaN == NaN
            if math.isnan(fd) and math.isnan(sd):
                return eq(True)
            else:
                return eq(fd == sd)
        return INEQUAL

    # Ints.
    if isinstance(first, IntObject):
        if isinstance(second, IntObject):
            return eq(first.getInt() == second.getInt())
        if isinstance(second, BigInt):
            return eq(second.bi.int_eq(first.getInt()))
        return INEQUAL

    if isinstance(first, BigInt):
        if isinstance(second, IntObject):
            return eq(first.bi.int_eq(second.getInt()))
        if isinstance(second, BigInt):
            return eq(first.bi.eq(second.bi))
        return INEQUAL

    # Strings.
    if isinstance(first, StrObject):
        return eq(isinstance(second, StrObject) and first._s == second._s)

    # Bytestrings.
    if isinstance(first, BytesObject):
        return eq(isinstance(second, BytesObject) and first._bs == second._bs)

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

        return listEq(firstList, secondList, cache)

    if isinstance(first, TraversalKey):
        if not isinstance(second, TraversalKey):
            return INEQUAL
        if first.snapHash != second.snapHash:
            return INEQUAL
        # are the values the same now?
        if optSame(first.ref, second.ref) is not EQUAL:
            return INEQUAL
        # OK but were they the same when the traversal keys were made?
        return eq(fringeEq(first.fringe, second.fringe))

    # Proxies do their own sameness checking.
    from typhon.objects.proxy import DisconnectedRef, Proxy
    if isinstance(first, Proxy) or isinstance(first, DisconnectedRef):
        return eq(first.eq(second))

    if isinstance(first, ConstMap):
        if not isinstance(second, ConstMap):
            return INEQUAL
        if len(first.objectMap) == 0 and len(second.objectMap) == 0:
            return EQUAL
        # Fall through to uncall-based comparison.

    # We've eliminated all objects that can be compared on first principles, now
    # we need the specimens to cooperate with further investigation.

    # First, see if either object wants to stop with just identity comparison.
    if selfless in first.auditorStamps():
        if selfless not in second.auditorStamps():
            return INEQUAL
        # Then see if both objects can be compared by contents.
        if (transparentStamp in first.auditorStamps() and
                transparentStamp in second.auditorStamps()):

            # This could recurse.
            if cache is None:
                cache = {}
            cache[first, second] = INEQUAL

            left = first.call(u"_uncall", [])
            right = second.call(u"_uncall", [])

            # Recurse, add the new value to the cache, and return.
            rv = optSame(left, right, cache)
            cache[first, second] = rv
            return rv
        # XXX Add support for Semitransparent, comparing objects for structural
        # equality even if they don't publicly reveal their contents.
        else:
            return NOTYET

    # By default, objects are not equal.
    return INEQUAL

# Only look at a few levels of the object graph for hash values
HASH_DEPTH = 10


def samenessHash(obj, depth, path, fringe):
    """
    Generate a hash code for an object that may not be completely
    settled. Equality of hash code implies sameness of objects. The generated
    hash is valid until settledness of a component changes.
    """

    if depth <= 0:
        # not gonna look any further for the purposes of hash computation, but
        # we do have to know about unsettled refs
        if samenessFringe(obj, path, fringe):
            # obj is settled.
            return -1
        elif fringe is None:
            raise userError(u"Must be settled")
        else:
            # not settled.
            return -1

    o = resolution(obj)
    if o is NullObject:
        return 0

    # Objects that do their own hashing.
    if (isinstance(o, BoolObject) or isinstance(o, CharObject)
            or isinstance(o, DoubleObject) or isinstance(o, IntObject)
            or isinstance(o, BigInt) or isinstance(o, StrObject)
            or isinstance(o, BytesObject)
            or isinstance(o, TraversalKey)):
        return o.hash()

    # Lists.
    if isinstance(o, ConstList):

        oList = unwrapList(o)
        result = len(oList)
        for i, x in enumerate(oList):
            if fringe is None:
                fr = None
            else:
                fr = FringePath(i, path)
            result ^= i ^ samenessHash(x, depth - 1, fr, fringe)
        return result

    # The empty map. (Uncalls contain maps, thus this base case.)
    if isinstance(o, ConstMap) and len(o.objectMap) == 0:
        return 127
    from typhon.objects.proxy import FarRef, DisconnectedRef
    if isinstance(o, FarRef) or isinstance(o, DisconnectedRef):
        return samenessHash(o.handler, depth, path, fringe)

    # Other objects compared by structure.
    if selfless in o.auditorStamps():
        if transparentStamp in o.auditorStamps():
            return samenessHash(o.call(u"_uncall", []), depth, path, fringe)
        # XXX Semitransparent support goes here

    # Objects compared by identity.
    if isResolved(o):
        return compute_identity_hash(o)
    elif fringe is None:
        raise userError(u"Must be settled")
    # Unresolved refs.
    fringe.append(FringeNode(o, path))
    return -1


def listFringe(o, fringe, path, sofar):
    result = True
    for i, x in enumerate(unwrapList(o)):
        if fringe is None:
            fr = None
        else:
            fr = FringePath(i, path)
        result &= samenessFringe(x, fr, fringe, sofar)
        if (not result) and fringe is None:
            # Unresolved promise found.
            return False
    return result


def samenessFringe(original, path, fringe, sofar=None):
    """
    Walk an object graph, building up the fringe.

    Returns whether the graph is settled.
    """

    # Resolve the object.
    o = resolution(original)
    # Handle primitive cases first.
    if o is NullObject:
        return True

    if (isinstance(o, BoolObject) or isinstance(o, CharObject)
            or isinstance(o, DoubleObject) or isinstance(o, IntObject)
            or isinstance(o, BigInt) or isinstance(o, StrObject)
            or isinstance(o, TraversalKey)):
        return True

    if isinstance(o, ConstMap) and len(o.objectMap) == 0:
        return True

    if sofar is None:
        sofar = {}
    elif o in sofar:
        return True

    if isinstance(o, ConstList):
        sofar[o] = None
        return listFringe(o, fringe, path, sofar)

    if selfless in o.auditorStamps():
        if transparentStamp in o.auditorStamps():
            sofar[o] = None
            return samenessFringe(o.call(u"_uncall", []), path, fringe, sofar)
        # XXX Semitransparent support goes here

    if isResolved(o):
        return True

    # Welp, it's unsettled.
    if fringe is not None:
        fringe.append(FringeNode(o, path))
    return False


class FringePath(object):
    def __init__(self, position, next):
        self.position = position
        self.next = next

    def eq(left, right):
        while left is not None:
            if right is None or left.position != right.position:
                return False
            left = left.next
            right = right.next
        return right is None


def hashFringePath(path):
    val = 0
    shift = 0
    while path is not None:
        val ^= path.position << shift
        shift = (shift + 4) % 32
        path = path.next
    return val


class FringeNode(object):
    def __init__(self, obj, path):
        self.identity = obj
        self.path = path

    def eq(self, other):
        if self.identity is not other.identity:
            return False
        if self.path is None:
            if other.path is None:
                return True
            return False
        if other.path is None:
            return False
        return self.path.eq(other.path)

    def fringeHash(self):
        return compute_identity_hash(self.identity) ^ hashFringePath(self.path)


def sameYetHash(obj, fringe):
    result = samenessHash(obj, HASH_DEPTH, None, fringe)
    for f in fringe:
        result ^= f.fringeHash()
    return result


@autohelp
@audited.DFSelfless
class TraversalKey(Object):

    def __init__(self, ref):
        self.ref = resolution(ref)
        self.fringe = []
        self.snapHash = sameYetHash(self.ref, self.fringe)

    def toString(self):
        return u"<a traversal key>"

    def hash(self):
        return self.snapHash


@autohelp
@audited.DF
class Equalizer(Object):
    """
    A perceiver of identity.

    This object can discern whether any two objects are distinct from each
    other.
    """

    def recv(self, atom, args):
        if atom is ISSETTLED_1:
            return wrapBool(args[0].isSettled())

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

        if atom is MAKETRAVERSALKEY_1:
            return TraversalKey(args[0])

        raise Refused(self, atom, args)
