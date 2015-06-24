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
object __comparer as DeepFrozenStamp:
    to asBigAs(left, right):
        return left.op__cmp(right).isZero()

    to geq(left, right):
        return left.op__cmp(right).atLeastZero()

    to greaterThan(left, right):
        return left.op__cmp(right).aboveZero()

    to leq(left, right):
        return left.op__cmp(right).atMostZero()

    to lessThan(left, right):
        return left.op__cmp(right).belowZero()


object Void as DeepFrozenStamp:
    to coerce(specimen, ej):
        if (specimen != null):
            throw.eject(ej, "not null")
        return null


def makePredicateGuard(predicate :DeepFrozenStamp, label) as DeepFrozenStamp:
    # No Str guard yet, and we need to preserve DFness
    if (!isStr(label)):
        throw("Predicate guard label must be string")
    return object predicateGuard as DeepFrozenStamp:
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


# Data guards. These must come before any while-expressions.
def Bool := makePredicateGuard(isBool, "Bool")
def Char := makePredicateGuard(isChar, "Char")
def Double := makePredicateGuard(isDouble, "Double")
def Int := makePredicateGuard(isInt, "Int")
def Str := makePredicateGuard(isStr, "Str")


def Empty := makePredicateGuard(def pred(specimen) as DeepFrozenStamp {return specimen.size() == 0}, "Empty")
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

object _ListGuardStamp:
    to audit(audition):
        return true

