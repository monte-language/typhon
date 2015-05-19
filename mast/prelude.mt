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

# Basic layout: Core guards, core expression syntax, core pattern syntax, and
# finally extra stuff like brands and simple QP.

# The comparer can come before guards, since it is extremely polymorphic and
# doesn't care much about the types of the values that it is manipulating.
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


def makePredicateGuard(predicate, label):
    return object predicateGuard:
        to _printOn(out):
            out.print(label)

        to coerce(specimen, ej):
            if (predicate(specimen)):
                return specimen

            def conformed := specimen._conformTo(predicateGuard)

            if (predicate(conformed)):
                return conformed

            def error := "Failed guard (" + label + "):"
            throw.eject(ej, [error, specimen])

        to makeSlot(value):
            return makeGuardedSlot(predicateGuard, value)

# Data guards. These must come before any while-expressions.
def Bool := makePredicateGuard(isBool, "Bool")
def Char := makePredicateGuard(isChar, "Char")
def Double := makePredicateGuard(isDouble, "Double")
def Int := makePredicateGuard(isInt, "Int")
def Str := makePredicateGuard(isStr, "Str")

# This is a hack. It is unabashedly, unashamedly, a hack. It is an essential
# hack, for now, but it is not permanent.
# The reference implementation uses "boolean" for the name of Bool when
# expanding while-expressions.
def boolean := Bool

def Empty := makePredicateGuard(fn specimen {specimen.size() == 0}, "Empty")
# Alias for map patterns.
def __mapEmpty := Empty


def testIntGuard(assert):
    assert.ejects(fn ej {def x :Int exit ej := 5.0})
    assert.doesNotEject(fn ej {def x :Int exit ej := 42})

def testEmptyGuard(assert):
    assert.ejects(fn ej {def x :Empty exit ej := [7]})
    assert.doesNotEject(fn ej {def x :Empty exit ej := []})

unittest([
    testIntGuard,
    testEmptyGuard,
])


# Must come before List. Must come after Void and Bool.
def __validateFor(flag :Bool) :Void:
    if (!flag):
        throw("Failed to validate loop!")


