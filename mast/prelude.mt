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
            def error := try {
                if (predicate(specimen)) { return specimen }
                def conformed := specimen._conformTo(predicateGuard)
                if (predicate(conformed)) { return conformed }
                "Failed guard (" + label + "):"
            } catch ex { "Caught exception while conforming (" + label + "):" }
            throw.eject(ej, [error, specimen])


def Empty := makePredicateGuard(def pred(specimen) as DeepFrozenStamp {return specimen.size() == 0}, "Empty")
# Alias for map patterns.
def _mapEmpty := Empty


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
                    for element in (specimen):
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
                for element in (specimen):
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
                    for key => value in (specimen):
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

object _VowStamp:
    to audit(audition):
        return true

object Vow as DeepFrozenStamp:
    "A guard which admits promises and their entailments.

     Vows admit the union of unfulfilled promises, fulfilled promises, broken
     promises, and `Near` values. The unifying concept is that of a partial
     future value to which messages will be sent but that is not `Far`.

     When specialized, this guard returns a guard which ensures that promised
     prizes either conform to its subguard or are broken."

    to _printOn(out):
        out.print("Vow")

    to coerce(specimen, ej):
        if (Ref.isNear(specimen) || Ref.isBroken(specimen) ||
            (Ref.isEventual(specimen) &! Ref.isFar(specimen))):
            return specimen

        def conformed := specimen._conformTo(Vow)

        if (Ref.isNear(conformed) || Ref.isBroken(conformed) ||
            (Ref.isEventual(conformed) &! Ref.isFar(conformed))):
            return conformed

        throw.eject(ej, ["Not avowable:", specimen])

    to get(subGuard):
        return object SubVow implements _VowStamp, Selfless, TransparentStamp:
            to _printOn(out):
                out.print("Vow[")
                out.print(subGuard)
                out.print("]")

            to _uncall():
                return [Vow, "get", [subGuard], [].asMap()]

            to coerce(specimen, ej):
                return if (Ref.isNear(specimen)) {
                    subGuard.coerce(specimen, ej)
                } else if (Ref.isBroken(specimen)) {
                    specimen
                } else if (Ref.isEventual(specimen) &! Ref.isFar(specimen)) {
                    # XXX I don't know why FAIL isn't always passed in here.
                    # Something about our ref stack is off, maybe. ~ C.
                    def cb(x, => FAIL := null) {
                        return subGuard.coerce(x, FAIL)
                    }
                    Ref.whenResolved(specimen, cb)
                } else {
                    throw.eject(ej, ["Not avowable:", specimen])
                }

            to getGuard():
                return subGuard

    to extractGuard(specimen, ej):
        if (specimen == Vow):
            return Any
        else if (_auditedBy(_VowStamp, specimen)):
            return specimen.getGuard()
        else:
            throw.eject(ej, "Not a Vow guard")

object _iterForever as DeepFrozenStamp:
    "Implementation of while-expression syntax."

    to _makeIterator():
        return _iterForever
    to next(ej):
        return [null, null]


def _splitList(position :Int) as DeepFrozenStamp:
    "
    Implementation of tail pattern-matching syntax in list patterns.

    m`def [x] + xs := l`.expand() == m`def via (_splitList.run(1)) [x, xs] := l`
    "

    # DF is justified by only `position`, `throw`, and `M` being free. ~ C.
    return def listSplitter(specimen, ej) as DeepFrozenStamp:
        def l :List exit ej := specimen
        if (l.size() < position):
            throw.eject(ej, "Needed " + M.toString(position) +
                        " elements, but only got " + M.toString(l.size()))
        return l.slice(0, position).with(l.slice(position))


def _accumulateList(iterable, mapper) as DeepFrozenStamp:
    "Implementation of list comprehension syntax."

    def iterator := iterable._makeIterator()
    # Flex for speed. ~ C.
    def rv := [].diverge()

    escape ej:
        while (true):
            escape skip:
                def [key, value] := iterator.next(ej)
                rv.push(mapper(key, value, skip))

    return rv.snapshot()


object nullAuditor as DeepFrozenStamp:
    "The do-nothing auditor."

    to audit(audition):
        return true

