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

# This is a hack. It is unabashedly, unashamedly, a hack. It is an essential
# hack, for now, but it is not permanent.
# The reference implementation uses "boolean" for the name of Bool when
# expanding while-expressions.
def boolean := Bool

object __comparer:
    to asBigAs(left, right):
        try:
            return left.op__cmp(right).isZero()
        catch _:
            return right.op__cmp(left).isZero()
    to geq(left, right):
        try:
            return left.op__cmp(right).atLeastZero()
        catch _:
            return right.op__cmp(left).atMostZero()
    to greaterThan(left, right):
        try:
            return left.op__cmp(right).aboveZero()
        catch _:
            return right.op__cmp(left).belowZero()
    to leq(left, right):
        try:
            return left.op__cmp(right).atMostZero()
        catch _:
            return right.op__cmp(left).atLeastZero()
    to lessThan(left, right):
        try:
            return left.op__cmp(right).belowZero()
        catch _:
            return right.op__cmp(left).aboveZero()


def __iterWhile(obj):
    return object iterWhile:
        to _makeIterator():
            return iterWhile
        to next(ej):
            def rv := obj()
            if (rv == false):
                throw.eject(ej, "End of iteration")
            return [null, rv]


def __accumulateList(iterable, mapper):
    def iterator := iterable._makeIterator()
    var rv := []

    escape ej:
        while (true):
            escape skip:
                def [key, value] := iterator.next(ej)
                def result := mapper(key, value, skip)
                rv := rv.with(result)

    return rv


object __makeOrderedSpace:
    to op__thru(var start, stop):
        var l := []
        while (start <= stop):
            l := l.with(start)
            start := start.next()
        return l

    to op__till(start, stop):
        return __makeOrderedSpace.op__thru(start, stop.previous())


def _listIterator(list):
    var index := 0
    return object iterator:
        to next(ej):
            if (list.size() > index):
                def rv := [index, list[index]]
                index += 1
                return rv
            else:
                throw.eject(ej, "Iterator exhausted")


def __splitList(position :Int):
    # XXX could use `return fn ...`
    # We use the List guard from the implementation rather than the one that
    # will be defined shortly, in order to avoid indefinite recursion on the
    # definition of listiness.
    def listSplitter(specimen, ej):
        if (specimen.size() < position):
            throw.eject(ej, ["List is too short:", specimen])
        return specimen.slice(0, position).with(specimen.slice(position))
    return listSplitter


def makeGuardedSlot(guard, var value :guard):
    return object guardedSlot:
        to get():
            return value
        to put(v):
            value := v


object Void:
    to coerce(_, _):
        return null

    to makeSlot(value):
        return makeGuardedSlot(Void, value)


def testVoid(assert):
    var x :Void := 42
    assert.equal(x, null)
    x := 'o'
    assert.equal(x, null)

unittest([
    testVoid,
])


# Must come before List.
def __validateFor(flag :Bool) :Void:
    if (!flag):
        throw("Failed to validate loop!")


object Any:
    to coerce(specimen, _):
        return specimen

    to makeSlot(value):
        return makeGuardedSlot(Any, value)


object NullOk:
    to coerce(specimen, ej):
        if (specimen != null):
            throw.eject(ej, ["Not null:", specimen])
        return specimen

    to get(subGuard):
        return object SubNullOk:
            to coerce(specimen, ej):
                if (specimen == null):
                    return specimen
                return subGuard.coerce(specimen, ej)

            to makeSlot(value):
                return makeGuardedSlot(SubNullOk, value)

    to makeSlot(value):
        return makeGuardedSlot(NullOk, value)


def testNullOkUnsubbed(assert):
    assert.ejects(fn ej {def x :NullOk exit ej := 42})
    assert.doesNotEject(fn ej {def x :NullOk exit ej := null})

def testNullOkInt(assert):
    assert.ejects(fn ej {def x :NullOk[Int] exit ej := "42"})
    assert.doesNotEject(fn ej {def x :NullOk[Int] exit ej := 42})
    assert.doesNotEject(fn ej {def x :NullOk[Int] exit ej := null})

unittest([
    testNullOkUnsubbed,
    testNullOkInt,
])


object Empty:
    to coerce(specimen, ej):
        if (specimen.size() != 0):
            throw.eject(ej, ["Not empty:", specimen])
        return specimen

    to makeSlot(value):
        return makeGuardedSlot(Empty, value)


