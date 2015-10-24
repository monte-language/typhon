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
from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.objectmodel import import_from_mixin, r_ordereddict
from rpython.rlib.rarithmetic import intmask

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import (Ejecting, Refused, UserException, WrongType,
                           userError)
from typhon.objects.auditors import selfless, transparentStamp
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.printers import Printer, toString
from typhon.objects.root import Object
from typhon.prelude import getGlobal
from typhon.rstrategies import rstrategies
from typhon.strategies import strategyFactory


ADD_1 = getAtom(u"add", 1)
AND_1 = getAtom(u"and", 1)
BUTNOT_1 = getAtom(u"butNot", 1)
ASLIST_0 = getAtom(u"asList", 0)
ASMAP_0 = getAtom(u"asMap", 0)
ASSET_0 = getAtom(u"asSet", 0)
CONTAINS_1 = getAtom(u"contains", 1)
DIVERGE_0 = getAtom(u"diverge", 0)
EXTEND_1 = getAtom(u"extend", 1)
FETCH_2 = getAtom(u"fetch", 2)
GETKEYS_0 = getAtom(u"getKeys", 0)
GETVALUES_0 = getAtom(u"getValues", 0)
GET_1 = getAtom(u"get", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
INDEXOF_2 = getAtom(u"indexOf", 2)
INSERT_2 = getAtom(u"insert", 2)
LAST_0 = getAtom(u"last", 0)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEXT_1 = getAtom(u"next", 1)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
POP_0 = getAtom(u"pop", 0)
PUSH_1 = getAtom(u"push", 1)
PUT_2 = getAtom(u"put", 2)
REVERSE_0 = getAtom(u"reverse", 0)
SIZE_0 = getAtom(u"size", 0)
SLICE_1 = getAtom(u"slice", 1)
SLICE_2 = getAtom(u"slice", 2)
SNAPSHOT_0 = getAtom(u"snapshot", 0)
SORTKEYS_0 = getAtom(u"sortKeys", 0)
SORTVALUES_0 = getAtom(u"sortValues", 0)
SORT_0 = getAtom(u"sort", 0)
STARTOF_1 = getAtom(u"startOf", 1)
STARTOF_2 = getAtom(u"startOf", 2)
SUBTRACT_1 = getAtom(u"subtract", 1)
WITHOUT_1 = getAtom(u"without", 1)
WITH_1 = getAtom(u"with", 1)
WITH_2 = getAtom(u"with", 2)
_MAKEITERATOR_0 = getAtom(u"_makeIterator", 0)
_PRINTON_1 = getAtom(u"_printOn", 1)
_UNCALL_0 = getAtom(u"_uncall", 0)


def monteLessThan(left, right):
    # Yes, this is ugly.
    try:
        return unwrapInt(left.call(u"op__cmp", [right])) < 0
    except UserException:
        return unwrapInt(right.call(u"op__cmp", [left])) > 0

def monteLTKey(left, right):
    return monteLessThan(left[0], right[0])

def monteLTValue(left, right):
    return monteLessThan(left[1], right[1])


MonteSorter = make_timsort_class(lt=monteLessThan)
KeySorter = make_timsort_class(lt=monteLTKey)
ValueSorter = make_timsort_class(lt=monteLTValue)


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

        return self._recv(atom, args)


@autohelp
class ConstList(Object):
    """
    A list of objects.
    """

    import_from_mixin(Collection)

    _immutable_fields_ = "storage[*]", "strategy[*]"

    rstrategies.make_accessors(strategy="strategy", storage="storage")

    strategy = None

    stamps = [selfless, transparentStamp]

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
            return ConstMap(self.asMap())

        if atom is ASSET_0:
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
            return ConstList([theMakeList, StrObject(u"run"), self, EMPTY_MAP])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self.strategy.fetch_all(self))

    def asMap(self):
        d = monteDict()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    def asSet(self):
        d = monteDict()
        for o in self.strategy.fetch_all(self):
            d[o] = None
        return d

    def cmp(self, other):
        for i, left in enumerate(self.strategy.fetch_all(self)):
            right = other[i]
            try:
                result = unwrapInt(left.call(u"op__cmp", [right]))
            except UserException:
                result = -unwrapInt(right.call(u"op__cmp", [left]))
            if result < 0:
                return -1
            if result > 0:
                return 1
        return 0

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

    import_from_mixin(Collection)

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
        if atom is ADD_1:
            other = args[0]
            return ConstList(self.strategy.fetch_all(self) +
                             unwrapList(other))

        if atom is ASMAP_0:
            return ConstMap(self.asMap())

        if atom is ASSET_0:
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
            self.strategy.store_all(self, self.strategy.fetch_all(self))
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
        d = monteDict()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    def asSet(self):
        d = monteDict()
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
            self.strategy.insert(self, index, [value])
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
    from typhon.objects.equality import samenessHash
    return samenessHash(resolveKey(key), 10, None, None)


