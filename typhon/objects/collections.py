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

from rpython.rlib.objectmodel import r_ordereddict, specialize
from rpython.rlib.rarithmetic import intmask

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import throw
from typhon.objects.root import Object
from typhon.prelude import getGlobal


ADD_1 = getAtom(u"add", 1)
ASMAP_0 = getAtom(u"asMap", 0)
ASSET_0 = getAtom(u"asSet", 0)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
FETCH_2 = getAtom(u"fetch", 2)
GET_1 = getAtom(u"get", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
INDEXOF_2 = getAtom(u"indexOf", 2)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEXT_1 = getAtom(u"next", 1)
OR_1 = getAtom(u"or", 1)
POP_0 = getAtom(u"pop", 0)
PUSH_1 = getAtom(u"push", 1)
REVERSE_0 = getAtom(u"reverse", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SNAPSHOT_0 = getAtom(u"snapshot", 0)
WITHOUT_1 = getAtom(u"without", 1)
WITH_1 = getAtom(u"with", 1)
WITH_2 = getAtom(u"with", 2)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_UNCALL_0 = getAtom(u"_uncall", 0)


class listIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def toString(self):
        return u"<listIterator>"

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < len(self.objects):
                rv = [IntObject(self._index), self.objects[self._index]]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


class mapIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def toString(self):
        return u"<mapIterator>"

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < len(self.objects):
                k, v = self.objects[self._index]
                rv = [k, v]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


class Collection(object):
    """
    A common abstraction for several collections which share methods.
    """

    _mixin_ = True

    def recv(self, atom, args):
        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        # contains/1: Determine whether an element is in this collection.
        if atom is CONTAINS_1:
            return wrapBool(self.contains(args[0]))

        # size/0: Get the number of elements in the collection.
        if atom is SIZE_0:
            return IntObject(self.size())

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_1:
            start = unwrapInt(args[0])
            return self.slice(start)

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_2:
            start = unwrapInt(args[0])
            stop = unwrapInt(args[1])
            return self.slice(start, stop)

        # snapshot/0: Create a new constant collection with a copy of the
        # current collection's contents.
        if atom is SNAPSHOT_0:
            return self.snapshot()

        return self._recv(atom, args)


class ConstList(Collection, Object):

    _immutable_fields_ = "objects[*]",

    def __init__(self, objects):
        self.objects = objects

    def toString(self):
        guts = u", ".join([obj.toString() for obj in self.objects])
        return u"[%s]" % (guts,)

    def toQuote(self):
        guts = u", ".join([obj.toQuote() for obj in self.objects])
        return u"[%s]" % (guts,)

    def hash(self):
        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.objects:
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def _recv(self, atom, args):
        if atom is ADD_1:
            other = args[0]
            return ConstList(self.objects + unwrapList(other))

        if atom is ASMAP_0:
            d = monteDict()
            for i, o in enumerate(self.objects):
                d[IntObject(i)] = o
            return ConstMap(d)

        if atom is ASSET_0:
            d = monteDict()
            for o in self.objects:
                d[o] = None
            return ConstSet(d)

        if atom is DIVERGE_0:
            return FlexList(self.objects)

        if atom is GET_1:
            # Lookup by index.
            index = unwrapInt(args[0])
            return self.objects[index]

        if atom is INDEXOF_1:
            from typhon.objects.equality import EQUAL, optSame
            needle = args[0]
            for index, specimen in enumerate(self.objects):
                if optSame(needle, specimen) is EQUAL:
                    return IntObject(index)
            return IntObject(-1)

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = unwrapInt(args[0])
            return ConstList(self.objects * index)

        if atom is REVERSE_0:
            # This might seem slightly inefficient, and it might be, but I
            # want to make it very clear to RPython that we are not mutating
            # the list after we assign it to the new object.
            new = self.objects[:]
            new.reverse()
            return ConstList(new)

        if atom is WITH_1:
            # with/1: Create a new list with an appended object.
            return ConstList(self.objects + args)

        if atom is WITH_2:
            # Replace by index.
            index = unwrapInt(args[0])
            return self.put(index, args[1])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self.objects)

    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.objects:
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    def put(self, index, value):
        top = len(self.objects)
        if 0 <= index < top:
            new = self.objects[:]
            new[index] = value
        elif index == top:
            new = self.objects + [value]
        else:
            raise userError(u"Index %d out of bounds for list of length %d" %
                           (index, len(self.objects)))

        return ConstList(new)

    def size(self):
        return len(self.objects)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            return ConstList(self.objects[start:])
        else:
            return ConstList(self.objects[start:stop])

    def snapshot(self):
        return ConstList(self.objects[:])


class FlexList(Collection, Object):

    def __init__(self, flexObjects):
        self.flexObjects = flexObjects

    def toString(self):
        guts = u", ".join([obj.toString() for obj in self.flexObjects])
        return u"[%s].diverge()" % (guts,)

    def toQuote(self):
        guts = u", ".join([obj.toQuote() for obj in self.flexObjects])
        return u"[%s].diverge()" % (guts,)

    def hash(self):
        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.flexObjects:
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def _recv(self, atom, args):
        if atom is ADD_1:
            other = args[0]
            return ConstList(self.flexObjects + unwrapList(other))

        if atom is ASMAP_0:
            d = monteDict()
            for i, o in enumerate(self.flexObjects):
                d[IntObject(i)] = o
            return ConstMap(d)

        if atom is ASSET_0:
            d = monteDict()
            for o in self.flexObjects:
                d[o] = None
            return ConstSet(d)

        if atom is DIVERGE_0:
            return FlexList(self.flexObjects)

        if atom is GET_1:
            # Lookup by index.
            index = unwrapInt(args[0])
            return self.flexObjects[index]

        if atom is INDEXOF_1:
            from typhon.flexObjects.equality import EQUAL, optSame
            needle = args[0]
            for index, specimen in enumerate(self.flexObjects):
                if optSame(needle, specimen) is EQUAL:
                    return IntObject(index)
            return IntObject(-1)

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = unwrapInt(args[0])
            return ConstList(self.flexObjects * index)

        if atom is POP_0:
            return self.flexObjects.pop()

        if atom is PUSH_1:
            self.flexObjects.append(args[0])
            return NullObject

        if atom is REVERSE_0:
            self.flexObjects.reverse()
            return NullObject

        if atom is WITH_1:
            # with/1: Create a new list with an appended object.
            return ConstList(self.flexObjects + args)

        if atom is WITH_2:
            # Replace by index.
            index = unwrapInt(args[0])
            return self.put(index, args[1])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self.flexObjects)

    def contains(self, needle):
        from typhon.flexObjects.equality import EQUAL, optSame
        for specimen in self.flexObjects:
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    def put(self, index, value):
        top = len(self.flexObjects)
        if 0 <= index < top:
            new = self.flexObjects[:]
            new[index] = value
        elif index == top:
            new = self.flexObjects + [value]
        else:
            raise userError(u"Index %d out of bounds for list of length %d" %
                           (index, len(self.flexObjects)))

        return ConstList(new)

    def size(self):
        return len(self.flexObjects)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            return ConstList(self.flexObjects[start:])
        else:
            return ConstList(self.flexObjects[start:stop])

    def snapshot(self):
        return ConstList(self.flexObjects[:])


