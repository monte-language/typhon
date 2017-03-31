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
from typhon.objects.collections.helpers import (KeySorter, ValueSorter,
                                                monteMap)
from typhon.objects.data import StrObject
from typhon.objects.ejectors import throwStr
from typhon.objects.printers import toString
from typhon.objects.root import Object, audited
from typhon.profile import profileTyphon


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

    @method("List", "Any")
    def next(self, ej):
        if self._index < len(self.objects):
            k, v = self.objects[self._index]
            rv = [k, v]
            self._index += 1
            return rv
        else:
            throwStr(ej, u"next/1: Iterator exhausted")


@autohelp
@audited.Transparent
class ConstMap(Object):
    """
    An ordered map of objects.
    """

    _immutable_fields_ = "objectMap",

    def __init__(self, objectMap):
        self.objectMap = objectMap

    @method("Void", "Any")
    def _printOn(self, printer):
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

    @method.py("Bool")
    def empty(self):
        return not self.objectMap

    @method("Set")
    def asSet(self):
        # COW optimization.
        return self.objectMap

    @method("Any")
    def diverge(self):
        # Split off a copy so that we are not mutated.
        return FlexMap(self.objectMap.copy())

    @method("Any", "Any", "Any")
    def fetch(self, key, thunk):
        rv = self.objectMap.get(key, None)
        if rv is None:
            rv = thunk.call(u"run", [])
        return rv

    @method("List")
    def getKeys(self):
        return self.objectMap.keys()

    @method("List")
    def getValues(self):
        return self.objectMap.values()

    @method("Any", "Any")
    def get(self, key):
        try:
            return self.objectMap[key]
        except KeyError:
            raise userError(u"Key not found: %s" % (key.toString(),))

    @method("Map")
    def reverse(self):
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        # Reverse it!
        l.reverse()
        for k, v in l:
            d[k] = v
        return d

    @method("Map")
    def sortKeys(self):
        # Extract a list, sort it, pack it back into a dict.
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        KeySorter(l).sort()
        for k, v in l:
            d[k] = v
        return d

    @method("Map")
    def sortValues(self):
        # Same as sortKeys/0.
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        ValueSorter(l).sort()
        for k, v in l:
            d[k] = v
        return d

    @method.py("Map", "Any", "Any", _verb="with")
    def _with(self, key, value):
        # Replace by key.
        d = self.objectMap.copy()
        d[key] = value
        return d

    @method("Map", "Any")
    def without(self, key):
        # Ignore the case where the key wasn't in the map.
        if key in self.objectMap:
            d = self.objectMap.copy()
            del d[key]
            return d
        return self.objectMap

    @method("Any")
    def _makeIterator(self):
        return mapIterator(self.objectMap.items())

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.lists import wrapList
        from typhon.scopes.safe import theMakeMap
        pairs = wrapList([wrapList([k, v])
                          for k, v in self.objectMap.items()])
        rv = wrapList([pairs])
        return [theMakeMap, StrObject(u"fromPairs"), rv, EMPTY_MAP]

    @method.py("Bool", "Any")
    def contains(self, needle):
        return needle in self.objectMap

    @method.py("Map", "Map", _verb="or")
    @profileTyphon("Map.or/1")
    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectMap.copy()
        for ok, ov in other.items():
            if ok not in rv:
                rv[ok] = ov
        return rv

    @method("Map", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        items = self.objectMap.items()[start:]
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return rv

    @method("Map", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        if stop < 0:
            raise userError(u"slice/1: Negative stop")
        items = self.objectMap.items()[start:stop]
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return rv

    @method("Int")
    def size(self):
        return len(self.objectMap)

    @method.py("Bool")
    def isEmpty(self):
        return not self.objectMap

    @method("Map")
    def snapshot(self):
        # This is a copy-on-write optimization; we are trusting the rest of
        # the functions on this map to not alter the map.
        return self.objectMap

    def extractStringKey(self, k, default):
        """
        Extract a string key from this map. On failure, return `default`.
        """

        return self.objectMap.get(StrObject(k), default)

    def withStringKey(self, k, v):
        """
        Add a key-value pair to this map.

        Like Monte m`self.with(k :Str, v)`.
        """

        return ConstMap(self._with(StrObject(k), v))

    def iteritems(self):
        """
        Iterate over (key, value) tuples.

        The normal caveats apply.
        """

        return self.objectMap.iteritems()

EMPTY_MAP = ConstMap(monteMap())


@autohelp
class FlexMap(Object):
    """
    An ordered map of objects.
    """

    def __init__(self, objectMap):
        self.objectMap = objectMap

    @method("Void", "Any")
    def _printOn(self, printer):
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

    @method("Bool")
    def empty(self):
        return not self.objectMap

    @method("Void", "Any", "Any")
    def put(self, key, value):
        self.objectMap[key] = value

    @method("Void", "Any")
    def removeKey(self, key):
        try:
            del self.objectMap[key]
        except KeyError:
            raise userError(u"removeKey/1: Key not in map")

    @method("List")
    def pop(self):
        if self.objectMap:
            key, value = self.objectMap.popitem()
            return [key, value]
        else:
            raise userError(u"pop/0: Pop from empty map")

    @method("Set")
    def asSet(self):
        return self.objectMap.copy()

    @method("Any")
    def diverge(self):
        return FlexMap(self.objectMap.copy())

    @method("Any", "Any", "Any")
    def fetch(self, key, thunk):
        rv = self.objectMap.get(key, None)
        if rv is None:
            rv = thunk.call(u"run", [])
        return rv

    @method("List")
    def getKeys(self):
        return self.objectMap.keys()

    @method("List")
    def getValues(self):
        return self.objectMap.values()

    @method("Any", "Any")
    def get(self, key):
        try:
            return self.objectMap[key]
        except KeyError:
            raise userError(u"get/1: Key not found: %s" % (key.toString(),))

    @method("Map")
    def reverse(self):
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        # Reverse it!
        l.reverse()
        for k, v in l:
            d[k] = v
        return d

    @method("Map")
    def sortKeys(self):
        # Extract a list, sort it, pack it back into a dict.
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        KeySorter(l).sort()
        for k, v in l:
            d[k] = v
        return d

    @method("Map")
    def sortValues(self):
        # Same as sortKeys/0.
        d = monteMap()
        l = [(k, v) for k, v in self.objectMap.iteritems()]
        ValueSorter(l).sort()
        for k, v in l:
            d[k] = v
        return d

    @method("Map", "Any", "Any", _verb="with")
    def _with(self, key, value):
        # Replace by key.
        d = self.objectMap.copy()
        d[key] = value
        return d

    @method("Map", "Any")
    def without(self, key):
        # Even if we don't have the key, we need to copy since we're returning
        # a ConstMap.
        d = self.objectMap.copy()
        # Ignore the case where the key wasn't in the map.
        if key in d:
            del d[key]
        return d

    @method("Any")
    def _makeIterator(self):
        return mapIterator(self.objectMap.items())

    @method("List")
    def _uncall(self):
        from typhon.objects.collections.lists import wrapList
        return [ConstMap(self.objectMap.copy()), StrObject(u"diverge"),
                wrapList([]), EMPTY_MAP]

    @method("Bool", "Any")
    def contains(self, needle):
        return needle in self.objectMap

    @method("Map", "Map", _verb="or")
    def _or(self, other):
        # XXX This is currently linear time. Can it be better? If not, prove
        # it, please.
        rv = self.objectMap.copy()
        for ok, ov in other.items():
            if ok not in rv:
                rv[ok] = ov
        return rv

    @method("Map", "Int")
    def slice(self, start):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        items = self.objectMap.items()[start:]
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return rv

    @method("Map", "Int", "Int", _verb="slice")
    def _slice(self, start, stop):
        if start < 0:
            raise userError(u"slice/1: Negative start")
        if stop < 0:
            raise userError(u"slice/1: Negative stop")
        items = self.objectMap.items()[start:stop]
        rv = monteMap()
        for k, v in items:
            rv[k] = v
        return rv

    @method("Int")
    def size(self):
        return len(self.objectMap)

    @method("Bool")
    def isEmpty(self):
        return not self.objectMap

    @method("Map")
    def snapshot(self):
        return self.objectMap.copy()


def unwrapMap(o):
    from typhon.objects.refs import resolution
    m = resolution(o)
    if isinstance(m, ConstMap):
        return m.objectMap
    if isinstance(m, FlexMap):
        return m.objectMap
    raise WrongType(u"Not a map!")

def wrapMap(d):
    return ConstMap(d)

def isMap(obj):
    from typhon.objects.refs import resolution
    o = resolution(obj)
    return isinstance(o, ConstMap) or isinstance(o, FlexMap)