object _matchSame as DeepFrozenStamp:
    to run(expected):
        "The pattern ==`expected`."

        def _sameMatcher(specimen, ej):
            if (expected != specimen):
                throw.eject(ej, ["Not same:", expected, specimen])
            return specimen

        return object sameMatcher extends _sameMatcher:
            to _conformTo(guard):
                return if (guard == DeepFrozen):
                    escape ej:
                        DeepFrozen.coerce(expected, ej)
                        def sameMatcher(specimen, ej) as DeepFrozenStamp:
                            return _sameMatcher(specimen, ej)

    to different(expected):
        "The pattern !=`expected`."

        def _differentMatcher(specimen, ej):
            if (expected == specimen):
                throw.eject(ej, ["Same:", expected, specimen])
            return specimen

        return object differentMatcher extends _differentMatcher:
            to _conformTo(guard):
                return if (guard == DeepFrozen):
                    escape ej:
                        DeepFrozen.coerce(expected, ej)
                        def differentMatcher(specimen, ej) as DeepFrozenStamp:
                            return _differentMatcher(specimen, ej)


object _mapExtract as DeepFrozenStamp:
    "Implementation of key pattern-matching syntax in map patterns."

    to run(key):
        "The pattern [=> `key`]."

        def _mapExtractor(specimen, ej):
            def map :Map exit ej := specimen
            if (map.contains(key)):
                return [map[key], map.without(key)]
            throw.eject(ej, "Key " + M.toQuote(key) + " not in map")

        return object mapExtractor extends _mapExtractor:
            to _conformTo(guard):
                return if (guard == DeepFrozen):
                    escape ej:
                        DeepFrozen.coerce(key, ej)
                        def mapExtractor(specimen, ej) as DeepFrozenStamp:
                            return _mapExtractor(specimen, ej)

    to withDefault(key, default):
        "The pattern [=> `key` := `default`]."

        def _mapDefaultExtractor(specimen, ej):
            def map :Map exit ej := specimen
            if (map.contains(key)):
                return [map[key], map.without(key)]
            else:
                return [default, map]

        return object mapDefaultExtractor extends _mapDefaultExtractor:
            to _conformTo(guard):
                return if (guard == DeepFrozen):
                    escape ej:
                        DeepFrozen.coerce(key, ej)
                        DeepFrozen.coerce(default, ej)
                        def mapDefaultExtractor(specimen, ej) as DeepFrozenStamp:
                            return _mapDefaultExtractor(specimen, ej)


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


object _switchFailed as DeepFrozenStamp:
    "The implicit default matcher in a switch expression.

     This object throws an exception."

    match [=="run", args, _]:
        throw("Switch failed: " + M.toString(args))


object _makeVerbFacet as DeepFrozenStamp:
    "The operator `obj`.`method`."

    to curryCall(target, verb :Str):
        "Curry a call to `target` using `verb`."

        return object curried implements Selfless, SemitransparentStamp:
            "A curried call.

             This object responds to messages with the verb \"run\" by passing
             them to another object with a different verb."

            to _uncall():
                return SemitransparentStamp.seal([
                    _makeVerbFacet, "curryCall", [target, verb],
                    [].asMap()])

            match [=="run", args, namedArgs]:
                M.call(target, verb, args, namedArgs)

    to currySend(target, verb :Str):
        "Curry a send to `target` using `verb`."

        return object curried implements Selfless, SemitransparentStamp:
            "A curried send.

             This object responds to messages with the verb \"run\" by passing
             them to another object with a different verb."

            to _uncall():
                return SemitransparentStamp.seal(
                    [_makeVerbFacet, "currySend", [target, verb],
                     [].asMap()])

            match [=="run", args, namedArgs]:
                M.send(target, verb, args, namedArgs)


def _accumulateMap(iterable, mapper) as DeepFrozenStamp:
    "Implementation of map comprehension syntax."

    def l := _accumulateList(iterable, mapper)
    return _makeMap.fromPairs(l)


def _bind(resolver, guard) as DeepFrozenStamp:
    "Resolve a forward declaration."

    def viaBinder(specimen, ej):
        return if (guard == null):
            resolver.resolve(specimen)
            specimen
        else:
            def coerced := guard.coerce(specimen, ej)
            resolver.resolve(coerced)
            coerced
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

        to getGuard():
            return guard