object List as DeepFrozenStamp:
    to _printOn(out):
        out.print("List")

    to coerce(specimen, ej):
        if (isList(specimen)):
            return specimen

        def conformed := specimen._conformTo(List)

        if (isList(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a list:", specimen])

    to get(subGuard):
        # XXX make this transparent
        return object SubList implements _ListGuardStamp:
            to _printOn(out):
                out.print("List[")
                subGuard._printOn(out)
                out.print("]")

            to getGuard():
                return subGuard

            to coerce(var specimen, ej):
                if (!isList(specimen)):
                    specimen := specimen._conformTo(SubList)

                if (isList(specimen)):
                    for element in specimen:
                        subGuard.coerce(element, ej)
                    return specimen

                throw.eject(ej,
                            ["(Probably) not a conforming list:", specimen])

    to extractGuard(specimen, ej):
        if (specimen == List):
            return Any
        else if (__auditedBy(_ListGuardStamp, specimen)):
            return specimen.getGuard()
        else:
            throw.eject(ej, "Not a List guard")

object _SetGuardStamp:
    to audit(audition):
        return true

object Set as DeepFrozenStamp:
    to _printOn(out):
        out.print("Set")

    to coerce(specimen, ej):
        if (isSet(specimen)):
            return specimen

        def conformed := specimen._conformTo(Set)

        if (isSet(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a set:", specimen])

    to get(subGuard):
        # XXX make this transparent
        return object SubSet implements _SetGuardStamp:
            to _printOn(out):
                out.print("Set[")
                subGuard._printOn(out)
                out.print("]")

            to getGuard():
                return subGuard

            to coerce(var specimen, ej):
                if (!isSet(specimen)):
                    specimen := specimen._conformTo(SubSet)

                if (isSet(specimen)):
                    for element in specimen:
                        subGuard.coerce(element, ej)
                    return specimen

                throw.eject(ej,
                            ["(Probably) not a conforming set:", specimen])

    to extractGuard(specimen, ej):
        if (specimen == Set):
            return Any
        else if (__auditedBy(_SetGuardStamp, specimen)):
            return specimen.getGuard()
        else:
            throw.eject(ej, "Not a Set guard")

object _MapGuardStamp:
    to audit(audition):
        return true

object Map as DeepFrozenStamp:
    to _printOn(out):
        out.print("Map")

    to coerce(specimen, ej):
        if (isMap(specimen)):
            return specimen

        def conformed := specimen._conformTo(Map)

        if (isMap(conformed)):
            return conformed

        throw.eject(ej, ["(Probably) not a map:", specimen])

    to get(keyGuard, valueGuard):
        #XXX Make this transparent
        return object SubMap implements _MapGuardStamp:
            to _printOn(out):
                out.print("Map[")
                keyGuard._printOn(out)
                out.print(", ")
                valueGuard._printOn(out)
                out.print("]")

            to getGuard():
                return [keyGuard, valueGuard]
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

    to extractGuard(specimen, ej):
        if (specimen == Map):
            return Any
        else if (__auditedBy(_MapGuardStamp, specimen)):
            return specimen.getGuard()
        else:
            throw.eject(ej, "Not a Map guard")

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


object NullOk as DeepFrozenStamp:
    to coerce(specimen, ej):
        if (specimen == null):
            return specimen

        def conformed := specimen._conformTo(NullOk)

        if (conformed == null):
            return conformed

        throw.eject(ej, ["Not null:", specimen])

    to get(subGuard):
        return object SubNullOk:
            to _printOn(out):
                out.print("NullOk[")
                out.print(subGuard)
                out.print("]")

            to coerce(specimen, ej):
                if (specimen == null):
                    return specimen
                return subGuard.coerce(specimen, ej)


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

object _SameGuardStamp:
    to audit(audition):
        return true

object Same as DeepFrozenStamp:
    to _printOn(out):
        out.print("Same")

    to get(value):
        #XXX make this transparent
        return object SameGuard implements _SameGuardStamp:
            to _printOn(out):
                out.print("Same[")
                value._printOn(out)
                out.print("]")

            to coerce(specimen, ej):
                if (!__equalizer.sameYet(value, specimen)):
                    throw.eject(ej, [specimen, "is not", value])
                return specimen

            to getValue():
                return value

    to extractValue(specimen, ej):
        if (__auditedBy(_SameGuardStamp, specimen)):
            return specimen.getValue()
        else:
            throw.eject(ej, "Not a Same guard")


def testSame(assert):
    object o:
        pass
    object p:
        pass
    assert.ejects(fn ej {def x :Same[o] exit ej := p})
    assert.doesNotEject(fn ej {def x :Same[o] exit ej := o})
    assert.equal(Same[o].getValue(), o)

unittest([testSame])


def __iterWhile(obj) as DeepFrozenStamp:
    return object iterWhile:
        to _makeIterator():
            return iterWhile
        to next(ej):
            def rv := obj()
            if (rv == false):
                throw.eject(ej, "End of iteration")
            return [null, rv]


def __splitList(position :Int) as DeepFrozenStamp:
    # XXX could use `return fn ...`
    def listSplitter(specimen, ej):
        if (specimen.size() < position):
            throw.eject(ej, ["List is too short:", specimen])
        return specimen.slice(0, position).with(specimen.slice(position))
    return listSplitter


def __accumulateList(iterable, mapper) as DeepFrozenStamp:
    def iterator := iterable._makeIterator()
    var rv := []

    escape ej:
        while (true):
            escape skip:
                def [key, value] := iterator.next(ej)
                def result := mapper(key, value, skip)
                rv := rv.with(result)

    return rv


def __matchSame(expected) as DeepFrozenStamp:
    # XXX could use `return fn ...`
    def sameMatcher(specimen, ej):
        if (expected != specimen):
            throw.eject(ej, ["Not the same:", expected, specimen])
    return sameMatcher


def __mapExtract(key) as DeepFrozenStamp:
    def mapExtractor(specimen, ej):
        if (specimen.contains(key)):
            return [specimen[key], specimen.without(key)]
        throw.eject(ej, "Key " + M.toQuote(specimen) + " not in map")
    return mapExtractor


def __quasiMatcher(matchMaker, values) as DeepFrozenStamp:
    def quasiMatcher(specimen, ej):
        return matchMaker.matchBind(values, specimen, ej)
    return quasiMatcher


object __suchThat as DeepFrozenStamp:
    to run(specimen :Bool):
        def suchThat(_, ej):
            if (!specimen):
                throw.eject(ej, "suchThat failed")
        return suchThat

    to run(specimen, _):
        return [specimen, null]


def testSuchThatTrue(assert):
    def f(ej):
        def x ? (true) exit ej := 42
        assert.equal(x, 42)
    assert.doesNotEject(f)

def testSuchThatFalse(assert):
    assert.ejects(fn ej {def x ? (false) exit ej := 42})

unittest([
    testSuchThatTrue,
    testSuchThatFalse,
])


def testAnySubGuard(assert):
    assert.ejects(fn ej {def x :Any[Int, Char] exit ej := "test"})
    assert.doesNotEject(fn ej {def x :Any[Int, Char] exit ej := 42})
    assert.doesNotEject(fn ej {def x :Any[Int, Char] exit ej := 'x'})

unittest([testAnySubGuard])


object __switchFailed as DeepFrozenStamp:
    match [=="run", args]:
        throw("Switch failed:", args)


object __makeVerbFacet as DeepFrozenStamp:
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


object __makeMap as DeepFrozenStamp:
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
            return specimen
        else:
            def coerced := guard.coerce(specimen, ej)
            resolver.resolve(coerced)
            return coerced
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
        null


object __booleanFlow:
    to broken():
        return Ref.broken("Boolean flow expression failed")

    to failureList(count :Int) :List:
        return [false] + [__booleanFlow.broken()] * count

object DeepFrozen:
    to audit(audition):
        return true
    to coerce(specimen, ej):
        return specimen

object SubrangeGuard:
    to get(superguard):
        return object SpecializedSubrangeGuard:
            to audit(audition):
                return true
            to coerce(specimen, ej):
                return specimen


# New approach to importing the rest of the prelude: Collate the entirety of
# the module and boot scope into a single map which is then passed as-is to
# the other modules.
var preludeScope := [
    => Any, => Bool, => Char, => DeepFrozen, => Double, => Empty, => Int,
    => List, => Map, => NullOk, => Same, => Set, => Str, => SubrangeGuard,
    => Void,
    => __mapEmpty, => __mapExtract,
    => __accumulateList, => __booleanFlow, => __iterWhile, => __validateFor,
    => __switchFailed, => __makeVerbFacet, => __comparer,
    => __suchThat, => __matchSame, => __bind, => __quasiMatcher,
    => __splitList,
    => M, => import, => throw, => typhonEval,
]

# AST (needed for auditors).
def astBuilder := import("prelude/monte_ast",
                         preludeScope.with("DeepFrozenStamp", DeepFrozenStamp))
_installASTBuilder(astBuilder)

# Simple QP.
preludeScope |= import("prelude/simple", preludeScope)

# Brands require simple QP.
preludeScope |= import("prelude/brand", preludeScope)

# Regions require simple QP.
def [
    => OrderedRegionMaker,
    => OrderedSpaceMaker
] := import("prelude/region", preludeScope)

# Spaces require regions.
preludeScope |= import("prelude/space",
                       preludeScope | [=> OrderedRegionMaker,
                                       => OrderedSpaceMaker])

# Terms require simple QP and spaces.
preludeScope |= import("lib/monte/termParser", preludeScope)

# Finally, the big kahuna: The Monte compiler and QL.
# Note: This isn't portable. The usage of typhonEval() ties us to Typhon. This
# doesn't *have* to be the case, but it's the case we currently want to deal
# with. Or, at least, this is what *I* want to deal with. The AST currently
# doesn't support evaluation, and I'd expect it to be slow, so we're not doing
# that. Instead, we're feeding dumped AST to Typhon via this magic boot scope
# hook, and that'll do for now. ~ C.
preludeScope |= import("prelude/m", preludeScope)

# The final scope exported from the prelude. This *must* be the final
# expression in the module!
preludeScope | [
    "void" => Void,
    "__mapEmpty" => Empty,
    => __accumulateMap,
    => __makeMessageDesc,
    => __makeParamDesc,
    => __makeProtocolDesc,
    => _flexMap,
]
