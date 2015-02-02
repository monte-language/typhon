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

from rpython.rlib.jit import look_inside_iff, loop_unrolling_heuristic
from rpython.rlib.rarithmetic import intmask
from rpython.rlib.rerased import new_erasing_pair

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.collections import Collection, ConstMap, ConstSet, monteDict
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.root import Object
from typhon.prelude import getGlobal


ADD_1 = getAtom(u"add", 1)
ASMAP_0 = getAtom(u"asMap", 0)
ASSET_0 = getAtom(u"asSet", 0)
DIVERGE_0 = getAtom(u"diverge", 0)
GET_1 = getAtom(u"get", 1)
INDEXOF_1 = getAtom(u"indexOf", 1)
MULTIPLY_1 = getAtom(u"multiply", 1)
NEXT_1 = getAtom(u"next", 1)
REVERSE_0 = getAtom(u"reverse", 0)
WITH_1 = getAtom(u"with", 1)
WITH_2 = getAtom(u"with", 2)


class listIterator(Object):

    _immutable_fields_ = "objects",

    _index = 0

    def __init__(self, objects):
        self.objects = objects

    def recv(self, atom, args):
        if atom is NEXT_1:
            if self._index < self.objects.size:
                rv = ConstList.pair(IntObject(self._index),
                                    self.objects.get(self._index))
                self._index += 1
                return rv
            else:
                ej = args[0]
                ej.call(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(self, atom, args)


CUTOFF = 7

@look_inside_iff(lambda l, ty: loop_unrolling_heuristic(l, len(l), CUTOFF))
def typecheck(l, ty):
    for i in l:
        if not isinstance(i, ty):
            return False
    return True


class ConstList(Collection, Object):

    _immutable_fields_ = "size", "storage", "strategy"

    def __init__(self, objects, strategy):
        self.size = len(objects)
        self.strategy = strategy
        self.storage = self.strategy.stash(objects)

    @staticmethod
    def withoutStrategy(objects):
        """
        Pessimistic constructor. Pick a good strategy for these objects and
        build a list with it.
        """

        if not objects:
            strategy = EmptyListStrategy
        elif typecheck(objects, IntObject):
            strategy = IntListStrategy
        elif len(objects) == 2:
            strategy = PairListStrategy
        else:
            strategy = GenericListStrategy

        return ConstList(objects, strategy)

    @staticmethod
    def empty():
        return ConstList([], EmptyListStrategy)

    @staticmethod
    def pair(x, y):
        return ConstList([x, y], PairListStrategy)

    @staticmethod
    def ints(xs):
        l = ConstList.empty()
        l.size = len(xs)
        l.strategy = IntListStrategy
        l.storage = eraseInt(xs)
        return l

    def asList(self):
        return self.strategy.unstash(self.storage)

    def toString(self):
        guts = u", ".join([obj.toString() for obj in self.asList()])
        return u"[%s]" % (guts,)

    def hash(self):
        # Use the same sort of hashing as CPython's tuple hash.
        x = 0x345678
        for obj in self.asList():
            y = obj.hash()
            x = intmask((1000003 * x) ^ y)
        return x

    def _recv(self, atom, args):
        if atom is ADD_1:
            other = reduceList(args[0])
            # And have the strategy do the actual heavy lifting.
            return self.strategy.add(self.storage, other)

        if atom is ASMAP_0:
            d = monteDict()
            for i, o in enumerate(self.asList()):
                d[IntObject(i)] = o
            return ConstMap(d)

        if atom is ASSET_0:
            d = monteDict()
            for o in self.asList():
                d[o] = None
            return ConstSet(d)

        if atom is DIVERGE_0:
            _flexList = getGlobal(u"_flexList")
            return _flexList.call(u"run", [self])

        if atom is GET_1:
            # Lookup by index.
            index = unwrapInt(args[0])
            return self.get(index)

        if atom is INDEXOF_1:
            from typhon.objects.equality import EQUAL, optSame
            needle = args[0]
            for index, specimen in enumerate(self.asList()):
                if optSame(needle, specimen) is EQUAL:
                    return IntObject(index)
            return IntObject(-1)

        if atom is MULTIPLY_1:
            # multiply/1: Create a new list by repeating this list's contents.
            index = unwrapInt(args[0])
            if index < 0:
                raise userError(
                    u"Can't repeat list a negative number of times")
            # Our strategy can usually be reused here.
            if self.strategy.multiplies:
                return ConstList(self.asList() * index, self.strategy)
            return ConstList.withoutStrategy(self.asList() * index)

        if atom is REVERSE_0:
            return self.reverse()

        if atom is WITH_1:
            # with/1: Create a new list with an appended object.
            appended = self.asList() + args
            # Check to see whether our current strategy can admit this new
            # object. If so, then no change of strategy is needed.
            if self.strategy.admits(args[0]):
                return ConstList(appended, self.strategy)
            # If not, then go with the slow path.
            return ConstList.withoutStrategy(appended)

        if atom is WITH_2:
            # Replace by index.
            index = unwrapInt(args[0])
            return self.put(index, args[1])

        raise Refused(self, atom, args)

    def _makeIterator(self):
        return listIterator(self)

    def contains(self, needle):
        from typhon.objects.equality import EQUAL, optSame
        for specimen in self.asList():
            if optSame(needle, specimen) is EQUAL:
                return True
        return False

    def get(self, index):
        if 0 <= index < self.size:
            return self.strategy.get(self.storage, index)
        else:
            raise userError(u"Index %d is out-of-bounds" % index)

    def put(self, index, value):
        top = self.size
        if 0 <= index < top:
            new = self.asList()
            new[index] = value
        elif index == top:
            new = self.asList() + [value]
        else:
            raise userError(u"Index %d out of bounds for list of length %d" %
                           (index, self.size))

        # Do the whole strategy thing.
        if self.strategy.admits(value):
            return ConstList(new, self.strategy)
        return ConstList.withoutStrategy(new)

    def slice(self, start, stop=-1):
        assert start >= 0
        if stop < 0:
            if self.strategy.slices:
                return ConstList(self.asList()[start:], self.strategy)
            return ConstList.withoutStrategy(self.asList()[start:])
        else:
            if self.strategy.slices:
                return ConstList(self.asList()[start:stop], self.strategy)
            return ConstList.withoutStrategy(self.asList()[start:stop])

    def snapshot(self):
        # XXX this could be made much more efficient.
        return ConstList(self.asList(), self.strategy)

    def reverse(self):
        # XXX this could be made more efficient? Dunno.
        new = self.asList()
        new.reverse()
        return ConstList(new, self.strategy)


def reduceList(o):
    from typhon.objects.refs import resolution
    l = resolution(o)
    if isinstance(l, ConstList):
        return l
    raise userError(u"Not a list!")


def unwrapList(o):
    return reduceList(o).asList()

def makeList(l):
    return ConstList.withoutStrategy(l)


class ListStrategy(object):
    """
    http://morepypy.blogspot.com/2011/10/more-compact-lists-with-list-strategies.html
    """

    multiplies = True
    slices = True


# I'm getting Haskell flashbacks here. In RPython, None is of type SomeNone,
# which isn't unifiable with SomeErased, the type of erased values.
eraseNone, uneraseNone = new_erasing_pair("none")
erasedNone = eraseNone(None)

class EmptyListStrategy(ListStrategy):

    @staticmethod
    def stash(l):
        return erasedNone

    @staticmethod
    def unstash(storage):
        return []

    @staticmethod
    def get(storage, index):
        raise IndexError(index)

    @staticmethod
    def admits(obj):
        return False

    @staticmethod
    def add(storage, other):
        # Cheating: forall x. [] + x <=> x
        return other


eraseGeneric, uneraseGeneric = new_erasing_pair("generic")

class GenericListStrategy(ListStrategy):
    """
    The fallback strategy. Stores a list of Objects.
    """

    @staticmethod
    def stash(l):
        return eraseGeneric(l)

    @staticmethod
    def unstash(storage):
        return uneraseGeneric(storage)

    @staticmethod
    def get(storage, index):
        return uneraseGeneric(storage)[index]

    @staticmethod
    def admits(obj):
        return True

    @staticmethod
    def add(storage, other):
        return ConstList(uneraseGeneric(storage) + other.asList(),
                         GenericListStrategy)


erasePair, unerasePair = new_erasing_pair("tuple")

class PairListStrategy(ListStrategy):
    """
    Stores two Objects as a tuple.
    """

    multiplies = False
    slices = False

    @staticmethod
    def stash(l):
        return erasePair((l[0], l[1]))

    @staticmethod
    def unstash(storage):
        x, y = unerasePair(storage)
        return [x, y]

    @staticmethod
    def get(storage, index):
        x, y = unerasePair(storage)
        if index == 0:
            return x
        elif index == 1:
            return y
        raise IndexError(index)

    @staticmethod
    def admits(obj):
        return False

    @staticmethod
    def add(storage, other):
        return ConstList(uneraseGeneric(storage) + other.asList(),
                         GenericListStrategy)


eraseInt, uneraseInt = new_erasing_pair("int")

class IntListStrategy(ListStrategy):
    """
    Stores a list of Ints as unboxed ints.
    """

    @staticmethod
    def stash(l):
        from typhon.objects.data import unwrapInt
        return eraseInt([unwrapInt(i) for i in l])

    @staticmethod
    def unstash(storage):
        from typhon.objects.data import IntObject
        return [IntObject(i) for i in uneraseInt(storage)]

    @staticmethod
    def get(storage, index):
        from typhon.objects.data import IntObject
        return IntObject(uneraseInt(storage)[index])

    @staticmethod
    def admits(obj):
        from typhon.objects.data import IntObject
        return isinstance(obj, IntObject)

    @staticmethod
    def add(storage, other):
        unerased = uneraseInt(storage)
        if other.strategy is IntListStrategy:
            return ConstList.ints(uneraseInt(storage) +
                                  uneraseInt(other.storage))
        return ConstList(IntListStrategy.unstash(storage) + other.asList(),
                         GenericListStrategy)
