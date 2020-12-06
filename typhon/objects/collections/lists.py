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

from typhon.autohelp import autohelp, method
from typhon.errors import Ejecting, userError
from typhon.errors import UserException
from typhon.objects.collections.helpers import MonteSorter
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.ejectors import Ejector, throwStr
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon


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
            throwStr(ej, u"listIterator.next/1: end of list")


@autohelp
class FlexList(Object):
    """
    A mutable list of objects.
    """

    def __init__(self, objects, guard=None):
        self._g = guard
        self._l = [self.coerce(obj) for obj in objects]

    def toString(self):
        return toString(self)

    def coerce(self, element):
        if self._g is None:
            return element
        else:
            from typhon.objects.constants import NullObject
            return self._g.call(u"coerce", [element, NullObject])

    @method("Void", "Any")
    def _printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self._l):
            if i != 0:
                printer.call(u"print", [StrObject(u", ")])
            printer.call(u"quote", [obj])
        printer.call(u"print", [StrObject(u"].diverge(")])
        if self._g is not None:
            printer.call(u"print", [self._g])
        printer.call(u"print", [StrObject(u")")])

    @method("Bool")
    def empty(self):
        return not bool(self._l)

    @method("Void")
    def clear(self):
        "Remove all elements from this list."
        self._l[0:len(self._l)] = []

    @method("List", "List")
    def join(self, pieces):
        l = []
        first = True
        for piece in pieces:
            # For all iterations except the first, append a copy of
            # ourselves.
            if first:
                first = False
            else:
                l.extend(self._l)

            l.append(piece)
        return l[:]

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.maps import EMPTY_MAP
        args = wrapList([] if self._g is None else [self._g])
        return [wrapList(self.snapshot()), StrObject(u"diverge"), args,
                EMPTY_MAP]

    @method("List", "List")
    def add(self, other):
        return self._l + other

    @method("Any")
    def diverge(self):
        "A mutable copy of this list."
        return FlexList(self._l)

    @method("Any", "Any", _verb="diverge")
    def divergeGuard(self, guard):
        "A mutable copy of this list, guarded by `guard`."
        return FlexList(self._l, guard=guard)

    @method("Void", "Any")
    def extend(self, other):
        # XXX factor me plz
        try:
            data = unwrapList(other)
        except:
            data = listFromIterable(other)
        self._l.extend([self.coerce(elt) for elt in data])

    @method("Any", "Int")
    def get(self, index):
        # Lookup by index.
        if 0 <= index < len(self._l):
            return self._l[index]
        else:
            raise userError(u"get/1: Index %d is out of bounds" % index)

    @method("Void", "Int", "Any")
    def insert(self, index, value):
        if 0 <= index < len(self._l):
            self._l.insert(index, self.coerce(value))
        elif index == len(self._l):
            self._l.append(self.coerce(value))
        else:
            raise userError(u"insert/2: Index %d is out of bounds" % index)

    @method("Any")
    def last(self):
        try:
            return self._l[-1]
        except IndexError:
            raise userError(u"last/0: Empty list has no last element")

    @method("List", "Int")
    def multiply(self, count):
        # multiply/1: Create a new list by repeating this list's contents.
        return self._l * count

    @method("Any")
    def pop(self):
        try:
            return self._l.pop()
        except IndexError:
            raise userError(u"pop/0: Pop from empty list")

    @method("Void", "Any")
    def push(self, value):
        self._l.append(self.coerce(value))

    @method("List")
    def reverse(self):
        new = self._l[:]
        new.reverse()
        return new

    @method("Void")
    def reverseInPlace(self):
        self._l.reverse()

    @method("List", "Any", _verb="with")
    def _with(self, value):
        # with/1: Create a new list with an appended object.
        return self._l + [value]

    @method("List", "Int", "Any", _verb="with")
    def withIndex(self, index, value):
        # Make a new ConstList.
        if not (0 < index < len(self._l)):
            raise userError(u"with/2: Index %d is out of bounds" % index)
        new = self._l[:]
        new[index] = value
        return new

    @method("Any")
    def _makeIterator(self):
        # This is the behavior we choose: Iterating over a FlexList grants
        # iteration over a snapshot of the list's contents at that point.
        return listIterator(self._l[:])

    @method("Map")
    def asMap(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for i, o in enumerate(self._l):
            d[IntObject(i)] = o
        return d

    @method("Set")
    def asSet(self):
        from typhon.objects.collections.maps import monteMap
        d = monteMap()
        for o in self._l:
            d[o] = None
        return d

    @method.py("Bool", "Any")
    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self._l:
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    @method("Int", "Any")
    def indexOf(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for index, specimen in enumerate(self._l):
            if optSame(needle, specimen) is EQUAL:
                return index
        return -1

    @method.py("Void", "Int", "Any")
    def put(self, index, value):
        top = len(self._l)
        if 0 <= index < top:
            self._l[index] = self.coerce(value)
        else:
            raise userError(u"put/2: Index %d out of bounds for list of length %d" %
                           (index, top))

    @method("Int")
    def size(self):
        return len(self._l)

    @method("Bool")
    def isEmpty(self):
        return not bool(self._l)

    @method("List", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        return self._l[start:]

    @method("List", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/2: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        return self._l[start:stop]

    @method.py("List")
    def snapshot(self):
        return self._l[:]


def unwrapList(o, ej=None):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l.objs
    if isinstance(l, FlexList):
        return l._l[:]
    throwStr(ej, u"Specimen is not List: " + l.toString())

def isList(obj):
    from typhon.objects.refs import resolution
    o = resolution(obj)
    return isinstance(o, ConstList) or isinstance(o, FlexList)


def listFromIterable(obj):
    rv = []
    iterator = obj.call(u"_makeIterator", [])
    with Ejector(u"makeList.fromIterable") as ej:
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
        from typhon.objects.equality import samenessHash
        return samenessHash(self, depth, None)

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
        "A mutable copy of this list."
        # NB: This copy is necessary to appease RPython.
        return FlexList(self.objs[:])

    @method("Any", "Any", _verb="diverge")
    def divergeGuard(self, guard):
        "A mutable copy of this list, guarded by `guard`."
        return FlexList(self.objs[:], guard=guard)

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
