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

from rpython.rlib.rarithmetic import intmask

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, WrongType, userError
from typhon.objects.collections.helpers import (KeySorter, ValueSorter,
                                                monteMap)
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon


ASSET_0 = getAtom(u"asSet", 0)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
FETCH_2 = getAtom(u"fetch", 2)
GETKEYS_0 = getAtom(u"getKeys", 0)
GETVALUES_0 = getAtom(u"getValues", 0)
GET_1 = getAtom(u"get", 1)
NEXT_1 = getAtom(u"next", 1)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
POP_0 = getAtom(u"pop", 0)
PUT_2 = getAtom(u"put", 2)
REMOVEKEY_1 = getAtom(u"removeKey", 1)
REVERSE_0 = getAtom(u"reverse", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SNAPSHOT_0 = getAtom(u"snapshot", 0)
SORTKEYS_0 = getAtom(u"sortKeys", 0)
SORTVALUES_0 = getAtom(u"sortValues", 0)
WITHOUT_1 = getAtom(u"without", 1)
WITH_2 = getAtom(u"with", 2)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_PRINTON_1 = getAtom(u"_printOn", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


@autohelp
class mapIterator(Object):
    """
    An iterator on a map, producing its keys and values.
    """

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def toString(self):
        return u"<mapIterator>"

    def recv(self, atom, args):
        if atom is NEXT_1:
            from typhon.objects.collections.lists import ConstList
            if self._index < len(self.objects):
                k, v = self.objects[self._index]
                rv = [k, v]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


@autohelp
@audited.Transparent
class ConstMap(Object):
    """
    An ordered map of objects.
    """

    _immutable_fields_ = "objectMap",

    def __init__(self, objectMap):
        self.objectMap = objectMap

    def asDict(self):
        return self.objectMap

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        i = 0
        for k, v in self.objectMap.iteritems():
            printer.call(u"quote", [k])
            printer.call(u"print", [StrObject(u" => ")])
            printer.call(u"quote", [v])
            if i + 1 < len(self.objectMap):
                printer.call(u"print", [StrObject(u", ")])
            i += 1
        printer.call(u"print", [StrObject(u"]")])
        if len(self.objectMap) == 0:
            printer.call(u"print", [StrObject(u".asMap()")])

    def computeHash(self, depth):
        # We're in too deep.
        if depth <= 0:
            # We won't continue hashing, but we do have to be certain that we
            # are settled.
            if self.isSettled():
                # That settles it; they're settled.
                return -127
            else:
                raise userError(u"Must be settled")


        # Nest each item, hand-unwrapping the nested "tuple" of items.
        x = 0x345678
        for k, v in self.objectMap.items():
            y = 0x345678
            y = intmask((1000003 * y) ^ k.computeHash(depth - 1))
            y = intmask((1000003 * y) ^ v.computeHash(depth - 1))
            x = intmask((1000003 * x) ^ y)
        return x

    @staticmethod
    @profileTyphon("_makeMap.fromPairs/1")
    def fromPairs(wrappedPairs):
        from typhon.objects.collections.lists import unwrapList
        d = monteMap()
        for obj in unwrapList(wrappedPairs):
            pair = unwrapList(obj)
            assert len(pair) == 2, "Not a pair!"
            d[pair[0]] = pair[1]
        return ConstMap(d)

    def toString(self):
        return toString(self)

    def isSettled(self, sofar=None):
        if sofar is None:
            sofar = {self: None}
        for k, v in self.objectMap.iteritems():
            if k not in sofar and not k.isSettled(sofar=sofar):
                return False
            if v not in sofar and not v.isSettled(sofar=sofar):
                return False
        return True

    def recv(self, atom, args):
        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        if atom is _PRINTON_1:
            printer = args[0]
            self.printOn(printer)
            return NullObject

        # contains/1: Determine whether an element is in this collection.
        if atom is CONTAINS_1:
            return wrapBool(self.contains(args[0]))

        # size/0: Get the number of elements in the collection.
        if atom is SIZE_0:
            return IntObject(self.size())

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_1:
            start = unwrapInt(args[0])
            try:
                return self.slice(start)
            except IndexError:
                raise userError(u"slice/1: Index out of bounds")

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_2:
            start = unwrapInt(args[0])
            stop = unwrapInt(args[1])
            try:
                return self.slice(start, stop)
            except IndexError:
                raise userError(u"slice/1: Index out of bounds")

        # snapshot/0: Create a new constant collection with a copy of the
        # current collection's contents.
        if atom is SNAPSHOT_0:
            return self.snapshot()

        from typhon.objects.collections.lists import ConstList

        if atom is _UNCALL_0:
            return ConstList(self._uncall())

        if atom is ASSET_0:
            from typhon.objects.collections.sets import ConstSet
            return ConstSet(self.objectMap)

        if atom is DIVERGE_0:
            # Split off a copy so that we are not mutated.
            return FlexMap(self.objectMap.copy())

        if atom is FETCH_2:
            key = args[0]
            thunk = args[1]
            rv = self.objectMap.get(key, None)
            if rv is None:
                rv = thunk.call(u"run", [])
            return rv

        if atom is GETKEYS_0:
            return ConstList(self.objectMap.keys())

        if atom is GETVALUES_0:
            return ConstList(self.objectMap.values())

        if atom is GET_1:
            key = args[0]
            try:
                return self.objectMap[key]
            except KeyError:
                raise userError(u"Key not found: %s" % (key.toString(),))

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        if atom is REVERSE_0:
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            # Reverse it!
            l.reverse()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTKEYS_0:
            # Extract a list, sort it, pack it back into a dict.
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            KeySorter(l).sort()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTVALUES_0:
            # Same as sortKeys/0.
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            ValueSorter(l).sort()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

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

    def _uncall(self):
        from typhon.objects.collections.lists import ConstList
        from typhon.scopes.safe import theMakeMap
        rv = ConstList([ConstList([k, v]) for k, v in self.objectMap.items()])
        return [theMakeMap, StrObject(u"fromPairs"), rv, EMPTY_MAP]

    def contains(self, needle):
        return needle in self.objectMap

    @profileTyphon("Map.or/1")
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
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return ConstMap(rv)

    def size(self):
        return len(self.objectMap)

    def snapshot(self):
        return ConstMap(self.objectMap.copy())

EMPTY_MAP = ConstMap(monteMap())


@autohelp
@audited.Transparent
class FlexMap(Object):
    """
    An ordered map of objects.
    """

    def __init__(self, objectMap):
        self.objectMap = objectMap

    def asDict(self):
        return self.objectMap

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        i = 0
        for k, v in self.objectMap.iteritems():
            printer.call(u"quote", [k])
            printer.call(u"print", [StrObject(u" => ")])
            printer.call(u"quote", [v])
            if i + 1 < len(self.objectMap):
                printer.call(u"print", [StrObject(u", ")])
            i += 1
        printer.call(u"print", [StrObject(u"]")])
        if len(self.objectMap) == 0:
            printer.call(u"print", [StrObject(u".asMap()")])
        printer.call(u"print", [StrObject(u".diverge()")])

    @staticmethod
    def fromPairs(wrappedPairs):
        from typhon.objects.collections.lists import unwrapList
        d = monteMap()
        for obj in unwrapList(wrappedPairs):
            pair = unwrapList(obj)
            assert len(pair) == 2, "Not a pair!"
            d[pair[0]] = pair[1]
        return ConstMap(d)

    def toString(self):
        return toString(self)

    def put(self, key, value):
        self.objectMap[key] = value

    def removeKey(self, key):
        try:
            del self.objectMap[key]
        except KeyError:
            raise userError(u"removeKey/1: Key not in map")

    def pop(self):
        from typhon.objects.collections.lists import ConstList
        if self.objectMap:
            key, value = self.objectMap.popitem()
            return ConstList([key, value])
        else:
            raise userError(u"pop/0: Pop from empty map")

    def recv(self, atom, args):
        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        if atom is _PRINTON_1:
            printer = args[0]
            self.printOn(printer)
            return NullObject

        # contains/1: Determine whether an element is in this collection.
        if atom is CONTAINS_1:
            return wrapBool(self.contains(args[0]))

        # size/0: Get the number of elements in the collection.
        if atom is SIZE_0:
            return IntObject(self.size())

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_1:
            start = unwrapInt(args[0])
            try:
                return self.slice(start)
            except IndexError:
                raise userError(u"slice/1: Index out of bounds")

        # slice/1 and slice/2: Select a subrange of this collection.
        if atom is SLICE_2:
            start = unwrapInt(args[0])
            stop = unwrapInt(args[1])
            try:
                return self.slice(start, stop)
            except IndexError:
                raise userError(u"slice/1: Index out of bounds")

        # snapshot/0: Create a new constant collection with a copy of the
        # current collection's contents.
        if atom is SNAPSHOT_0:
            return self.snapshot()

        from typhon.objects.collections.lists import ConstList

        if atom is _UNCALL_0:
            return ConstList(self._uncall())

        if atom is ASSET_0:
            from typhon.objects.collections.sets import ConstSet
            return ConstSet(self.objectMap)

        if atom is DIVERGE_0:
            return FlexMap(self.objectMap)

        if atom is FETCH_2:
            key = args[0]
            thunk = args[1]
            rv = self.objectMap.get(key, None)
            if rv is None:
                rv = thunk.call(u"run", [])
            return rv

        if atom is GETKEYS_0:
            return ConstList(self.objectMap.keys())

        if atom is GETVALUES_0:
            return ConstList(self.objectMap.values())

        if atom is GET_1:
            key = args[0]
            try:
                return self.objectMap[key]
            except KeyError:
                raise userError(u"Key not found: %s" % (key.toString(),))

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        if atom is REVERSE_0:
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            # Reverse it!
            l.reverse()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTKEYS_0:
            # Extract a list, sort it, pack it back into a dict.
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            KeySorter(l).sort()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTVALUES_0:
            # Same as sortKeys/0.
            d = monteMap()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            ValueSorter(l).sort()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

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

        if atom is PUT_2:
            key = args[0]
            value = args[1]
            self.put(key, value)
            return NullObject

        if atom is REMOVEKEY_1:
            key = args[0]
            self.removeKey(key)
            return NullObject

        if atom is POP_0:
            return self.pop()

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return mapIterator(self.objectMap.items())

    def _uncall(self):
        from typhon.objects.collections.lists import ConstList
        from typhon.scopes.safe import theMakeMap
        rv = ConstList([ConstList([k, v]) for k, v in self.objectMap.items()])
        return [theMakeMap, StrObject(u"fromPairs"), rv, EMPTY_MAP]

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
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return ConstMap(rv)

    def size(self):
        return len(self.objectMap)

    def snapshot(self):
        return ConstMap(self.objectMap.copy())


def unwrapMap(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstMap):
        return m.objectMap
    if isinstance(m, FlexMap):
        return m.objectMap
    raise WrongType(u"Not a map!")