object BetterList:
    to coerce(specimen, ej):
        if (specimen !~ [] + _):
            throw.eject(ej, ["Not a list:", specimen])
        return specimen

    to makeSlot(value):
        return makeGuardedSlot(BetterList, value)

    to get(subguard):
        return object SubList:
            to coerce(specimen, ej):
                def [] + l exit ej := specimen
                for element in l:
                    subguard.coerce(element, ej)
                return specimen

            to makeSlot(value):
                return makeGuardedSlot(SubList, value)


object BetterSet:
    to coerce(specimen, ej):
        return Set.coerce(specimen, ej)

    to makeSlot(value):
        return makeGuardedSlot(BetterSet, value)

    to get(subguard):
        return object SubSet:
            to coerce(specimen, ej):
                def set := Set.coerce(specimen, ej)
                for element in set:
                    subguard.coerce(element, ej)
                return specimen

            to makeSlot(value):
                return makeGuardedSlot(SubSet, value)


def __matchSame(expected):
    # XXX could use `return fn ...`
    def sameMatcher(specimen, ej):
        if (expected != specimen):
            throw.eject(ej, ["Not the same:", expected, specimen])
    return sameMatcher


def __mapExtract(key):
    def mapExtractor(specimen, ej):
        # XXX use the ejector if key is not in specimen
        return [specimen[key], specimen.without(key)]
    return mapExtractor


def __quasiMatcher(matchMaker, values):
    def quasiMatcher(specimen, ej):
        return matchMaker.matchBind(values, specimen, ej)
    return quasiMatcher


object __suchThat:
    to run(specimen :Bool):
        def suchThat(_, ej):
            if (!specimen):
                throw.eject(ej, "suchThat failed")
        return suchThat

    to run(specimen, _):
        return [specimen, null]


def testSuchThatTrue(assert):
    def f(ej):
        def x ? true exit ej := 42
        assert.equal(x, 42)
    assert.doesNotEject(f)

def testSuchThatFalse(assert):
    assert.ejects(fn ej {def x ? false exit ej := 42})

unittest([
    testSuchThatTrue,
    testSuchThatFalse,
])


object __switchFailed:
    match [=="run", args]:
        throw("Switch failed:", args)


object __makeVerbFacet:
    to curryCall(target, verb):
        return object curried:
            match [=="run", args]:
                M.call(target, verb, args)


def _flexMap(var m):
    return object flexMap:
        to _makeIterator():
            return m._makeIterator()

        to _printOn(out):
            out.print(M.toString(m))
            out.print(".diverge()")

        to asSet() :Set:
            return m.asSet()

        to contains(k) :Bool:
            return m.contains(k)

        to diverge():
            return _flexMap(m)

        to fetch(k, thunk):
            return m.fetch(k, thunk)

        to get(k):
            return m.get(k)

        to or(other):
            return _flexMap(m | other)

        to put(k, v):
            m := m.with(k, v)

        to removeKey(k):
            m := m.without(k)

        to size():
            return m.size()

        to slice(start):
            return flexMap.slice(start, flexMap.size())

        # XXX need to guard non-negative
        to slice(start, stop):
            return _flexMap(m.slice(start, stop))

        to snapshot():
            return m


def testFlexMapPrinting(assert):
    assert.equal(M.toString(_flexMap([].asMap())), "[].asMap().diverge()")
    assert.equal(M.toString(_flexMap([5 => 42])), "[5 => 42].diverge()")

def testFlexMapRemoveKey(assert):
    def m := _flexMap([1 => 2])
    m.removeKey(1)
    assert.equal(m.contains(1), false)


unittest([
    testFlexMapPrinting,
    testFlexMapRemoveKey,
])


object __makeMap:
    to fromPairs(l):
        def m := _flexMap([].asMap())
        for [k, v] in l:
            m[k] := v
        return m.snapshot()


def __accumulateMap(iterable, mapper):
    def l := __accumulateList(iterable, mapper)
    return __makeMap.fromPairs(l)


[
    # This is 100% hack. See the matching comment near the top of the prelude.
    "boolean" => Bool,

    "List" => BetterList,
    "Set" => BetterSet,
    "__mapEmpty" => Empty,
    => Any,
    => NullOk,
    => Void,
    => __accumulateList,
    => __accumulateMap,
    => __comparer,
    => __iterWhile,
    => __makeMap,
    => __makeOrderedSpace,
    => __makeVerbFacet,
    => __mapExtract,
    => __matchSame,
    => __quasiMatcher,
    => __splitList,
    => __suchThat,
    => __switchFailed,
    => __validateFor,
    => _flexMap,
    => _listIterator,
]
