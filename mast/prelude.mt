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
object _comparer as DeepFrozenStamp:
    "A comparison helper.

     This object implements the comparison operators."

    to asBigAs(left, right):
        "The operator `left` <=> `right`.
        
         Whether `left` and `right` have the same magnitude; to be precise,
         this method returns whether `left` ≤ `right` ∧ `right` ≤ `left`."
        return left.op__cmp(right).isZero()

    to geq(left, right):
        "The operator `left` >= `right`.
        
         Whether `left` ≥ `right`."
        return left.op__cmp(right).atLeastZero()

    to greaterThan(left, right):
        "The operator `left` > `right`.
        
         Whether `left` > `right`."
        return left.op__cmp(right).aboveZero()

    to leq(left, right):
        "The operator `left` <= `right`.
        
         Whether `left` ≤ `right`."
        return left.op__cmp(right).atMostZero()

    to lessThan(left, right):
        "The operator `left` < `right`.
        
         Whether `left` < `right`."
        return left.op__cmp(right).belowZero()


object Void as DeepFrozenStamp:
    "Nothingness.

     This guard admits only `null`."

    to coerce(specimen, ej):
        if (specimen != null):
            throw.eject(ej, "not null")
        return null


def makePredicateGuard(predicate :DeepFrozenStamp, label) as DeepFrozenStamp:
    # No Str guard yet, and we need to preserve DFness
    if (!isStr(label)):
        throw("Predicate guard label must be string")
    return object predicateGuard as DeepFrozenStamp:
        "A predicate guard.

         This guard admits any object which passes its predicate."

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
def Bytes := makePredicateGuard(isBytes, "Bytes")
def Char := makePredicateGuard(isChar, "Char")
def Double := makePredicateGuard(isDouble, "Double")
def Int := makePredicateGuard(isInt, "Int")
def Str := makePredicateGuard(isStr, "Str")


def Empty := makePredicateGuard(def pred(specimen) as DeepFrozenStamp {return specimen.size() == 0}, "Empty")
# Alias for map patterns.
def _mapEmpty := Empty


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
def _validateFor(flag :Bool) :Void as DeepFrozenStamp:
    "Ensure that `flag` is `true`.

     This object is a safeguard against malicious loop objects. A flag is set
     to `true` and closed over by a loop body; once the loop is finished, the
     flag is set to `false` and the loop cannot be reëntered."

    if (!flag):
        throw("Failed to validate loop!")

object _ListGuardStamp:
    to audit(audition):
        return true

object List as DeepFrozenStamp:
    "A guard which admits lists.

     Only immutable lists are admitted by this object. Mutable lists created
     with `diverge/0` will not be admitted; freeze them first with
     `snapshot/0`."

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
    "A guard which admits sets.

     Only immutable sets are admitted by this object. Mutable sets created
     with `diverge/0` will not be admitted; freeze them first with
     `snapshot/0`."

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

                var set := [].asSet()
                for element in specimen:
                    set with= (subGuard.coerce(element, ej))
                return set

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
    "A guard which admits maps.

     Only immutable maps are admitted by this object. Mutable maps created
     with `diverge/0` will not be admitted; freeze them first with
     `snapshot/0`."

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

            to getGuards():
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

    to extractGuards(specimen, ej):
        if (specimen == Map):
            return [Any, Any]
        else if (__auditedBy(_MapGuardStamp, specimen)):
            return specimen.getGuards()
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

object _NullOkStamp:
    to audit(audition):
        return true

object NullOk as DeepFrozenStamp:
    "A guard which admits `null`.

     When specialized, this object returns a guard which admits its subguard
     as well as `null`."

    to coerce(specimen, ej):
        if (specimen == null):
            return specimen

        def conformed := specimen._conformTo(NullOk)

        if (conformed == null):
            return conformed

        throw.eject(ej, ["Not null:", specimen])

    to get(subGuard):
        return object SubNullOk implements _NullOkStamp:
            to _printOn(out):
                out.print("NullOk[")
                out.print(subGuard)
                out.print("]")

            to coerce(specimen, ej):
                if (specimen == null):
                    return specimen
                return subGuard.coerce(specimen, ej)

            to getGuard():
                return subGuard

    to extractGuard(specimen, ej):
        if (specimen == NullOk):
            return Any
        else if (__auditedBy(_NullOkStamp, specimen)):
            return specimen.getGuard()
        else:
            throw.eject(ej, "Not a NullOk guard")


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


def _iterWhile(obj) as DeepFrozenStamp:
    return object iterWhile:
        to _makeIterator():
            return iterWhile
        to next(ej):
            def rv := obj()
            if (rv == false):
                throw.eject(ej, "End of iteration")
            return [null, rv]


def _splitList(position :Int) as DeepFrozenStamp:
    return def listSplitter(specimen, ej):
        if (specimen.size() < position):
            throw.eject(ej, ["List is too short:", specimen])
        return specimen.slice(0, position).with(specimen.slice(position))


def _accumulateList(iterable, mapper) as DeepFrozenStamp:
    def iterator := iterable._makeIterator()
    var rv := []

    escape ej:
        while (true):
            escape skip:
                def [key, value] := iterator.next(ej)
                def result := mapper(key, value, skip)
                rv := rv.with(result)

    return rv


