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

def any(l :List[Bool]) :Bool:
    for x in l:
        if (x):
            return true
    return false

def all(l :List[Bool]) :Bool:
    for x in l:
        if (!x):
            return false
    return true

def singletonSet(s, ej):
    if (s.size() != 1):
        throw.eject(ej, "Not a singleton set")
    return s.asList()[0]

# The core.

object empty:
    to _printOn(out):
        out.print("∅")

object nullSet:
    to _printOn(out):
        out.print("ε")

object anything:
    to _printOn(out):
        out.print("∀")

object anyOf:
    to _printOn(out):
        out.print("∈")

object exactly:
    to _printOn(out):
        out.print("≡")

object term:
    to _printOn(out):
        out.print("term")

object reduction:
    to _printOn(out):
        out.print("red")

object alternation:
    to _printOn(out):
        out.print("∨")

object catenation:
    to _printOn(out):
        out.print("∧")

object repeat:
    to _printOn(out):
        out.print("*")


def parserSize(l) :Int:
    switch (l):
        match ==empty:
            return 1
        match ==nullSet:
            return 1
        match ==anything:
            return 1
        match [==exactly, _]:
            return 1
        match [==anyOf, _]:
            return 1

        match [==term, ts]:
            return 1 + parserSize(ts)
        match [==reduction, inner, f]:
            return 1 + parserSize(inner)
        match [==alternation, ls]:
            var sum := 1
            for l in ls:
                sum += parserSize(l)
            return sum
        match [==catenation, a, b]:
            return 1 + parserSize(a) + parserSize(b)
        match [==repeat, inner]:
            return 1 + parserSize(inner)

        match _:
            return 1


def onlyNull(l) :Bool:
    switch (l):
        match ==nullSet:
            return true
        match [==term, _]:
            return true

        match [==reduction, inner, _]:
            return onlyNull(inner)
        match [==alternation, ls]:
            return all([onlyNull(l) for l in ls])
        match [==catenation, a, b]:
            return onlyNull(a) & onlyNull(b)

        match _:
            return false


def nullable(l) :Bool:
    if (onlyNull(l)):
        return true

    switch (l):
        match [==reduction, inner, _]:
            return nullable(inner)
        match [==alternation, ls]:
            return any([nullable(l) for l in ls])
        match [==catenation, a, b]:
            return nullable(a) && nullable(b)

        match [==repeat, _]:
            return true

        match _:
            return false


def isEmpty(l) :Bool:
    switch (l):
        match ==empty:
            return true
        match [==reduction, inner, _]:
            return isEmpty(inner)
        match [==alternation, ls]:
            return all([isEmpty(l) for l in ls])
        match [==catenation, a, b]:
            return isEmpty(a) || isEmpty(b)
        match [==repeat, l]:
            return isEmpty(l)

        match _:
            return false


def trees(l) :Set:
    switch (l):
        match ==nullSet:
            return [null].asSet()
        match [==term, ts]:
            return ts
        match [==reduction, inner, f]:
            var rv := [].asSet()
            def ts := trees(inner)
            for tree in ts:
                rv |= f(tree)
            return rv
        match [==alternation, ls]:
            var ts := [].asSet()
            for l in ls:
                ts |= trees(l)
            return ts
        match [==catenation, a, b]:
            var ts := [].asSet()
            for x in trees(a):
                for y in trees(b):
                    ts with= [x, y]
            return ts
        match [==repeat, _]:
            return [null].asSet()

        match _:
            return [].asSet()


object nullLeader:
    pass

object anyLeader:
    pass


def leaders(l) :Set:
    switch (l):
        match ==nullSet:
            return [nullLeader].asSet()
        match [==term, _]:
            return [nullLeader].asSet()

        match ==anything:
            return [anyLeader].asSet()
        match [==exactly, c]:
            return [c].asSet()
        match [==anyOf, xs]:
            return xs

        match [==reduction, inner, _]:
            return leaders(inner)

        match [==alternation, ls]:
            var rv := [].asSet()
            for inner in ls:
                rv |= leaders(inner)
            return rv

        match [==catenation, a ? nullable(a), b]:
            if (onlyNull(a)):
                return leaders(b)
            else:
                return leaders(a) | leaders(b)
        match [==catenation, a, b]:
            return leaders(a)

        match [==repeat, l]:
            return leaders(l).with(nullLeader)

        match _:
            return [].asSet()


def _filterEmpty(xs):
    return [x for x in xs if x != empty]