# Let's talk about maps for a second.
# Maps are backed by ordered dictionaries. This is an RPython-level hash table
# that is ordered, using insertion order, and has predictable
# insertion-order-based iteration order. Therefore, they should back Monte
# maps perfectly.
# The ordered dictionary at RPython level requires a few extra pieces of
# plumbing. We are asked to provide `key_eq` and `key_hash`. These are
# functions. `key_eq` is a key equality function which determines whether two
# keys are equal. `key_hash` is a key hashing function which returns a hash
# for a key.
# If two objects are equal, then they hash equal.
# We forbid unsettled refs from being used as keys, since their equality can
# change at any time.


def pairRepr(key, value):
    return key.toString() + u" => " + value.toString()


def pairQuote(key, value):
    return key.toQuote() + u" => " + value.toQuote()


def resolveKey(key):
    from typhon.objects.refs import Promise, isResolved
    if isinstance(key, Promise):
        key = key.resolution()
    if not isResolved(key):
        raise userError(u"Unresolved promises cannot be used as map keys")
    return key


def keyEq(first, second):
    from typhon.objects.equality import optSame, EQUAL
    first = resolveKey(first)
    second = resolveKey(second)
    return optSame(first, second) is EQUAL


def keyHash(key):
    return resolveKey(key).hash()


def monteDict():
    return r_ordereddict(keyEq, keyHash)