def _matchSame(expected) as DeepFrozenStamp:
    "The pattern ==`expected`."
    return def sameMatcher(specimen, ej):
        if (expected != specimen):
            throw.eject(ej, ["Not the same:", expected, specimen])


def _mapExtract(key) as DeepFrozenStamp:
    return def mapExtractor(specimen, ej):
        if (specimen.contains(key)):
            return [specimen[key], specimen.without(key)]
        throw.eject(ej, "Key " + M.toQuote(specimen) + " not in map")


def _quasiMatcher(matchMaker, values) as DeepFrozenStamp:
    return def quasiMatcher(specimen, ej):
        return matchMaker.matchBind(values, specimen, ej)


object _suchThat as DeepFrozenStamp:
    "The pattern patt ? (expr)."
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


object _switchFailed as DeepFrozenStamp:
    match [=="run", args, _]:
        throw("Switch failed:", args)


object _makeVerbFacet as DeepFrozenStamp:
    "The operator `obj`.`method`."

    to curryCall(target, verb):
        "Curry a call to `target` using `verb`."

        return object curried:
            "A curried call.

             This object responds to messages with the verb \"run\" by passing
             them to another object with a different verb."
            to _uncall():
                return [_makeVerbFacet, "curryCall", [target, verb], [].asMap()]

            match [=="run", args, namedArgs]:
                M.call(target, verb, args, namedArgs)


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

        to sortKeys():
            return m.sortKeys()

        to sortValues():
            return m.sortValues()


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


object _makeMap as DeepFrozenStamp:
    to fromPairs(l):
        def m := _flexMap([].asMap())
        for [k, v] in l:
            m[k] := v
        return m.snapshot()


def _accumulateMap(iterable, mapper) as DeepFrozenStamp:
    def l := _accumulateList(iterable, mapper)
    return _makeMap.fromPairs(l)


def _bind(resolver, guard) as DeepFrozenStamp:
    def viaBinder(specimen, ej):
        if (guard == null):
            resolver.resolve(specimen)
            return specimen
        else:
            def coerced := guard.coerce(specimen, ej)
            resolver.resolve(coerced)
            return coerced
    return viaBinder


object _booleanFlow as DeepFrozenStamp:
    to broken():
        return Ref.broken("Boolean flow expression failed")

    to failureList(count :Int) :List:
        return [false] + [_booleanFlow.broken()] * count


def [=> SubrangeGuard, => DeepFrozen] := import.script(
    "prelude/deepfrozen",
    [=> _comparer, => _booleanFlow, => _makeVerbFacet,
     => _validateFor, => _bind,
     => DeepFrozenStamp, => TransparentStamp,
     => Bool, => Char, => Double, => Int, => Str, => Void,
     => List, => Map, => NullOk, => Same, => Set,
     ])


# New approach to importing the rest of the prelude: Collate the entirety of
# the module and boot scope into a single map which is then passed as-is to
# the other modules.
var preludeScope := [
    => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
    => Int, => List, => Map, => NullOk, => Same, => Set, => Str,
    => SubrangeGuard, => Void,
    => _mapEmpty, => _mapExtract,
    => _accumulateList, => _accumulateMap, => _booleanFlow, => _iterWhile,
    => _validateFor,
    => _switchFailed, => _makeVerbFacet, => _comparer, => _suchThat,
    => _matchSame, => _bind, => _quasiMatcher, => _splitList,
    => M, => import, => throw, => typhonEval,
]

# AST (needed for auditors).
preludeScope |= import.script("prelude/monte_ast",
                         preludeScope | [=> DeepFrozenStamp, => TransparentStamp,
                                         => KernelAstStamp])

# Simple QP.
preludeScope |= import.script("prelude/simple", preludeScope)

# Brands require simple QP.
preludeScope |= import.script("prelude/brand", preludeScope)

# Interfaces require simple QP.
preludeScope |= import.script("prelude/protocolDesc", preludeScope)

# Regions require simple QP.
def [
    => OrderedRegionMaker,
    => OrderedSpaceMaker
] := import.script("prelude/region", preludeScope)

# Spaces require regions. We're doing this import slightly differently since
# we want to replace some of our names with spaces; look at the order of
# operations.
preludeScope := import.script("prelude/space",
                       preludeScope | [=> OrderedRegionMaker,
                                       => OrderedSpaceMaker]) | preludeScope

# b__quasiParser desires spaces.
preludeScope |= import.script("prelude/b", preludeScope)

# The big kahuna: The Monte compiler and QL.
# Note: This isn't portable. The usage of typhonEval() ties us to Typhon. This
# doesn't *have* to be the case, but it's the case we currently want to deal
# with. Or, at least, this is what *I* want to deal with. The AST currently
# doesn't support evaluation, and I'd expect it to be slow, so we're not doing
# that. Instead, we're feeding dumped AST to Typhon via this magic boot scope
# hook, and that'll do for now. ~ C.
preludeScope |= import.script("prelude/m", preludeScope)

# Transparent auditor and guard.
# This has to do some significant AST groveling so it uses AST quasipatterns
# for convenience.
preludeScope |= import.script("prelude/transparent", preludeScope)

# The final scope exported from the prelude. This *must* be the final
# expression in the module!
preludeScope | [
    => _flexMap,
]
