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

from rpython.rlib.jit import elidable
from rpython.rlib.objectmodel import import_from_mixin
from rpython.rlib.rarithmetic import intmask

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Ejecting, Refused, UserException, userError
from typhon.objects.collections.helpers import MonteSorter
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.rstrategies import rstrategies
from typhon.strategies.lists import strategyFactory


ADD_1 = getAtom(u"add", 1)
ASMAP_0 = getAtom(u"asMap", 0)
ASSET_0 = getAtom(u"asSet", 0)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
EXTEND_1 = getAtom(u"extend", 1)
GET_1 = getAtom(u"get", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
INDEXOF_2 = getAtom(u"indexOf", 2)
INSERT_2 = getAtom(u"insert", 2)
JOIN_1 = getAtom(u"join", 1)
LAST_0 = getAtom(u"last", 0)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEXT_1 = getAtom(u"next", 1)
OP__CMP_1 = getAtom(u"op__cmp", 1)
POP_0 = getAtom(u"pop", 0)
PUSH_1 = getAtom(u"push", 1)
PUT_2 = getAtom(u"put", 2)
REVERSEINPLACE_0 = getAtom(u"reverseInPlace", 0)
REVERSE_0 = getAtom(u"reverse", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SNAPSHOT_0 = getAtom(u"snapshot", 0)
SORT_0 = getAtom(u"sort", 0)
STARTOF_1 = getAtom(u"startOf", 1)
STARTOF_2 = getAtom(u"startOf", 2)
WITH_1 = getAtom(u"with", 1)
WITH_2 = getAtom(u"with", 2)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_PRINTON_1 = getAtom(u"_printOn", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


@autohelp
class listIterator(Object):
    """
    An iterator on a list, producing its elements.
    """

    _immutable_fields_ = "objects[*]", "size"

    _index = 0

    def __init__(self, objects):
        self.objects = objects
        self.size = len(objects)

    def toString(self):
        return u"<listIterator>"

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < self.size:
                rv = [IntObject(self._index), self.objects[self._index]]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


class List(object):
    """
    A common abstraction for several collections which share methods.
    """

    def toString(self):
        return toString(self)

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

        if atom is JOIN_1:
            l = unwrapList(args[0])
            return self.join(l)

        return self._recv(atom, args)

    def join(self, pieces):
        l = []
        filler = self.strategy.fetch_all(self)
        first = True
        for piece in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                l.extend(filler)

            l.append(piece)
        return ConstList(l[:])


@autohelp
@audited.Transparent
class ConstList(Object):
    """
    A list of objects.
    """

    import_from_mixin(List)

    _immutable_fields_ = "storage[*]", "strategy[*]"

    rstrategies.make_accessors(strategy="strategy", storage="storage")

    strategy = None

    def __init__(self, objects):
        strategy = strategyFactory.strategy_type_for(objects)
        strategyFactory.set_initial_strategy(self, strategy, len(objects),
                                             objects)

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        items = self.strategy.fetch_all(self)
        for i, obj in enumerate(items):
            printer.call(u"quote", [obj])
            if i + 1 < len(items):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"]")])

    def hash(self):
        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.strategy.fetch_all(self):
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def _recv(self, atom, args):
        if atom is ADD_1:
            other = unwrapList(args[0])
            if len(other):
                return ConstList(self.strategy.fetch_all(self) + other)
            else:
                return self

        if atom is ASMAP_0:
            from typhon.objects.collections.maps import ConstMap
            return ConstMap(self.asMap())

        if atom is ASSET_0:
            from typhon.objects.collections.sets import ConstSet
            return ConstSet(self.asSet())

        if atom is DIVERGE_0:
            return FlexList(self.strategy.fetch_all(self)[:])

        if atom is GET_1:
            # Lookup by index.
            index = unwrapInt(args[0])
            if index < 0:
                raise userError(u"Index %d cannot be negative" % index)
            if index >= self.strategy.size(self):
                raise userError(u"Index %d is out of bounds" % index)
            return self.strategy.fetch(self, index)

        if atom is INDEXOF_1:
            return IntObject(self.indexOf(args[0]))

        if atom is LAST_0:
            size = self.strategy.size(self)
            if size:
                return self.strategy.fetch(self, size - 1)
            raise userError(u"Empty list has no last element")

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            count = unwrapInt(args[0])
            if count < 0:
                raise userError(u"Can't multiply list %d times" % count)
            elif count == 0:
                return ConstList([])
            return ConstList(self.strategy.fetch_all(self) * count)

        if atom is OP__CMP_1:
            other = unwrapList(args[0])
            return IntObject(self.cmp(other))

        if atom is REVERSE_0:
            # This might seem slightly inefficient, and it might be, but I
            # want to make it very clear to RPython that we are not mutating
            # the list after we assign it to the new object.
            new = self.strategy.fetch_all(self)[:]
            new.reverse()
            return ConstList(new)

        if atom is SORT_0:
            return self.sort()

        if atom is STARTOF_1:
            return IntObject(self.startOf(unwrapList(args[0])))

        if atom is STARTOF_2:
            start = unwrapInt(args[1])
            if start < 0:
                raise userError(u"startOf/2: Negative start %d not permitted"
                                % start)
            return IntObject(self.startOf(unwrapList(args[0]), start))

        if atom is WITH_1:
            # with/1: Create a new list with an appended object.
            return ConstList(self.strategy.fetch_all(self) + args)

        if atom is WITH_2:
            # Replace by index.
            index = unwrapInt(args[0])
            return self.put(index, args[1])

        if atom is _UNCALL_0:
            from typhon.scopes.safe import theMakeList
            from typhon.objects.collections.maps import EMPTY_MAP
            return ConstList([theMakeList, StrObject(u"run"), self, EMPTY_MAP])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self.strategy.fetch_all(self))

    def asMap(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    def asSet(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for o in self.strategy.fetch_all(self):
            d[o] = None
        return d

    def cmp(self, other):
        for i, left in enumerate(self.strategy.fetch_all(self)):
            try:
                right = other[i]
            except IndexError:
                # They're shorter than us.
                return 1
            try:
                result = unwrapInt(left.call(u"op__cmp", [right]))
            except UserException:
                result = -unwrapInt(right.call(u"op__cmp", [left]))
            if result < 0:
                return -1
            if result > 0:
                return 1
        # They could be longer than us but we were equal up to this point.
        # Do a final length check.
        return 0 if self.size() == len(other) else -1

    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.strategy.fetch_all(self):
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    def indexOf(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.strategy.fetch_all(self)):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    def put(self, index, value):
        objects = self.strategy.fetch_all(self)
        top = self.strategy.size(self)
        if 0 <= index < top:
            new = objects[:]
            new[index] = value
        elif index == top:
            new = objects + [value]
        else:
            raise userError(u"Index %d out of bounds for list of length %d" %
                           (index, self.strategy.size(self)))

        return ConstList(new)

    @elidable
    def size(self):
        return self.strategy.size(self)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            stop = self.strategy.size(self)

        return ConstList(self.strategy.slice(self, start, stop))

    def snapshot(self):
        return ConstList(self.strategy.fetch_all(self))

    def sort(self):
        l = self.strategy.fetch_all(self)
        MonteSorter(l).sort()
        return ConstList(l)

    def startOf(self, needleList, start=0):
        # This is quadratic. It could be better.
        from typhon.objects.equality import EQUAL, optSame
        for index in range(start, self.strategy.size(self)):
            for needleIndex, needle in enumerate(needleList):
                offset = index + needleIndex
                if optSame(self.strategy.fetch(self, offset), needle) is not EQUAL:
                    break
                return index
        return -1


@autohelp
class FlexList(Object):
    """
    A mutable list of objects.
    """

    import_from_mixin(List)

    rstrategies.make_accessors(strategy="strategy", storage="storage")

    strategy = None

    def __init__(self, flexObjects):
        strategy = strategyFactory.strategy_type_for(flexObjects)
        strategyFactory.set_initial_strategy(self, strategy, len(flexObjects),
                                             flexObjects)

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        items = self.strategy.fetch_all(self)
        for i, obj in enumerate(items):
            printer.call(u"quote", [obj])
            if i + 1 < len(items):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].diverge()")])

    def hash(self):
        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.strategy.fetch_all(self):
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def _recv(self, atom, args):
        if atom is _UNCALL_0:
            from typhon.objects.collections.maps import EMPTY_MAP
            return ConstList([self.snapshot(), StrObject(u"diverge"),
                              ConstList([]), EMPTY_MAP])

        if atom is ADD_1:
            other = args[0]
            return ConstList(self.strategy.fetch_all(self) +
                             unwrapList(other))

        if atom is ASMAP_0:
            from typhon.objects.collections.maps import ConstMap
            return ConstMap(self.asMap())

        if atom is ASSET_0:
            from typhon.objects.collections.sets import ConstSet
            return ConstSet(self.asSet())

        if atom is DIVERGE_0:
            return FlexList(self.strategy.fetch_all(self))

        if atom is EXTEND_1:
            from typhon.objects.refs import resolution
            l = resolution(args[0])
            # The early exits are essential here; without them, we might pass
            # an empty list to strategy.append(), which causes a crash. ~ C.
            if isinstance(l, ConstList):
                if l.size() == 0:
                    return NullObject
                data = l.strategy.fetch_all(l)
            elif isinstance(l, FlexList):
                if l.size() == 0:
                    return NullObject
                data = l.strategy.fetch_all(l)
            else:
                data = listFromIterable(l)[:]
            self.strategy.append(self, data)
            return NullObject

        if atom is GET_1:
            # Lookup by index.
            index = unwrapInt(args[0])
            if index >= self.strategy.size(self) or index < 0:
                raise userError(u"Index %d is out of bounds" % index)
            return self.strategy.fetch(self, index)

        if atom is INDEXOF_1:
            return IntObject(self.indexOf(args[0]))

        if atom is INSERT_2:
            index = unwrapInt(args[0])
            value = args[1]
            if index < 0:
                raise userError(u"Index %d is out of bounds" % index)
            self.strategy.insert(self, index, [value])
            return NullObject

        if atom is LAST_0:
            size = self.strategy.size(self)
            if size:
                return self.strategy.fetch(self, size - 1)
            raise userError(u"Empty list has no last element")

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = unwrapInt(args[0])
            return ConstList(self.strategy.fetch_all(self) * index)

        if atom is POP_0:
            try:
                return self.strategy.pop(self, self.strategy.size(self) - 1)
            except IndexError:
                raise userError(u"pop/0: Pop from empty list")

        if atom is PUSH_1:
            self.strategy.append(self, args)
            return NullObject

        if atom is PUT_2:
            # Replace by index.
            index = unwrapInt(args[0])
            return self.put(index, args[1])

        if atom is REVERSE_0:
            new = self.strategy.fetch_all(self)[:]
            new.reverse()
            return ConstList(new)

        if atom is REVERSEINPLACE_0:
            new = self.strategy.fetch_all(self)[:]
            new.reverse()
            self.strategy.store_all(self, new)
            return NullObject

        if atom is WITH_1:
            # with/1: Create a new list with an appended object.
            return ConstList(self.strategy.fetch_all(self) + args)

        if atom is WITH_2:
            # Make a new ConstList.
            return self.snapshot().put(unwrapInt(args[0]), args[1])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        # This is the behavior we choose: Iterating over a FlexList grants
        # iteration over a snapshot of the list's contents at that point.
        return listIterator(self.strategy.fetch_all(self))

    def asMap(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    def asSet(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for o in self.strategy.fetch_all(self):
            d[o] = None
        return d

    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.strategy.fetch_all(self):
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    def indexOf(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.strategy.fetch_all(self)):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    def put(self, index, value):
        top = self.strategy.size(self)
        if 0 <= index <= top:
            self.strategy.store(self, index, value)
        else:
            raise userError(u"Index %d out of bounds for list of length %d" %
                           (index, top))

        return NullObject

    def size(self):
        return self.strategy.size(self)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            stop = self.strategy.size(self)

        return ConstList(self.strategy.slice(self, start, stop))

    def snapshot(self):
        return ConstList(self.strategy.fetch_all(self))


def unwrapList(o, ej=None):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.strategy.fetch_all(l)
    if isinstance(l, FlexList):
        return l.strategy.fetch_all(l)
    throw(ej, StrObject(u"Not a list!"))


def listFromIterable(obj):
    rv = []
    iterator = obj.call(u"_makeIterator", [])
    ej = Ejector()
    while True:
        try:
            l = unwrapList(iterator.call(u"next", [ej]))
            if len(l) != 2:
                raise userError(u"makeList.fromIterable/1: Invalid iterator")
            rv.append(l[1])
        except Ejecting as ex:
            if ex.ejector is ej:
                ej.disable()
                return rv
            raise