class ConstMap(Collection, Object):

    _immutable_fields_ = "objectMap",

    def __init__(self, objectMap):
        self.objectMap = objectMap

    def asDict(self):
        return self.objectMap

    def toString(self):
        # If this map is empty, return a string that distinguishes it from a
        # list. E does the same thing.
        if not self.objectMap:
            return u"[].asMap()"

        guts = u", ".join([pairRepr(k, v) for k, v in self.objectMap.items()])
        return u"[%s]" % (guts,)

    def toQuote(self):
        if not self.objectMap:
            return u"[].asMap()"

        guts = u", ".join([pairQuote(k, v) for k, v in self.objectMap.items()])
        return u"[%s]" % (guts,)

    def hash(self):
        # Nest each item, hand-unwrapping the nested "tuple" of items.
        x = 0x345678
        for k, v in self.objectMap.items():
            y = 0x345678
            y = intmask((1000003 * y) ^ k.hash())
            y = intmask((1000003 * y) ^ v.hash())
            x = intmask((1000003 * x) ^ y)
        return x

    @staticmethod
    def fromPairs(wrappedPairs):
        d = monteDict()
        for obj in unwrapList(wrappedPairs):
            pair = unwrapList(obj)
            assert len(pair) == 2, "Not a pair!"
            d[pair[0]] = pair[1]
        return ConstMap(d)

    def _recv(self, atom, args):
        if atom is _UNCALL_0:
            rv = ConstList([ConstList([k, v])
                for k, v in self.objectMap.items()])
            return ConstList([StrObject(u"fromPairs"), rv])

        if atom is DIVERGE_0:
            _flexMap = getGlobal(u"_flexMap")
            return _flexMap.call(u"run", [self])

        if atom is FETCH_2:
            key = args[0]
            thunk = args[1]
            rv = self.objectMap.get(key, None)
            if rv is None:
                rv = thunk.call(u"run", [])
            return rv

        if atom is GET_1:
            key = args[0]
            try:
                return self.objectMap[key]
            except KeyError:
                raise userError(u"Key not found: %s" % (key.toString(),))

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        if atom is WITH_2:
            # Replace by key.
            key = args[0]
            value = args[1]
            d = self.objectMap.copy()
            d[key] = value
            return ConstMap(d)

        if atom is WITHOUT_1:
            key = args[0]
            d = self.objectMap.copy()
            # Ignore the case where the key wasn't in the map.
            if key in d:
                del d[key]
            return ConstMap(d)

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return mapIterator(self.objectMap.items())

    def contains(self, needle):
        return needle in self.objectMap

    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectMap.copy()
        for ok, ov in unwrapMap(other).items():
            if ok not in rv:
                rv[ok] = ov
        return ConstMap(rv)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            items = self.objectMap.items()[start:]
        else:
            items = self.objectMap.items()[start:stop]
        rv = monteDict()
        for k, v in items:
            rv[k] = v
        return ConstMap(rv)

    def size(self):
        return len(self.objectMap)

    def snapshot(self):
        return ConstMap(self.objectMap.copy())


class ConstSet(Collection, Object):
    """
    Like a map, but with only keys.

    The actual implementation is an RPython-style set, which is a dictionary
    with None for the values.
    """

    _immutable_fields_ = "objectMap",

    def __init__(self, objectMap):
        self.objectMap = objectMap

    def asDict(self):
        return self.objectMap

    def hash(self):
        # Hash as if we were a list.
        x = 0x345678
        for obj in self.objectMap.keys():
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def toString(self):
        # We always have to remind the user that we are a set, not a list.
        guts = u", ".join([k.toString() for k in self.objectMap.keys()])
        return u"[%s].asSet()" % (guts,)

    def toQuote(self):
        # We always have to remind the user that we are a set, not a list.
        guts = u", ".join([k.toQuote() for k in self.objectMap.keys()])
        return u"[%s].asSet()" % (guts,)

    def _recv(self, atom, args):
        if atom is _UNCALL_0:
            # [1,2,3].asSet() -> [[1,2,3], "asSet"]
            rv = ConstList(self.objectMap.keys())
            return ConstList([rv, StrObject(u"asSet")])

        if atom is DIVERGE_0:
            _flexSet = getGlobal(u"_flexSet")
            return _flexSet.call(u"run", [self])

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        if atom is WITH_1:
            key = args[0]
            d = self.objectMap.copy()
            d[key] = None
            return ConstSet(d)

        if atom is WITHOUT_1:
            key = args[0]
            d = self.objectMap.copy()
            # Ignore the case where the key wasn't in the map.
            if key in d:
                del d[key]
            return ConstSet(d)

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self.objectMap.keys())

    def contains(self, needle):
        return needle in self.objectMap

    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectMap.copy()
        for ok in unwrapSet(other).keys():
            if ok not in rv:
                rv[ok] = None
        return ConstSet(rv)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            keys = self.objectMap.keys()[start:]
        else:
            keys = self.objectMap.keys()[start:stop]
        rv = monteDict()
        for k in keys:
            rv[k] = None
        return ConstSet(rv)

    def size(self):
        return len(self.objectMap)

    def snapshot(self):
        return ConstSet(self.objectMap.copy())


def unwrapList(o, ej=None):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.objects
    if isinstance(l, FlexList):
        return l.flexObjects
    throw(ej, StrObject(u"Not a list!"))


def unwrapMap(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstMap):
        return m.objectMap
    raise userError(u"Not a map!")


def unwrapSet(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstSet):
        return m.objectMap
    raise userError(u"Not a set!")
