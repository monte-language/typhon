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
from typhon.objects.collections.helpers import monteSet
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.prelude import getGlobal
from typhon.profile import profileTyphon


AND_1 = getAtom(u"and", 1)
ASLIST_0 = getAtom(u"asList", 0)
ASMAP_0 = getAtom(u"asMap", 0)
ASSET_0 = getAtom(u"asSet", 0)
BUTNOT_1 = getAtom(u"butNot", 1)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
GET_1 = getAtom(u"get", 1)
INCLUDE_1 = getAtom(u"include", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
INDEXOF_2 = getAtom(u"indexOf", 2)
INSERT_2 = getAtom(u"insert", 2)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
POP_0 = getAtom(u"pop", 0)
REMOVE_1 = getAtom(u"remove", 1)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SNAPSHOT_0 = getAtom(u"snapshot", 0)
SUBTRACT_1 = getAtom(u"subtract", 1)
WITHOUT_1 = getAtom(u"without", 1)
WITH_1 = getAtom(u"with", 1)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_PRINTON_1 = getAtom(u"_printOn", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


@autohelp
@audited.Transparent
class ConstSet(Object):
    """
    An ordered set of distinct objects.
    """

    _immutable_fields_ = "objectSet",

    def __init__(self, objectSet):
        self.objectSet = objectSet

    def toString(self):
        return toString(self)

    def asDict(self):
        return self.objectSet

    def computeHash(self, depth):
        # We're in too deep.
        if depth <= 0:
            # We won't continue hashing, but we do have to be certain that we
            # are settled.
            if self.isSettled():
                # That settles it; they're settled.
                return -63
            else:
                raise userError(u"Must be settled")


        # Hash as if we were a list, but change our starting seed so that
        # we won't hash exactly equal.
        x = 0x3456789
        for obj in self.objectSet.keys():
            y = obj.computeHash(depth - 1)
            x = intmask((1000003 * x) ^ y)
        return x

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objectSet.keys()):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objectSet):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].asSet()")])

    def _makeIterator(self):
        from typhon.objects.collections.lists import listIterator
        return listIterator(self.objectSet.keys())

    def contains(self, needle):
        return needle in self.objectSet

    @profileTyphon("Set.and/1")
    def _and(self, otherSet):
        other = unwrapSet(otherSet)
        if (len(self.objectSet) > len(other)):
            bigger = self.objectSet
            smaller = other
        else:
            bigger = other
            smaller = self.objectSet

        rv = monteSet()
        for k in smaller:
            if k in bigger:
                rv[k] = None
        return ConstSet(rv)

    @profileTyphon("Set.or/1")
    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectSet.copy()
        for ok in unwrapSet(other).keys():
            if ok not in rv:
                rv[ok] = None
        return ConstSet(rv)

    @profileTyphon("Set.subtract/1")
    def subtract(self, otherSet):
        other = unwrapSet(otherSet)
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok in rv:
                del rv[ok]
        return ConstSet(rv)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            keys = self.objectSet.keys()[start:]
        else:
            keys = self.objectSet.keys()[start:stop]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return ConstSet(rv)

    def size(self):
        return len(self.objectSet)

    def snapshot(self):
        return ConstSet(self.objectSet.copy())

    def recv(self, atom, args):
        from typhon.objects.collections.lists import wrapList

        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        if atom is _PRINTON_1:
            printer = args[0]
            self.printOn(printer)
            return NullObject

        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            # [1,2,3].asSet() -> [[1,2,3], "asSet"]
            rv = wrapList(self.objectSet.keys())
            return wrapList([rv, StrObject(u"asSet"), wrapList([]),
                              EMPTY_MAP])

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

        if atom is ASSET_0:
            return self

        if atom is DIVERGE_0:
            return FlexSet(self.objectSet)

        if atom is AND_1:
            return self._and(args[0])

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        # XXX Decide if we follow python-style '-' or E-style '&!' here.
        if atom is SUBTRACT_1:
            return self.subtract(args[0])

        if atom is ASLIST_0:
            return wrapList(self.objectSet.keys())

        if atom is BUTNOT_1:
            return self.subtract(args[0])

        if atom is WITH_1:
            key = args[0]
            d = self.objectSet.copy()
            d[key] = None
            return ConstSet(d)

        if atom is WITHOUT_1:
            key = args[0]
            d = self.objectSet.copy()
            # Ignore the case where the key wasn't in the map.
            if key in d:
                del d[key]
            return ConstSet(d)

        raise Refused(self, atom, args)


