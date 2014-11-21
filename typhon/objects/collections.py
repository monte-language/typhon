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

from typhon.errors import Refused, userError
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, StrObject
from typhon.objects.root import Object


class listIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def recv(self, verb, args):
        if verb == u"next" and len(args) == 1:
            if self._index < len(self.objects):
                rv = [IntObject(self._index), self.objects[self._index],
                        NullObject]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.recv(u"run", [StrObject(u"Iterator exhausted")])
        raise Refused(verb, args)


class mapIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def recv(self, verb, args):
        if verb == u"next" and len(args) == 1:
            if self._index < len(self.objects):
                k, v = self.objects[self._index]
                rv = [k, v, NullObject]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.recv(u"run", [StrObject(u"Iterator exhausted")])
        raise Refused(verb, args)


class Collection(object):
    """
    A common abstraction for several collections which share methods.
    """

    _mixin_ = True

    @specialize.argtype(0)
    def size(self):
        return len(self.objects)

    def recv(self, verb, args):
        # _makeIterator/0: Create an iterator for this collection's contents.
        if verb == u"_makeIterator" and len(args) == 0:
            return self._makeIterator()

        # size/0: Get the number of elements in the collection.
        if verb == u"size" and len(args) == 0:
            return IntObject(self.size())

        # slice/1 and slice/2: Select a subrange of this collection.
        if verb == u"slice" and len(args) >= 1:
            start = args[0]
            if isinstance(start, IntObject):
                if len(args) > 1:
                    stop = args[1]
                    if isinstance(stop, IntObject):
                        return self.slice(start.getInt(), stop.getInt())
                return self.slice(start.getInt())

        # snapshot/0: Create a new constant collection with a copy of the
        # current collection's contents.
        if verb == u"snapshot" and len(args) == 0:
            return self.snapshot()

        return self._recv(verb, args)


class ConstList(Object, Collection):

    _immutable_fields_ = "objects",

    def __init__(self, objects):
        self.objects = objects

    def repr(self):
        return "[" + ", ".join([obj.repr() for obj in self.objects]) + "]"

    def _recv(self, verb, args):
        if verb == u"add" and len(args) == 1:
            other = args[0]
            return ConstList(self.objects + unwrapList(other))

        if verb == u"get" and len(args) == 1:
            # Lookup by index.
            index = args[0]
            if isinstance(index, IntObject):
                return self.objects[index.getInt()]
        if verb == u"multiply" and len(args) == 1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = args[0]
            if isinstance(index, IntObject):
                return ConstList(self.objects * index._i)

        if verb == u"with" and len(args) == 2:
            # Replace by index.
            index = args[0]
            if isinstance(index, IntObject):
                new = self.objects[:]
                new[index.getInt()] = args[1]
                return ConstList(new)

        if verb == u"asMap" and len(args) == 0:
            return ConstMap([(IntObject(i), o)
                for i, o in enumerate(self.objects)])

        raise Refused(verb, args)

    def _makeIterator(self):
        return listIterator(self.objects)

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


class ConstMap(Object, Collection):

    _immutable_fields_ = "objects",

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

    def _recv(self, verb, args):
        # XXX we should be using hashing here, not equality.
        from typhon.objects import EqualizerObject

        if verb == u"_uncall" and len(args) == 0:
            rv = ConstList([ConstList([k, v]) for k, v in self.objects])
            return ConstList([StrObject(u"fromPairs"), rv])

        if verb == u"get" and len(args) == 1:
            key = args[0]
            for (k, v) in self.objects:
                if EqualizerObject().sameEver(key, k):
                    return v

        # or/1: Unify the elements of this collection with another.
        if verb == u"or" and len(args) == 1:
            return self._or(args[0])

        if verb == u"with" and len(args) == 2:
            # Replace by index.
            key = args[0]
            value = args[1]
            rv = [(key, value)]
            for (k, v) in self.objects:
                if EqualizerObject().sameEver(key, k):
                    # Hit!
                    continue
                else:
                    rv.append((k, v))
            return ConstMap(rv)

        if verb == u"without" and len(args) == 1:
            key = args[0]
            return ConstMap([(k, v) for (k, v) in self.objects
                if not EqualizerObject().sameEver(key, k)])

        raise Refused(verb, args)

    def _makeIterator(self):
        return mapIterator(self.objects)

    def _or(self, other):
        # XXX quadratic time is not my friend
        rv = self.objects[:]
        for ok, ov in unwrapMap(other):
            found = False
            for i, (k, v) in enumerate(rv):
                from typhon.objects import EqualizerObject
                if EqualizerObject().sameEver(k, ok):
                    found = True
            if not found:
                rv.append((ok, ov))
        return ConstMap(rv)

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
    from typhon.objects.refs import near
    l = near(o)
    if isinstance(l, ConstList):
        return l.objects
    raise userError(u"Not a list!")


def unwrapMap(o):
    from typhon.objects.refs import near
    m = near(o)
    if isinstance(m, ConstMap):
        return m.objects
    raise userError(u"Not a map!")
