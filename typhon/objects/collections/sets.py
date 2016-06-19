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

from typhon.autohelp import autohelp, method
from typhon.errors import WrongType, userError
from typhon.objects.collections.helpers import monteSet
from typhon.objects.data import StrObject
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon


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

    @method("Void", "Any")
    def _printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objectSet.keys()):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objectSet):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].asSet()")])

    @method("Any")
    def _makeIterator(self):
        """
        Create an iterator for this collection's contents.
        """

        from typhon.objects.collections.lists import listIterator
        return listIterator(self.objectSet.keys())

    @method("Bool", "Any")
    def contains(self, needle):
        """
        Determine whether an element is in this collection.
        """

        return needle in self.objectSet

    @method("Set", "Set", _verb="and")
    @profileTyphon("Set.and/1")
    def _and(self, other):
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
        return rv

    @method("Set", "Set", _verb="or")
    @profileTyphon("Set.or/1")
    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok not in rv:
                rv[ok] = None
        return rv

    # XXX Decide if we follow python-style '-' or E-style '&!' here.
    @method.py("Set", "Set")
    @profileTyphon("Set.subtract/1")
    def subtract(self, other):
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok in rv:
                del rv[ok]
        return rv

    @method("Set", "Set")
    def butNot(self, other):
        return self.subtract(other)

    @method("Set", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/2: Negative start")
        keys = self.objectSet.keys()[start:]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return rv

    @method("Set", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/2: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        keys = self.objectSet.keys()[start:stop]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return rv

    @method("Int")
    def size(self):
        return len(self.objectSet)

    @method("Set")
    def snapshot(self):
        return self.objectSet.copy()

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.lists import wrapList
        from typhon.objects.collections.maps import EMPTY_MAP
        # [1,2,3].asSet() -> [[1,2,3], "asSet"]
        rv = wrapList(self.objectSet.keys())
        return [rv, StrObject(u"asSet"), wrapList([]), EMPTY_MAP]

    @method("Set")
    def asSet(self):
        return self.objectSet

    @method("Any")
    def diverge(self):
        return FlexSet(self.objectSet.copy())

    @method("List")
    def asList(self):
        return self.objectSet.keys()

    @method("Set", "Any", _verb="with")
    def _with(self, key):
        d = self.objectSet.copy()
        d[key] = None
        return d

    @method("Set", "Any")
    def without(self, key):
        # If the key isn't in the map, don't bother copying.
        if key in self.objectSet:
            d = self.objectSet.copy()
            del d[key]
            return d
        else:
            return self.objectSet


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

    @method("Void", "Any")
    def _printOn(self, printer):
        printer.call(u"print", [StrObject(u"[")])
        for i, obj in enumerate(self.objectSet.keys()):
            printer.call(u"quote", [obj])
            if i + 1 < len(self.objectSet):
                printer.call(u"print", [StrObject(u", ")])
        printer.call(u"print", [StrObject(u"].asSet().diverge()")])

    @method("Any")
    def _makeIterator(self):
        from typhon.objects.collections.lists import listIterator
        return listIterator(self.objectSet.keys())

    @method("Bool", "Any")
    def contains(self, needle):
        return needle in self.objectSet

    @method("Set", "Set", _verb="and")
    def _and(self, other):
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
        return rv

    @method("Set", "Set", _verb="or")
    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok not in rv:
                rv[ok] = None
        return rv

    @method.py("Set", "Set")
    def subtract(self, other):
        rv = self.objectSet.copy()
        for ok in other.keys():
            if ok in rv:
                del rv[ok]
        return rv

    @method("Set", "Set")
    def butNot(self, other):
        return self.subtract(other)

    @method("Set", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        keys = self.objectSet.keys()[start:]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return rv

    @method("Set", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/2: Negative start")
        if stop < 0:
            raise userError(u"slice/2: Negative stop")
        keys = self.objectSet.keys()[start:stop]
        rv = monteSet()
        for k in keys:
            rv[k] = None
        return rv

    @method("Int")
    def size(self):
        return len(self.objectSet)

    @method.py("Set")
    def snapshot(self):
        return self.objectSet.copy()

    @method("Void", "Any")
    def include(self, key):
        self.objectSet[key] = None

    @method("Void", "Any")
    def remove(self, key):
        try:
            del self.objectSet[key]
        except KeyError:
            raise userError(u"remove/1: Key not in set")

    @method("Any")
    def pop(self):
        if self.objectSet:
            key, _ = self.objectSet.popitem()
            return key
        else:
            raise userError(u"pop/0: Pop from empty set")

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.lists import wrapList
        from typhon.objects.collections.maps import EMPTY_MAP
        # [1,2,3].asSet().diverge() -> [[[1,2,3], "asSet"], "diverge"]
        rv = wrapList(self.objectSet.keys())
        return [wrapList([rv, StrObject(u"asSet"), wrapList([]), EMPTY_MAP]),
                StrObject(u"diverge"), wrapList([]), EMPTY_MAP]

    @method("Set")
    def asSet(self):
        return self.snapshot()

    @method("Any")
    def diverge(self):
        return FlexSet(self.objectSet.copy())

    @method("List")
    def asList(self):
        return self.objectSet.keys()

    @method("Set", "Any", _verb="with")
    def _with(self, key):
        d = self.objectSet.copy()
        d[key] = None
        return d

    @method("Set", "Any")
    def without(self, key):
        d = self.objectSet.copy()
        # Ignore the case where the key wasn't in the map.
        if key in d:
            del d[key]
        return d


def unwrapSet(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstSet):
        return m.objectSet
    if isinstance(m, FlexSet):
        return m.objectSet
    raise WrongType(u"Not a set!")

def wrapSet(d):
    return ConstSet(d)