def derive(l, c):
    # Optimization in derive(): Do not permit cat(empty, _) to come into
    # existence. It is too costly, since it preserves its second tree for far
    # too long. Also watch out for cat(_, empty) in the rare case that it can
    # form, when deriving cat.
    switch (l):
        match x ? isEmpty(x):
            return empty

        match ==nullSet:
            return empty
        match [==term, _]:
            return empty

        match ==anything:
            return [term, [c].asSet()]
        match [==exactly, ==c]:
            return [term, [c].asSet()]
        match [==exactly, _]:
            return empty
        match [==anyOf, xs]:
            return if (xs.contains(c)) {[term, [c].asSet()]} else {empty}

        match [==reduction, inner, f]:
            return [reduction, derive(inner, c), f]
        match [==alternation, ls]:
            return [alternation,
                    _filterEmpty([derive(l, c) for l in ls]).asSet()]

        match [==catenation, a ? (nullable(a)), b]:
            def da := derive(a, c)
            if (da == empty):
                def db := derive(b, c)
                if (db == empty):
                    return empty
                # db cannot be empty, and a must be nullable.
                return [catenation, [term, trees(a)], db]

            def db := derive(b, c)
            if (db == empty):
                # da cannot be empty.
                return [catenation, da, b]

            # The worst case. Completely legal, though.
            return [alternation, [[catenation, da, b], [catenation, [term, trees(a)], db]].asSet()]

        match [==catenation, a, b]:
            # a cannot be nullable.
            def da := derive(a, c)
            if (da == empty):
                return empty
            return [catenation, da, b]

        match [==repeat, a]:
            def da := derive(a, c)
            return if (da == empty) {empty} else {[catenation, da, l]}

        match _:
            return empty


def compact(l):
    # Perform zero or more graph reductions to the head of a parser.
    # The body of the parser will generally not be reduced.
    # Irreducable heads:
    # ~ empty
    # ~ term
    # Conditionally reducable heads:
    # ~ red, when its body is only null or empty
    # ~ cat, when its front is only null or empty

    switch (l):
        # Remove empty reds.
        match [==reduction, x ? (isEmpty(x)), _]:
            return empty

        # The red's inner expression can only accept null. We can apply the
        # reduction and gain terminals.
        match [==reduction, inner ? (onlyNull(inner)), f]:
            var reduced := [].asSet()
            for tree in trees(inner):
                reduced |= f(tree)
            return [term, reduced]

        # When red is inside red, we can compose their functions.
        match [==reduction, [==reduction, inner, f], g]:
            def compose(x) :Set:
                var rv := [].asSet()
                for item in f(x):
                    rv |= g(item)
                return rv
            # red is still compactable.
            return compact([reduction, inner, compose])

        # An alternation that has been defeated on every path is empty.
        match [==alternation, _ :Empty]:
            return empty

        # An alternation with only one remaining path is equivalent to just
        # that path.
        match [==alternation, via (singletonSet) inner]:
            return compact(inner)

        # Alternations can be flattened.
        match [==alternation, ls]:
            # First, recurse into the subordinate parse trees, and look for
            # more alternations. We're going to flatten all of them out.
            def leaves := [].diverge()
            def stack := ls.asList().diverge()
            while (stack.size() > 0):
                switch (stack.pop()):
                    match [==alternation, more]:
                        for t in more:
                            stack.push(t)
                    match x:
                        leaves.push(x)

            # Now, filter away empty leaves, and return the remainder.
            def compacted := _filterEmpty(leaves)
            return [alternation, compacted.asSet()]

        # If the front of a cat is null, then we can produce a red on its
        # back and finish evaluating the front.
        match [==catenation, a ? (onlyNull(a)), b]:
            def xs := trees(a)
            def curry(y) :Set:
                var ts := [].asSet()
                for x in xs:
                    ts with= [x, y]
                return ts
            return compact([reduction, b, curry])

        # If either part of a cat is empty, then the cat is empty.
        match [==catenation, a ? (isEmpty(a)), b]:
            return empty
        match [==catenation, a, b ? (isEmpty(b))]:
            return empty

        # If a rep is empty, then it has one possible path: The path of zero
        # matches. Simplify to that path.
        match [==repeat, x ? (isEmpty(x))]:
            return [term, [null].asSet()]

        match _:
            return l


def testEmptyDerive(assert):
    assert.equal(derive(empty, 'x'), empty)

unittest([testEmptyDerive])

def testExactlyDerive(assert):
    assert.equal(trees(derive([exactly, 'x'], 'x')), ['x'].asSet())

unittest([testExactlyDerive])

def testReduceDerive(assert):
    def plusOne(x):
        return [x + 1].asSet()
    assert.equal(trees(derive([reduction, [exactly, 'x'], plusOne], 'x')),
                 ['y'].asSet())

unittest([testReduceDerive])

def testAlternationOptimizationEmpty(assert):
    def single := [alternation, [empty].asSet()]
    assert.equal(compact(single), empty)

