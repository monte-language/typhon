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

     This object implements the various comparison operators."

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


def makePredicateGuard(predicate :DeepFrozenStamp, label :Str) as DeepFrozenStamp:
    return object predicateGuard as DeepFrozenStamp:
        "An unretractable predicate guard.

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
        return object SubList as DeepFrozenStamp implements _ListGuardStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("List[")
                subGuard._printOn(out)
                out.print("]")

            to _uncall():
                return [List, "get", [subGuard], [].asMap()]

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
        else if (_auditedBy(_ListGuardStamp, specimen)):
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
        return object SubSet implements _SetGuardStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("Set[")
                subGuard._printOn(out)
                out.print("]")

            to _uncall():
                return [Set, "get", [subGuard], [].asMap()]

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
        else if (_auditedBy(_SetGuardStamp, specimen)):
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
        return object SubMap implements _MapGuardStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("Map[")
                keyGuard._printOn(out)
                out.print(", ")
                valueGuard._printOn(out)
                out.print("]")

            to _uncall():
                return [Map, "get", [keyGuard, valueGuard], [].asMap()]

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
        else if (_auditedBy(_MapGuardStamp, specimen)):
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
        return object SubNullOk implements _NullOkStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("NullOk[")
                out.print(subGuard)
                out.print("]")

            to _uncall():
                return [NullOk, "get", [subGuard], [].asMap()]

            to coerce(specimen, ej):
                if (specimen == null):
                    return specimen
                return subGuard.coerce(specimen, ej)

            to getGuard():
                return subGuard

    to extractGuard(specimen, ej):
        if (specimen == NullOk):
            return Any
        else if (_auditedBy(_NullOkStamp, specimen)):
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

object _PairGuardStamp:
    to audit(audition):
        return true

object Pair as DeepFrozenStamp:
    "A guard which admits immutable pairs.
    
     Pairs are merely lists of size two."

    to _printOn(out):
        out.print("Pair")

    to coerce(specimen, ej):
        if (isList(specimen) && specimen.size() == 2):
            return specimen

        def conformed := specimen._conformTo(Map)

        if (isList(conformed) && conformed.size() == 2):
            return conformed

        throw.eject(ej, ["(Probably) not a pair:", specimen])

    to get(firstGuard, secondGuard):
        return object SubPair implements _PairGuardStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("Pair[")
                firstGuard._printOn(out)
                out.print(", ")
                secondGuard._printOn(out)
                out.print("]")

            to _uncall():
                return [Pair, "get", [firstGuard, secondGuard], [].asMap()]

            to getGuards():
                return [firstGuard, secondGuard]

            to coerce(var specimen, ej):
                if (!isList(specimen) || specimen.size() != 2):
                    specimen := specimen._conformTo(SubPair)

                def [first :firstGuard, second :secondGuard] exit ej := specimen
                return specimen

    to extractGuards(specimen, ej):
        if (specimen == Pair):
            return [Any, Any]
        else if (_auditedBy(_PairGuardStamp, specimen)):
            return specimen.getGuards()
        else:
            throw.eject(ej, "Not a Pair guard")

def testPairGuard(assert):
    assert.ejects(fn ej {def x :Pair exit ej := 42})
    assert.doesNotEject(fn ej {def x :Pair exit ej := [6, 9]})

def testPairGuardIntStr(assert):
    assert.ejects(fn ej {def x :Pair[Int, Str] exit ej := ["lue", 42]})
    assert.doesNotEject(fn ej {def x :Pair[Int, Str] exit ej := [42, "lue"]})

unittest([
    testPairGuard,
    testPairGuardIntStr,
])

# object _SameGuardStamp:
#     to audit(audition):
#         return true

# object Same as DeepFrozenStamp:
#     to _printOn(out):
#         out.print("Same")

#     to get(value):
#         return object SameGuard implements _SameGuardStamp, Selfless, TransparentStamp:
#             to _printOn(out):
#                 out.print("Same[")
#                 value._printOn(out)
#                 out.print("]")

#             to _uncall():
#                 return [Same, "get", [value], [].asMap()]

#             to coerce(specimen, ej):
#                 if (!_equalizer.sameYet(value, specimen)):
#                     throw.eject(ej, [specimen, "is not", value])
#                 return specimen

#             to getValue():
#                 return value

#     to extractValue(specimen, ej):
#         if (_auditedBy(_SameGuardStamp, specimen)):
#             return specimen.getValue()
#         else:
#             throw.eject(ej, "Not a Same guard")


def testSame(assert):
    object o:
        pass
    object p:
        pass
    assert.ejects(fn ej {def x :Same[o] exit ej := p})
    assert.doesNotEject(fn ej {def x :Same[o] exit ej := o})
    assert.equal(Same[o].getValue(), o)

unittest([testSame])


object _iterForever as DeepFrozenStamp:
    "Implementation of while-expression syntax."

    to _makeIterator():
        return _iterForever
    to next(ej):
        return [null, null]


def _splitList(position :Int) as DeepFrozenStamp:
    "Implementation of tail pattern-matching syntax in list patterns.
    
     m`def [x] + xs := l`.expand() ==
     m`def via (_splitList.run(1)) [x, xs] := l`"

    return def listSplitter(specimen, ej):
        if (specimen.size() < position):
            throw.eject(ej, ["List is too short:", specimen])
        return specimen.slice(0, position).with(specimen.slice(position))


def _accumulateList(iterable, mapper) as DeepFrozenStamp:
    "Implementation of list comprehension syntax."

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