def promiseAllFulfilled(vows) as DeepFrozenStamp:
    var counter := vows.size()
    if (counter == 0):
        return vows
    def [p, r] := Ref.promise()
    for v in (vows):
        Ref.whenResolvedOnly(v, def done(_) {
            if (Ref.isBroken(v)) {
                r.resolveRace(v)
            } else if ((counter -= 1) <= 0) {
                r.resolve(vows)
            }
        })
    return p


def scopeNames := [
    => Any, => Bool, => Bytes, => Char, => DeepFrozen, => Double, => Empty,
    => Int, => List, => Map, => NullOk, => Near, => Pair, => Same, => Set,
    => Selfless, => Str, => SubrangeGuard, => Void, => Vow,
    => null, => Infinity, => NaN, => false, => true,
    => _auditedBy, => _equalizer, => _loop,
    => _makeList, => _makeMap, => _makeInt, => _makeDouble,
    => _makeSourceSpan, => _makeStr, => _slotToBinding,
    => _makeBytes, => _makeFinalSlot, => _makeVarSlot,
    => throw, => trace, => traceln,
    => _mapEmpty, => _mapExtract,
    => _accumulateList, => _accumulateMap, => _booleanFlow, => _iterForever,
    => _validateFor,
    => _switchFailed, => _makeVerbFacet, => _comparer, => _suchThat,
    => _matchSame, => _bind, => _quasiMatcher, => _splitList,
    => M, => Ref,  => throw, => astEval, => promiseAllFulfilled,
    => makeLazySlot]

def scopeAsDF(scope):
    return [for k => v in (scope)
            "&&" + k => (def v0 :DeepFrozen := v; &&v0)]


var preludeScope := scopeAsDF(scopeNames)
def preludeStamps := [=> DeepFrozenStamp, => TransparentStamp, => KernelAstStamp,
                      => SemitransparentStamp]
def dependencies := [].asMap().diverge()
object stubLoader:
    to "import"(name):
        if (name == "boot"):
            return preludeStamps
        if (name == "safeScope"):
            return preludeScope
        if (name == "unittest"):
            return ["unittest" => fn _ {null}]
        if (name == "bench"):
            return ["bench" => fn _, _ {null}]
        return dependencies[name]


def loadit(name):
    def m := getMonteFile(name, preludeScope)
    return m(stubLoader)

def importIntoScope(name):
    preludeScope |= scopeAsDF(loadit(name))
dependencies["ast_printer"] := loadit("prelude/ast_printer")
dependencies["lib/iterators"] := loadit("lib/iterators")
# AST (needed for auditors).
importIntoScope("prelude/monte_ast")

# Simple QP.
importIntoScope("prelude/simple")

# Brands require simple QP.
importIntoScope("prelude/brand")

# Interfaces require simple QP.
importIntoScope("prelude/protocolDesc")

# Upgrade all guards with interfaces. These are the core-most guards; they
# cannot be uncalled or anything like that.

# preludeScope := scopeAsDF(loadit("prelude/coreInterfaces")) | preludeScope

# Spaces and regions require simple QP. They also upgrade the guards.
preludeScope := scopeAsDF(loadit("prelude/region")) | preludeScope

# b__quasiParser desires spaces.
importIntoScope("prelude/b")

# Parsing stack. These don't directly contribute to scope but are loaded by m.
for module in ([
    "lib/monte/monte_lexer",
    "lib/monte/monte_parser",
    "lib/monte/monte_expander",
    "lib/monte/monte_optimizer",
    "lib/codec/utf8",
    "lib/monte/mast",
]):
    dependencies[module] := loadit(module)

# The big kahuna: The Monte compiler and QL.
# Note: This isn't portable. The usage of typhonEval() ties us to Typhon. This
# doesn't *have* to be the case, but it's the case we currently want to deal
# with. Or, at least, this is what *I* want to deal with. The AST currently
# doesn't support evaluation, and I'd expect it to be slow, so we're not doing
# that. Instead, we're feeding dumped AST to Typhon via this magic boot scope
# hook, and that'll do for now. ~ C.
importIntoScope("prelude/m")


# Transparent auditor and guard.
# This has to do some significant AST groveling so it uses AST quasipatterns
# for convenience.
importIntoScope("prelude/transparent")
preludeScope with= ("&&safeScope", &&preludeScope)

# preludeScope without= ("&&typhonEval")

# The final scope exported from the prelude. This *must* be the final
# expression in the module!
preludeScope