def testAlternationOptimizationTree(assert):
    def deep := [alternation, [
        [alternation, [
            [alternation, [[exactly, 'x'], empty].asSet()],
            [alternation, [empty].asSet()],
            [exactly, 'y'],
        ].asSet()],
        [exactly, 'z'],
    ].asSet()]
    # Note that the optimizing traversal inverts the tree, so the leaves
    # are listed here in backwards order from their original positions.
    assert.equal(compact(deep), [alternation, [
        [exactly, 'z'],
        [exactly, 'y'],
        [exactly, 'x']].asSet()])

def testAlternationPair(assert):
    def l := [alternation, [[exactly, 'x'], [exactly, 'y']].asSet()]
    assert.equal(trees(derive(l, 'x')), ['x'].asSet())
    assert.equal(trees(derive(l, 'y')), ['y'].asSet())

def testAlternationMany(assert):
    def l := [alternation,
              [[exactly, 'x'], [exactly, 'y'], [exactly, 'z']].asSet()]
    assert.equal(trees(derive(l, 'x')), ['x'].asSet())
    assert.equal(trees(derive(l, 'y')), ['y'].asSet())
    assert.equal(trees(derive(l, 'z')), ['z'].asSet())
    assert.equal(trees(derive(l, 'w')), [].asSet())

unittest([
    testAlternationOptimizationEmpty,
    testAlternationOptimizationTree,
    testAlternationPair,
    testAlternationMany,
])

def testCatenationCompactEmpty(assert):
    def l := [catenation, empty, [exactly, 'x']]
    assert.equal(compact(l), empty)

def testCatenationCompactNull(assert):
    def l := [catenation, [term, ['x'].asSet()], [term, ['y'].asSet()]]
    assert.equal(trees(compact(l)), [['x', 'y']].asSet())

def testCatenationDerive(assert):
    def l := [catenation, [exactly, 'x'], [exactly, 'y']]
    assert.equal(trees(derive(derive(l, 'x'), 'y')), [['x', 'y']].asSet())

unittest([
    testCatenationCompactEmpty,
    testCatenationCompactNull,
    testCatenationDerive,
])

def testRepeatNull(assert):
    def l := [repeat, [exactly, 'x']]
    assert.equal(true, nullable(l))
    assert.equal(false, onlyNull(l))

def testRepeatDerive(assert):
    def l := [repeat, [exactly, 'x']]
    assert.equal(trees(derive(l, 'x')), [['x', null]].asSet())
    assert.equal(trees(derive(derive(l, 'x'), 'x')),
                 [['x', ['x', null]]].asSet())

unittest([
    testRepeatNull,
    testRepeatDerive,
])

def _pureToSet(f):
    return fn x { [f(x)].asSet() }

def _unstackRepeats(xs):
    switch (xs):
        match ==null:
            return []
        match [x, ==null]:
            return [x]
        match [x, stack]:
            return [x] + _unstackRepeats(stack)

def makeDerp(language):
    return object parser:
        to unwrap():
            return language

        # Monte core methods.

        to _printOn(out):
            out.print(`Parser (${parserSize(language)}): `)
            out.print(M.toString(language))

        # EDSL wrapper methods.

        to add(other):
            # Addition is catenation.
            return makeDerp([catenation, language, other.unwrap()])

        to or(other):
            # Alternation.
            return makeDerp([alternation, [language, other.unwrap()].asSet()])

        to mod(other):
            # Inspired by lens, which uses `%` for its modification/map API.
            # Their mnemonic is *mod*ification, for *mod*ulus.
            return makeDerp([reduction, language, _pureToSet(other)])

        to repeated():
            # Repeat!
            return makeDerp([repeat, language]) % _unstackRepeats

        # Parser API.

        to size() :Int:
            return parserSize(language)

        to leaders():
            return leaders(language)

        to compacted():
            return makeDerp(compact(language))

        to feed(c):
            # traceln(`Leaders: ${parser.leaders()}`)
            # traceln(`Character: $c`)
            def derived := derive(language, c)
            # traceln(`Raw size: ${parserSize(derived)}`)
            def compacted := compact(derived)
            # if (isEmpty(compacted)):
            #     traceln("Language is empty!")
            # traceln(`Compacted size: ${parserSize(compacted)}`)
            def p := makeDerp(compacted)
            # traceln(`Compacted: $p`)
            return p

        to feedMany(cs):
            var p := parser
            for c in cs:
                p := p.feed(c)
            return p

        to results() :Set:
            return trees(language)

        to isEmpty() :Bool:
            return isEmpty(language)

        to canFinish() :Bool:
            return leaders(language).contains(nullLeader)

        # The most convenient thing to do with run().

        to run(cs) :Set:
            return parser.feedMany(cs).results()

def ex(x):
    return makeDerp([exactly, x])

def set(xs :Set):
    return makeDerp([anyOf, xs])

[
    => makeDerp,
    => ex,
    "anything" => fn {makeDerp(anything)},
    => set,
    => nullLeader,
    => anyLeader,
]