object _mapExtract as DeepFrozenStamp:
    "Implementation of key pattern-matching syntax in map patterns."

    to run(key):
        return def mapExtractor(specimen, ej):
            if (specimen.contains(key)):
                return [specimen[key], specimen.without(key)]
            throw.eject(ej, "Key " + M.toQuote(key) + " not in map")

    to withDefault(key, default):
        return def mapDefaultExtractor(specimen, _):
            if (specimen.contains(key)):
                return [specimen[key], specimen.without(key)]
            else:
                return [default, specimen]


def _quasiMatcher(matchMaker, values) as DeepFrozenStamp:
    "Implementation of quasiliteral pattern syntax."

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
    "The implicit default matcher in a switch expression.
    
     This object throws an exception."

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


object _makeMap as DeepFrozenStamp:
    "A maker of maps."

    to fromPairs(l):
        def m := [].asMap().diverge()
        for [k, v] in l:
            m[k] := v
        return m.snapshot()


def _accumulateMap(iterable, mapper) as DeepFrozenStamp:
    "Implementation of map comprehension syntax."

    def l := _accumulateList(iterable, mapper)
    return _makeMap.fromPairs(l)


def _bind(resolver, guard) as DeepFrozenStamp:
    "Resolve a forward declaration."

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
    "Implementation of implicit breakage semantics in conditionally-defined
     names."

    to broken():
        return Ref.broken("Boolean flow expression failed")

    to failureList(count :Int) :List:
        return [false] + [_booleanFlow.broken()] * count


# DF abuse.
def makeLazySlot(var thunk, => guard := Any) as DeepFrozenStamp:
    "Make a slot that lazily binds its value."

    var evaluated :Bool := false

    return object lazySlot as DeepFrozenStamp:
        "A slot that possibly has not yet computed its value."

        to get() :guard:
            if (!evaluated):
                # Our predecessors had a trick where they nulled out the
                # reference to the thunk, which let the thunk be GC'd. While
                # this is good, we're going to go one step better and not have
                # two spots in the closure for the thunk and value. Instead,
                # the value replaces the thunk. ~ C.
                evaluated := true
                thunk := thunk()
            return thunk


def scopeAsDF(scope):
    return [for k => v in (scope)
            "&&" + k => (def v0 :DeepFrozen := v; &&v0)]

# New approach to importing the rest of the prelude: Collate the entirety of
# the module and boot scope into a single map which is then passed as-is to
# the other modules.
var preludeScope := scopeAsDF([
    => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
    => Int, => List, => Map, => NullOk, => Near, => Pair, => Same, => Set,
    => Selfless, => Str, => SubrangeGuard, => Void,
    => null, => Infinity, => NaN, => false, => true,
    => _auditedBy, => _equalizer, => _loop,
    => _makeList, => _makeMap, => _makeInt, => _makeDouble,
    => _makeSourceSpan, => _makeString, => _slotToBinding,
    => _makeBytes, => _makeFinalSlot, => _makeVarSlot,
    => throw, => trace, => traceln,
    => _mapEmpty, => _mapExtract,
    => _accumulateList, => _accumulateMap, => _booleanFlow, => _iterForever,
    => _validateFor,
    => _switchFailed, => _makeVerbFacet, => _comparer, => _suchThat,
    => _matchSame, => _bind, => _quasiMatcher, => _splitList,
    => M, => Ref, => ::"import", => throw, => typhonEval,
    => makeLazySlot,
])

def importIntoScope(name, moduleScope):
    preludeScope |= scopeAsDF(::"import".script(name, moduleScope))

# AST (needed for auditors).
importIntoScope(
    "prelude/monte_ast",
    preludeScope | scopeAsDF([=> DeepFrozenStamp, => TransparentStamp,
                              => KernelAstStamp]))

# Simple QP.
importIntoScope("prelude/simple", preludeScope)

# Brands require simple QP.
importIntoScope("prelude/brand", preludeScope)

# Interfaces require simple QP.
importIntoScope("prelude/protocolDesc",
                preludeScope | scopeAsDF([=> TransparentStamp]))

# Upgrade all guards with interfaces. These are the core-most guards; they
# cannot be uncalled or anything like that.
# preludeScope := scopeAsDF(
#     ::"import".script("prelude/coreInterfaces",
#                   preludeScope)) | preludeScope

# Spaces and regions require simple QP. They also upgrade the guards.
preludeScope := scopeAsDF(
    ::"import".script("prelude/region",
                  preludeScope)) | preludeScope

# b__quasiParser desires spaces.
importIntoScope("prelude/b", preludeScope)

# The big kahuna: The Monte compiler and QL.
# Note: This isn't portable. The usage of typhonEval() ties us to Typhon. This
# doesn't *have* to be the case, but it's the case we currently want to deal
# with. Or, at least, this is what *I* want to deal with. The AST currently
# doesn't support evaluation, and I'd expect it to be slow, so we're not doing
# that. Instead, we're feeding dumped AST to Typhon via this magic boot scope
# hook, and that'll do for now. ~ C.
def preludeScope0 := preludeScope | ["&&safeScope" => &&preludeScope0]
importIntoScope("prelude/m", preludeScope0)


# Transparent auditor and guard.
# This has to do some significant AST groveling so it uses AST quasipatterns
# for convenience.
importIntoScope("prelude/transparent", preludeScope)

preludeScope without= ("&&typhonEval")

# The final scope exported from the prelude. This *must* be the final
# expression in the module!
preludeScope