object List:
    to _printOn(out):
        out.print("List")

    to coerce(specimen, ej):
        if (isList(specimen)):
            return specimen

        def conformed := specimen._conformTo(List)

        if (isList(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a list:", specimen])

    to makeSlot(value):
        return makeGuardedSlot(List, value)

    to get(subGuard):
        return object SubList:
            to _printOn(out):
                out.print("List[")
                subGuard._printOn(out)
                out.print("]")

            to coerce(var specimen, ej):
                if (!isList(specimen)):
                    specimen := specimen._conformTo(SubList)

                if (isList(specimen)):
                    for element in specimen:
                        subGuard.coerce(element, ej)
                    return specimen

                throw.eject(ej,
                            ["(Probably) not a conforming list:", specimen])


object Set:
    to _printOn(out):
        out.print("Set")

    to coerce(specimen, ej):
        if (isSet(specimen)):
            return specimen

        def conformed := specimen._conformTo(Set)

        if (isSet(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a set:", specimen])

    to makeSlot(value):
        return makeGuardedSlot(Set, value)

    to get(subGuard):
        return object SubSet:
            to _printOn(out):
                out.print("Set[")
                subGuard._printOn(out)
                out.print("]")

            to coerce(var specimen, ej):
                if (!isSet(specimen)):
                    specimen := specimen._conformTo(SubSet)

                if (isSet(specimen)):
                    for element in specimen:
                        subGuard.coerce(element, ej)
                    return specimen

                throw.eject(ej,
                            ["(Probably) not a conforming list:", specimen])


object Map:
    to _printOn(out):
        out.print("Map")

    to coerce(specimen, ej):
        if (isMap(specimen)):
            return specimen

        def conformed := specimen._conformTo(Map)

        if (isMap(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a map:", specimen])

    to makeSlot(value):
        return makeGuardedSlot(Map, value)

    to get(keyGuard, valueGuard):
        return object SubMap:
            to _printOn(out):
                out.print("Map[")
                keyGuard._printOn(out)
                out.print(", ")
                valueGuard._printOn(out)
                out.print("]")

            to coerce(var specimen, ej):
                if (!isMap(specimen)):
                    specimen := specimen._conformTo(SubMap)

                if (isMap(specimen)):
                    for key => value in specimen:
                        keyGuard.coerce(key, ej)
                        valueGuard.coerce(value, ej)
                    return specimen

                throw.eject(ej,
                            ["(Probably) not a conforming map:", specimen])


def testMapGuard(assert):
    assert.ejects(fn ej {def x :Map exit ej := 42})
    assert.doesNotEject(fn ej {def x :Map exit ej := [].asMap()})

def testMapGuardIntStr(assert):
    assert.ejects(fn ej {def x :Map[Int, Str] exit ej := ["lue" => 42]})
    assert.doesNotEject(fn ej {def x :Map[Int, Str] exit ej := [42 => "lue"]})

unittest([
    testMapGuard,
    testMapGuardIntStr,
])


object NullOk:
    to coerce(specimen, ej):
        if (specimen == null):
            return specimen

        def conformed := specimen._conformTo(NullOk)

        if (conformed == null):
            return conformed

        throw.eject(ej, ["Not null:", specimen])

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


object Same:
    to get(value):
        return object SameGuard:
            to _printOn(out):
                out.print("Same[")
                value._printOn(out)
                out.print("]")

            to coerce(specimen, ej):
                if (!__equalizer.sameYet(value, specimen)):
                    throw.eject(ej, [specimen, "is not", value])
                return specimen

            to makeSlot(v):
                return makeGuardedSlot(SameGuard, v)

def testSame(assert):
    object o:
        pass
    object p:
        pass
    assert.ejects(fn ej {def x :Same[o] exit ej := p})
    assert.doesNotEject(fn ej {def x :Same[o] exit ej := o})

unittest([testSame])


def __iterWhile(obj):
    return object iterWhile:
        to _makeIterator():
            return iterWhile
        to next(ej):
            def rv := obj()
            if (rv == false):
                throw.eject(ej, "End of iteration")
            return [null, rv]


def __splitList(position :Int):
    # XXX could use `return fn ...`
    def listSplitter(specimen, ej):
        if (specimen.size() < position):
            throw.eject(ej, ["List is too short:", specimen])
        return specimen.slice(0, position).with(specimen.slice(position))
    return listSplitter


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


object Any:
    to _printOn(out):
        out.print("Any")

    to coerce(specimen, _):
        return specimen

    to makeSlot(value):
        return makeGuardedSlot(Any, value)

    match [=="get", subGuards ? (subGuards.size() != 0)]:
        object subAny:
            to _printOn(out):
                out.print("Any[")
                def [head] + tail := subGuards
                head._printOn(out)
                for subGuard in tail:
                    out.print(", ")
                    subGuard._printOn(out)
                out.print("]")

            to coerce(specimen, ej):
                for subGuard in subGuards:
                    escape subEj:
                        return subGuard.coerce(specimen, subEj)
                    catch _:
                        continue
                throw.eject(ej, "Specimen didn't match any subguard")

            to makeSlot(value):
                return makeGuardedSlot(subAny, value)

def testAnySubGuard(assert):
    assert.ejects(fn ej {def x :Any[Int, Char] exit ej := "test"})
    assert.doesNotEject(fn ej {def x :Any[Int, Char] exit ej := 42})
    assert.doesNotEject(fn ej {def x :Any[Int, Char] exit ej := 'x'})

unittest([testAnySubGuard])


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


def __bind(resolver, guard):
    def viaBinder(specimen, ej):
        if (guard == null):
            resolver.resolve(specimen)
        else:
            resolver.resolve(guard.coerce(specimen, ej))
    return viaBinder


def __makeParamDesc(name, guard):
    return object paramDesc:
        pass


def __makeMessageDesc(unknown, name, params, guard):
    return object messageDesc:
        pass


object __makeProtocolDesc:
    to run(unknown, name, alsoUnknown, stillUnknown, messages):
        return object protocolDesc:
            pass

    to makePair():
        pass


object __booleanFlow:
    to broken():
        return Ref.broken("Boolean flow expression failed")

    to failureList(count :Int) :List:
        return [false] + [__booleanFlow.broken()] * count


# Simple QP needs patterns, some loops, some other syntax, and a few guards.
def [=> simple__quasiParser] := import("prelude/simple", ["boolean" => Bool,
                                                          => Bool, => Str,
                                                          => __comparer,
                                                          => __iterWhile,
                                                          => __matchSame,
                                                          => __quasiMatcher,
                                                          => __suchThat,
                                                          => __validateFor])


# Brands need a bunch of guards and also the simple QP.
def [=> makeBrandPair] := import("prelude/brand", [=> NullOk, => Str, => Void,
                                                   => simple__quasiParser])

# Regions need some guards. And simple QP. And a bunch of other stuff.
def [
    => OrderedRegionMaker,
    => OrderedSpaceMaker
] := import("prelude/region", [=> Bool, => Double, => Int, => List, => NullOk,
                               => Same, => Str, => __accumulateList,
                               => __booleanFlow, => __comparer,
                               => __iterWhile, => __validateFor,
                               => simple__quasiParser,
                               "boolean" => Bool])

# Spaces need some guards, and also regions.
def [
    "Char" => SpaceChar,
    "Double" => SpaceDouble,
    "Int" => SpaceInt,
    => __makeOrderedSpace
] := import("prelude/space", [=> Char, => Double, => Int,
                              => OrderedRegionMaker, => OrderedSpaceMaker,
                              => __comparer])


[
    # Needed for interface expansions with ref Monte. :T
    "any" => Any,
    "void" => Void,
    "DeepFrozen" => Any,
    # This is 100% hack. See the matching comment near the top of the prelude.
    "boolean" => Bool,

    "__mapEmpty" => Empty,
    => Any,
    => Bool,
    "Char" => SpaceChar,
    "Double" => SpaceDouble,
    => Empty,
    "Int" => SpaceInt,
    => List,
    => Map,
    => NullOk,
    => Same,
    => Set,
    => Str,
    => Void,
    => __accumulateList,
    => __accumulateMap,
    => __bind,
    => __booleanFlow,
    => __comparer,
    => __iterWhile,
    => __makeMap,
    => __makeMessageDesc,
    => __makeOrderedSpace,
    => __makeParamDesc,
    => __makeProtocolDesc,
    => __makeVerbFacet,
    => __mapExtract,
    => __matchSame,
    => __quasiMatcher,
    => __splitList,
    => __suchThat,
    => __switchFailed,
    => __validateFor,
    => _flexMap,
    => makeBrandPair,
    => simple__quasiParser,
]
