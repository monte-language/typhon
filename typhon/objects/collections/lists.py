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
from rpython.rlib.rarithmetic import intmask

from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, userError
from typhon.errors import UserException
from typhon.objects.collections.helpers import MonteSorter
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import Ejector, throwStr
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon
from typhon.rstrategies import rstrategies
from typhon.strategies.lists import strategyFactory


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

    @method("List", "Any")
    def next(self, ej):
        if self._index < self.size:
            rv = [IntObject(self._index), self.objects[self._index]]
            self._index += 1
            return rv
        else:
            throwStr(ej, u"Iterator exhausted")


@autohelp
class FlexList(Object):
    """
    A mutable list of objects.
    """

    rstrategies.make_accessors(strategy="strategy", storage="storage")

    strategy = None

    def __init__(self, flexObjects):
        strategy = strategyFactory.strategy_type_for(flexObjects)
        strategyFactory.set_initial_strategy(self, strategy, len(flexObjects),
                                             flexObjects)

    def toString(self):
        return toString(self)

    @method("Void", "Any")
    def _printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        items = self.strategy.fetch_all(self)
        for i, obj in enumerate(items):
            printer.call(u"quote", [obj])
            if i + 1 < len(items):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].diverge()")])

    @method("Bool")
    def empty(self):
        return self.strategy.size(self) == 0

    @method("List", "List")
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
        return l[:]

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        return [wrapList(self.snapshot()), StrObject(u"diverge"),
                wrapList([]), EMPTY_MAP]

    @method("List", "List")
    def add(self, other):
        return self.strategy.fetch_all(self) + other

    @method("Any")
    def diverge(self):
        return FlexList(self.strategy.fetch_all(self))

    @method("Void", "Any")
    def extend(self, other):
        # XXX factor me plz
        try:
            data = unwrapList(other)
        except:
            data = listFromIterable(other)
        # Required to avoid passing an empty list to .append(), which
        # apparently cannot deal. Also a quick win. ~ C.
        if len(data) != 0:
            self.strategy.append(self, data)

    @method("Any", "Int")
    def get(self, index):
        # Lookup by index.
        if index >= self.strategy.size(self) or index < 0:
            raise userError(u"get/1: Index %d is out of bounds" % index)
        return self.strategy.fetch(self, index)

    @method("Void", "Int", "Any")
    def insert(self, index, value):
        if index < 0:
            raise userError(u"insert/2: Index %d is out of bounds" % index)
        self.strategy.insert(self, index, [value])

    @method("Any")
    def last(self):
        size = self.strategy.size(self)
        if size:
            return self.strategy.fetch(self, size - 1)
        raise userError(u"last/0: Empty list has no last element")

    @method("List", "Int")
    def multiply(self, count):
        # multiply/1: Create a new list by repeating this list's contents.
        return self.strategy.fetch_all(self) * count

    @method("Any")
    def pop(self):
        try:
            return self.strategy.pop(self, self.strategy.size(self) - 1)
        except IndexError:
            raise userError(u"pop/0: Pop from empty list")

    @method("Void", "Any")
    def push(self, value):
        self.strategy.append(self, [value])

    @method("List")
    def reverse(self):
        new = self.strategy.fetch_all(self)[:]
        new.reverse()
        return new

    @method("Void")
    def reverseInPlace(self):
        new = self.strategy.fetch_all(self)[:]
        new.reverse()
        self.strategy.store_all(self, new)

    @method("List", "Any", _verb="with")
    def _with(self, value):
        # with/1: Create a new list with an appended object.
        return self.strategy.fetch_all(self) + [value]

    @method("List", "Int", "Any", _verb="with")
    def withIndex(self, index, value):
        # Make a new ConstList.
        if index >= self.strategy.size(self) or index < 0:
            raise userError(u"with/2: Index %d is out of bounds" % index)
        new = self.strategy.fetch_all(self)[:]
        new[index] = value
        return new

    @method("Any")
    def _makeIterator(self):
        # This is the behavior we choose: Iterating over a FlexList grants
        # iteration over a snapshot of the list's contents at that point.
        return listIterator(self.strategy.fetch_all(self))

    @method("Map")
    def asMap(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.strategy.fetch_all(self)):
            d[IntObject(i)] = o
        return d

    @method("Set")
    def asSet(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for o in self.strategy.fetch_all(self):
            d[o] = None
        return d

    @method.py("Bool", "Any")
    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.strategy.fetch_all(self):
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    @method("Int", "Any")
    def indexOf(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.strategy.fetch_all(self)):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    @method.py("Void", "Int", "Any")
    def put(self, index, value):
        top = self.strategy.size(self)
        if 0 <= index <= top:
            self.strategy.store(self, index, value)
        else:
            raise userError(u"put/2: Index %d out of bounds for list of length %d" %
                           (index, top))

    @method("Int")
    def size(self):
        return self.strategy.size(self)

    @method("Bool")
    def isEmpty(self):
        return not self.strategy.size(self)

    @method("List", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        stop = self.strategy.size(self)
        return self.strategy.slice(self, start, stop)

    @method("List", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/2: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        return self.strategy.slice(self, start, stop)

    @method.py("List")
    def snapshot(self):
        return self.strategy.fetch_all(self)


def unwrapList(o, ej=None):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.objs
    if isinstance(l, FlexList):
        return l.strategy.fetch_all(l)
    throwStr(ej, u"Not a list!")

def isList(obj):
    from typhon.objects.refs import resolution
    o = resolution(obj)
    return isinstance(o, ConstList) or isinstance(o, FlexList)


def listFromIterable(obj):
    rv = []
    iterator = obj.call(u"_makeIterator", [])
    with Ejector() as ej:
        while True:
            try:
                l = unwrapList(iterator.call(u"next", [ej]))
                if len(l) != 2:
                    raise userError(u"makeList.fromIterable/1: Invalid iterator")
                rv.append(l[1])
            except Ejecting as ex:
                if ex.ejector is ej:
                    return rv[:]
                raise


@autohelp
@audited.Transparent
class ConstList(Object):
    """
    A list of objects.
    """

    _immutable_fields_ = "objs[*]",

    _isSettled = False

    def __init__(self, objs):
        self.objs = objs

    # Do some voodoo for pretty-printing. Cargo-culted voodoo. ~ C.

    def toQuote(self):
        return toString(self)

    def toString(self):
        return toString(self)

    @method("Void", "Any")
    def _printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objs):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objs):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"]")])

    def computeHash(self, depth):
        # We're in too deep.
        if depth <= 0:
            # We won't continue hashing, but we do have to be certain that we
            # are settled.
            if self.isSettled():
                # That settles it; they're settled.
                return -1
            else:
                raise userError(u"Must be settled")

        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.objs:
            y = obj.computeHash(depth - 1)
            x = intmask((1000003 * x) ^ y)
        return x

    def isSettled(self, sofar=None):
        # Check for a usable cached result.
        if self._isSettled:
            return True

        # No cache; do this the hard way.
        if sofar is None:
            sofar = {self: None}
        for v in self.objs:
            if v not in sofar and not v.isSettled(sofar=sofar):
                return False

        # Cache this success; we can't become unsettled.
        self._isSettled = True
        return True

    @method("Bool")
    def empty(self):
        return bool(self.objs)

    @method("List", "List")
    @profileTyphon("List.add/1")
    def add(self, other):
        if other:
            return self.objs + other
        else:
            return self.objs

    @method("List", "List")
    @profileTyphon("List.join/1")
    def join(self, pieces):
        l = []
        filler = self.objs
        first = True
        for piece in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                l.extend(filler)

            l.append(piece)
        return l[:]

    @method("Any")
    def diverge(self):
        # XXX is this copy necessary?
        return FlexList(self.objs[:])

    @method("Any", "Int")
    def get(self, index):
        # Lookup by index.
        if index < 0:
            raise userError(u"get/1: Index %d cannot be negative" % index)

        try:
            return self.objs[index]
        except IndexError:
            raise userError(u"get/1: Index %d is out of bounds" % index)

    @method("Any")
    def last(self):
        if self.objs:
            return self.objs[-1]
        else:
            raise userError(u"last/0: Empty list has no last element")

    @method("List", "Int")
    def multiply(self, count):
        # multiply/1: Create a new list by repeating this list's contents.
        if count < 0:
            raise userError(u"multiply/1: Can't multiply list %d times" % count)
        elif count == 0:
            return []
        else:
            return self.objs * count

    @method("List")
    def reverse(self):
        l = self.objs[:]
        l.reverse()
        return l

    @method("List", "Int", "Any", _verb="with")
    def _with(self, index, value):
        # Replace by index.
        return self.put(index, value)

    @method("List")
    def _uncall(self):
        from typhon.scopes.safe import theMakeList
        from typhon.objects.collections.maps import EMPTY_MAP
        return [theMakeList, StrObject(u"run"), self, EMPTY_MAP]

    @method("Any")
    def _makeIterator(self):
        # XXX could be more efficient with case analysis
        return listIterator(self.objs)

    @method("Map")
    def asMap(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self.objs):
            d[IntObject(i)] = o
        return d

    @method("Set")
    def asSet(self):
        from typhon.objects.collections.sets import monteSet
        d = monteSet()
        for o in self.objs:
            d[o] = None
        return d

    @method("Int", "List")
    @profileTyphon("List.op__cmp/1")
    def op__cmp(self, other):
        for i, left in enumerate(self.objs):
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
        return 0 if len(self.objs) == len(other) else -1

    @method("Bool", "Any")
    @profileTyphon("List.contains/1")
    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.objs:
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    @method("Int", "Any")
    @profileTyphon("List.indexOf/1")
    def indexOf(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self.objs):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    @method.py("List", "Any", _verb="with")
    @profileTyphon("List.with/1")
    def with_(self, obj):
        if not self.objs:
            return [obj]
        else:
            return self.objs + [obj]

    @method.py("List", "Int", "Any")
    def put(self, index, value):
        top = len(self.objs)
        if index == top:
            return self.with_(value)
        else:
            try:
                objs = self.objs[:]
                objs[index] = value
                return objs
            except IndexError:
                raise userError(u"put/2: Index %d out of bounds for list of length %d" %
                                (index, top))

    @method.py("Int")
    @elidable
    def size(self):
        return len(self.objs)

    @method("Bool")
    def isEmpty(self):
        return not self.objs

    @method("List", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        stop = len(self.objs)
        start = min(start, stop)
        return self.objs[start:stop]

    @method("List", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        stop = min(stop, len(self.objs))
        start = min(start, stop)
        return self.objs[start:stop]

    @method("Any")
    def snapshot(self):
        return self

    @method("List")
    @profileTyphon("List.sort/0")
    def sort(self):
        l = self.objs[:]
        MonteSorter(l).sort()
        return l

    @method("Int", "List")
    def startOf(self, needleCL, start=0):
        return self._startOf(needleCL, 0)

    @method.py("Int", "List", "Int", _verb="startOf")
    def _startOf(self, needleCL, start):
        if start < 0:
            raise userError(u"startOf/2: Negative start %d not permitted" %
                    start)
        # This is quadratic. It could be better.
        from typhon.objects.equality import EQUAL, optSame
        for index in range(start, len(self.objs)):
            for needleIndex, needle in enumerate(needleCL):
                offset = index + needleIndex
                if optSame(self.objs[offset], needle) is not EQUAL:
                    break
                return index
        return -1


def wrapList(l):
    return ConstList(l)
