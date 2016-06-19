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

from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.collections.lists import ConstList, unwrapList
from typhon.objects.collections.maps import ConstMap
from typhon.objects.constants import TrueObject, FalseObject, NullObject, wrapBool
from typhon.objects.data import (BigInt, BytesObject, CharObject,
                                 DoubleObject, IntObject, StrObject)
from typhon.objects.refs import resolution, isResolved
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon


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

    # Two identical objects are equal. We do this twice; this first time is
    # done prior to checking settledness, which takes time proportional to the
    # size of the object graphs.
    if first is second:
        return EQUAL

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

    # NB: null, true, and false are all singletons, prebuilt before
    # translation, and as such, their identities cannot possibly vary. Code
    # checking for their cases used to live here, but it has been removed for
    # speed. ~ C.

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
        if first.empty() and second.empty():
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


def samenessHash(obj, depth, fringe, path=None):
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
    # The constants have their own special hash values.
    if o is NullObject:
        return 0
    if o is TrueObject:
        return 1
    if o is FalseObject:
        return 2

    # Objects that do their own hashing.
    if (isinstance(o, CharObject) or isinstance(o, DoubleObject) or
        isinstance(o, IntObject) or isinstance(o, BigInt) or
        isinstance(o, StrObject) or isinstance(o, BytesObject) or
        isinstance(o, TraversalKey)):
        return o.computeHash(depth)

    # Lists.
    if isinstance(o, ConstList):

        oList = unwrapList(o)
        result = len(oList)
        for i, x in enumerate(oList):
            if fringe is None:
                fr = None
            else:
                fr = FringePath(i, path)
            result ^= i ^ samenessHash(x, depth - 1, fringe, path=fr)
        return result

    # The empty map. (Uncalls contain maps, thus this base case.)
    if isinstance(o, ConstMap) and o.empty():
        return 127
    from typhon.objects.proxy import FarRef, DisconnectedRef
    if isinstance(o, FarRef) or isinstance(o, DisconnectedRef):
        return samenessHash(o.handler, depth, fringe, path=path)

    # Other objects compared by structure.
    if selfless in o.auditorStamps():
        if transparentStamp in o.auditorStamps():
            return samenessHash(o.call(u"_uncall", []), depth, fringe,
                                path=path)
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
    if o in (NullObject, TrueObject, FalseObject):
        return True

    if (isinstance(o, CharObject) or isinstance(o, DoubleObject) or
        isinstance(o, IntObject) or isinstance(o, BigInt) or
        isinstance(o, StrObject) or isinstance(o, BytesObject) or
        isinstance(o, TraversalKey)):
        return True

    if isinstance(o, ConstMap) and o.empty():
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


# Only look at a few levels of the object graph for hash values.
HASH_DEPTH = 7

@autohelp
@audited.DFSelfless
class TraversalKey(Object):

    def __init__(self, ref):
        self.ref = resolution(ref)
        self.fringe = []

        # Compute a "sameYet" hash, which represents a snapshot of how this
        # key's traversal had resolved at the time of key creation.
        snapHash = samenessHash(self.ref, HASH_DEPTH, self.fringe)
        for f in self.fringe:
            snapHash ^= f.fringeHash()
        self.snapHash = snapHash

    def toString(self):
        return u"<a traversal key>"

    def computeHash(self, depth):
        return self.snapHash


@profileTyphon("_equalizer.sameEver/2")
def isSameEver(first, second):
    """
    Call this instead of _equalizer.sameEver/2.
    """

    result = optSame(first, second)
    if result is NOTYET:
        raise userError(u"Not yet settled!")
    return result is EQUAL


@autohelp
@audited.DF
class Equalizer(Object):
    """
    A perceiver of identity.

    This object can discern whether any two objects are distinct from each
    other.
    """

    @method("Bool", "Any")
    def isSettled(self, specimen):
        return specimen.isSettled()

    @method("Any", "Any", "Any")
    def optSame(self, first, second):
        result = optSame(first, second)
        if result is NOTYET:
            return NullObject
        return wrapBool(result is EQUAL)

    @method("Bool", "Any", "Any")
    def sameEver(self, first, second):
        return isSameEver(first, second)

    @method("Bool", "Any", "Any")
    def sameYet(self, first, second):
        result = optSame(first, second)
        return result is EQUAL

    @method("Any", "Any")
    def makeTraversalKey(self, key):
        return TraversalKey(key)