@autohelp
@audited.Transparent
class FlexSet(Object):
    """
    An ordered set of distinct objects.
    """

    def __init__(self, objectSet):
        self.objectSet = objectSet

    def toString(self):
        return toString(self)

    def asDict(self):
        return self.objectSet

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objectSet.keys()):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objectSet):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].asSet().diverge()")])

    def _makeIterator(self):
        from typhon.objects.collections.lists import listIterator
        return listIterator(self.objectSet.keys())

    def contains(self, needle):
        return needle in self.objectSet

    def _and(self, otherSet):
        other = unwrapSet(otherSet)
        if (len(self.objectSet) > len(other)):
            bigger = self.objectSet
            smaller = other
        else:
            bigger = other
            smaller = self.objectSet

        rv = monteSet()
        for k in smaller:
            if k in bigger:
                rv[k] = None
        return ConstSet(rv)

    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectSet.copy()
        for ok in unwrapSet(other).keys():
            if ok not in rv:
                rv[ok] = None
        return ConstSet(rv)

    def subtract(self, otherSet):
        other = unwrapSet(otherSet)
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok in rv:
                del rv[ok]
        return ConstSet(rv)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            keys = self.objectSet.keys()[start:]
        else:
            keys = self.objectSet.keys()[start:stop]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return ConstSet(rv)

    def size(self):
        return len(self.objectSet)

    def snapshot(self):
        return ConstSet(self.objectSet.copy())

    def include(self, key):
        self.objectSet[key] = None

    def remove(self, key):
        try:
            del self.objectSet[key]
        except KeyError:
            raise userError(u"remove/1: Key not in set")

    def pop(self):
        if self.objectSet:
            key, _ = self.objectSet.popitem()
            return key
        else:
            raise userError(u"pop/0: Pop from empty set")

    def recv(self, atom, args):
        from typhon.objects.collections.lists import wrapList

        # _makeIterator/0: Create an iterator for this collection's contents.
        if atom is _MAKEITERATOR_0:
            return self._makeIterator()

        if atom is _PRINTON_1:
            printer = args[0]
            self.printOn(printer)
            return NullObject

        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            # [1,2,3].asSet() -> [[1,2,3], "asSet"]
            rv = wrapList(self.objectSet.keys())
            return wrapList([rv, StrObject(u"asSet"), wrapList([]),
                              EMPTY_MAP])

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

        if atom is ASSET_0:
            return self

        if atom is DIVERGE_0:
            _flexSet = getGlobal(u"_flexSet").getValue()
            return _flexSet.call(u"run", [self])

        if atom is AND_1:
            return self._and(args[0])

        # or/1: Unify the elements of this collection with another.
        if atom is OR_1:
            return self._or(args[0])

        # XXX Decide if we follow python-style '-' or E-style '&!' here.
        if atom is SUBTRACT_1:
            return self.subtract(args[0])

        if atom is ASLIST_0:
            return wrapList(self.objectSet.keys())

        if atom is BUTNOT_1:
            return self.subtract(args[0])

        if atom is WITH_1:
            key = args[0]
            d = self.objectSet.copy()
            d[key] = None
            return ConstSet(d)

        if atom is WITHOUT_1:
            key = args[0]
            d = self.objectSet.copy()
            # Ignore the case where the key wasn't in the map.
            if key in d:
                del d[key]
            return ConstSet(d)

        if atom is INCLUDE_1:
            key = args[0]
            self.include(key)
            return NullObject

        if atom is REMOVE_1:
            key = args[0]
            self.remove(key)
            return NullObject

        if atom is POP_0:
            return self.pop()

        raise Refused(self, atom, args)


def unwrapSet(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstSet):
        return m.objectSet
    if isinstance(m, FlexSet):
        return m.objectSet
    raise WrongType(u"Not a set!")