def monteDict():
    return r_ordereddict(keyEq, keyHash)


@autohelp
class ConstMap(Object):
    """
    A map of objects.
    """

    import_from_mixin(Collection)

    _immutable_fields_ = "objectMap",
    stamps = [selfless, transparentStamp]

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
            return ConstList(self._uncall())

        if atom is ASSET_0:
            return ConstSet(self.objectMap)

        if atom is DIVERGE_0:
            _flexMap = getGlobal(u"_flexMap").getValue()
            return _flexMap.call(u"run", [self])

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
            d = monteDict()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            # Reverse it!
            l.reverse()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTKEYS_0:
            # Extract a list, sort it, pack it back into a dict.
            d = monteDict()
            l = [(k, v) for k, v in self.objectMap.iteritems()]
            KeySorter(l).sort()
            for k, v in l:
                d[k] = v
            return ConstMap(d)

        if atom is SORTVALUES_0:
            # Same as sortKeys/0.
            d = monteDict()
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
        rv = monteDict()
        for k, v in items:
            rv[k] = v
        return ConstMap(rv)

    def size(self):
        return len(self.objectMap)

    def snapshot(self):
        return ConstMap(self.objectMap.copy())

EMPTY_MAP = ConstMap(monteDict())


@autohelp
class ConstSet(Object):
    """
    A set of objects.
    """

    import_from_mixin(Collection)

    _immutable_fields_ = "objectMap",
    stamps = [selfless, transparentStamp]

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
        return toString(self)

    def printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objectMap.keys()):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objectMap):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].asSet()")])

    def _recv(self, atom, args):
        if atom is _UNCALL_0:
            # [1,2,3].asSet() -> [[1,2,3], "asSet"]
            rv = ConstList(self.objectMap.keys())
            return ConstList([rv, StrObject(u"asSet"), ConstList([]),
                              EMPTY_MAP])

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
            return ConstList(self.objectMap.keys())

        if atom is BUTNOT_1:
            return self.subtract(args[0])

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

    def _and(self, otherSet):
        other = unwrapSet(otherSet)
        if (len(self.objectMap) > len(other)):
            bigger = self.objectMap
            smaller = other
        else:
            bigger = other
            smaller = self.objectMap

        rv = monteDict()
        for k in smaller:
            if k in bigger:
                rv[k] = None
        return ConstSet(rv)

    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectMap.copy()
        for ok in unwrapSet(other).keys():
            if ok not in rv:
                rv[ok] = None
        return ConstSet(rv)

    def subtract(self, otherSet):
        other = unwrapSet(otherSet)
        rv = self.objectMap.copy()
        for ok in other.keys():
            if ok in rv:
                del rv[ok]
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

    def subtract(self, other):
        rv = self.objectMap.copy()
        for ok in unwrapSet(other).keys():
            if ok in rv:
                del rv[ok]
        return ConstSet(rv)


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


def unwrapMap(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstMap):
        return m.objectMap
    raise WrongType(u"Not a map!")


def unwrapSet(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstSet):
        return m.objectMap
    raise WrongType(u"Not a set!")
