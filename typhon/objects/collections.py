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

from rpython.rlib.objectmodel import specialize

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.constants import wrapBool
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object
from typhon.prelude import getGlobal


ADD_1 = getAtom(u"add", 1)
ASMAP_0 = getAtom(u"asMap", 0)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
GET_1 = getAtom(u"get", 1)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEXT_1 = getAtom(u"next", 1)
OR_1 = getAtom(u"or", 1)
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

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < len(self.objects):
                rv = [IntObject(self._index), self.objects[self._index]]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(atom, args)


class mapIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def recv(self, verb, args):
        if verb is NEXT_1:
            if self._index < len(self.objects):
                k, v = self.objects[self._index]
                rv = [k, v]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(verb, args)


class Collection(object):
    """
    A common abstraction for several collections which share methods.
    """

    _mixin_ = True

    @specialize.argtype(0)
    def size(self):
        return len(self.objects)

    def recv(self, atom, args):
        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        # size/0: Get the number of elements in the collection.
        if atom is SIZE_0:
            return IntObject(self.size())

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_1:
            start = args[0]
            if isinstance(start, IntObject):
                return self.slice(start.getInt())

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_2:
            start = args[0]
            stop = args[1]
            if isinstance(start, IntObject):
                if isinstance(stop, IntObject):
                    return self.slice(start.getInt(), stop.getInt())

        # snapshot/0: Create a new constant collection with a copy of the
        # current collection's contents.
        if atom is SNAPSHOT_0:
            return self.snapshot()

        return self._recv(atom, args)


class ConstList(Collection, Object):

    _immutable_fields_ = "objects[*]",

    def __init__(self, objects):
        self.objects = objects

    def repr(self):
        return "[" + ", ".join([obj.repr() for obj in self.objects]) + "]"

    def _recv(self, atom, args):
        if atom is ADD_1:
            other = args[0]
            return ConstList(self.objects + unwrapList(other))

        if atom is CONTAINS_1:
            from typhon.objects.equality import EQUAL, optSame
            needle = args[0]
            for specimen in self.objects:
                if optSame(needle, specimen) is EQUAL:
                    return wrapBool(True)
            return wrapBool(False)

        if atom is DIVERGE_0:
            _flexList = getGlobal(u"_flexList")
            return _flexList.call(u"run", [self])

        if atom is GET_1:
            # Lookup by index.
            index = args[0]
            if isinstance(index, IntObject):
                return self.objects[index.getInt()]

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = args[0]
            if isinstance(index, IntObject):
                return ConstList(self.objects * index._i)

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
            index = args[0]
            if isinstance(index, IntObject):
                return self.put(index.getInt(), args[1])

        if atom is ASMAP_0:
            return ConstMap([(IntObject(i), o)
                for i, o in enumerate(self.objects)])

        raise Refused(atom, args)

    def _makeIterator(self):
        return listIterator(self.objects)

    def put(self, index, value):
        new = self.objects[:]
        new[index] = value
        return ConstList(new)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            return ConstList(self.objects[start:])
        else:
            return ConstList(self.objects[start:stop])

    def snapshot(self):
        return ConstList(self.objects[:])


def pairRepr(pair):
    key, value = pair
    return key.repr() + " => " + value.repr()


class ConstMap(Collection, Object):

    _immutable_fields_ = "objects[*]",

    def __init__(self, objects):
        self.objects = objects

    def asDict(self):
        d = {}
        for k, v in self.objects:
            d[k] = v
        return d

    def repr(self):
        return "[" + ", ".join([pairRepr(pair) for pair in self.objects]) + "]"

    @staticmethod
    def fromPairs(wrappedPairs):
        pairs = []
        for obj in unwrapList(wrappedPairs):
            pair = unwrapList(obj)
            assert len(pair) == 2, "Not a pair!"
            pairs.append((pair[0], pair[1]))
        return ConstMap(pairs)

    def _recv(self, atom, args):
        # XXX we should be using hashing here, not equality, right?
        from typhon.objects.equality import optSame, EQUAL

        if atom is _UNCALL_0:
            rv = ConstList([ConstList([k, v]) for k, v in self.objects])
            return ConstList([StrObject(u"fromPairs"), rv])

        if atom is GET_1:
            key = args[0]
            for (k, v) in self.objects:
                if optSame(key, k) is EQUAL:
                    return v

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        if atom is WITH_2:
            # Replace by index.
            key = args[0]
            value = args[1]
            rv = [(key, value)]
            for (k, v) in self.objects:
                if optSame(key, k) is EQUAL:
                    # Hit!
                    continue
                else:
                    rv.append((k, v))
            return ConstMap(rv[:])

        if atom is WITHOUT_1:
            key = args[0]
            return ConstMap([(k, v) for (k, v) in self.objects
                if optSame(key, k) is not EQUAL])

        raise Refused(atom, args)

    def _makeIterator(self):
        return mapIterator(self.objects)

    def _or(self, other):
        # XXX quadratic time is not my friend
        rv = self.objects[:]
        for ok, ov in unwrapMap(other):
            found = False
            for i, (k, v) in enumerate(rv):
                from typhon.objects.equality import optSame, EQUAL
                if optSame(k, ok) is EQUAL:
                    found = True
            if not found:
                rv.append((ok, ov))
        return ConstMap(rv[:])

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            return ConstMap(self.objects[start:])
        else:
            return ConstMap(self.objects[start:stop])

    def snapshot(self):
        return ConstMap(self.objects[:])


def dictToMap(d):
    l = []
    for k in d:
        l.append((k, d[k]))
    return ConstMap(l)


def unwrapList(o):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.objects
    raise userError(u"Not a list!")


def unwrapMap(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstMap):
        return m.objects
    raise userError(u"Not a map!")
