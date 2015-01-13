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

def [=> simple__quasiParser] | _ := import("lib/simple")

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
            return nullable(a) & nullable(b)

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
            return isEmpty(a) | isEmpty(b)
        match [==repeat, l]:
            return isEmpty(l)

        match _:
            return false


def trees(l):
    switch (l):
        match ==nullSet:
            return [null]
        match [==term, ts]:
            return ts
        match [==reduction, inner, f]:
            var rv := []
            def ts := trees(inner)
            for tree in ts:
                rv += f(tree)
            return rv
        match [==alternation, ls]:
            var ts := []
            for l in ls:
                ts += trees(l)
            return ts
        match [==catenation, a, b]:
            def ts := [].diverge()
            for x in trees(a):
                for y in trees(b):
                    ts.push([x, y])
            return ts.snapshot()
        match [==repeat, _]:
            return [null]

        match _:
            return []


def _leaders(l):
    switch (l):
        match ==nullSet:
            return [null]
        match [==term, _]:
            return [null]

        match ==anything:
            return [anything]
        match [==exactly, c]:
            return [c]

        match [==reduction, inner, _]:
            return _leaders(inner)

        match [==alternation, ls]:
            var rv := []
            for inner in ls:
                rv += _leaders(inner)
            return rv

        match [==catenation, a ? nullable(a), b]:
            if (onlyNull(a)):
                return _leaders(b)
            else:
                return _leaders(a) + _leaders(b)
        match [==catenation, a, b]:
            return _leaders(a)

        match [==repeat, l]:
            return [null] + _leaders(l)

        match _:
            return []


def _filterEmpty(xs):
    return [x for x in xs if x != empty]


def derive(l, c):
    switch (l):
        match x ? isEmpty(x):
            return empty

        match ==nullSet:
            return empty
        match [==term, _]:
            return empty

        match ==anything:
            return [term, [c]]
        match [==exactly, ==c]:
            return [term, [c]]
        match [==exactly, _]:
            return empty

        match [==reduction, inner, f]:
            return [reduction, derive(inner, c), f]
        match [==alternation, ls]:
            return [alternation, _filterEmpty([derive(l, c) for l in ls])]

        match [==catenation, a ? nullable(a), b]:
            def da := derive(a, c)
            def db := derive(b, c)
            def rv := [alternation,
                [[catenation, da, b],
                 [catenation, [term, trees(a)], db]]]
            return rv
        match [==catenation, a, b]:
            def rv := [catenation, derive(a, c), b]
            return rv

        match [==repeat, l]:
            return [catenation, derive(l, c), [repeat, l]]

        match _:
            return empty


def compact(l):
    switch (l):
        match [==reduction, x ? isEmpty(x), _]:
            return empty

        match [==reduction, inner ? onlyNull(inner), f]:
            var reduced := []
            for tree in trees(inner):
                reduced += f(tree)
            return [term, reduced]

        match [==reduction, [==reduction, inner, f], g]:
            def compose(x):
                var rv := []
                for item in f(x):
                    rv += g(item)
                return rv
            return compact([reduction, inner, compose], j)

        match [==reduction, inner, f]:
            return [reduction, compact(inner), f]

        match [==alternation, ls]:
            # First, recurse into the subordinate parse trees, and look for
            # more alternations. We're going to flatten all of them out.
            def leaves := [].diverge()
            def stack := ls.diverge()
            while (stack.size() > 0):
                switch (stack.pop()):
                    match [==alternation, more]:
                        for t in more:
                            stack.push(t)
                    match x:
                        leaves.push(x)

            # Now, compact and filter away empty leaves, and return the
            # remainder.
            def compacted := _filterEmpty([compact(l) for l in leaves])
            switch (compacted):
                match []:
                    return empty
                match [inner]:
                    return inner
                match x:
                    return [alternation, x]

        match [==catenation, a ? onlyNull(a), b]:
            def xs := trees(a)
            def curry(y):
                def ts := [].diverge()
                for x in xs:
                    ts.push([x, y])
                return ts.snapshot()
            return compact([reduction, b, curry])

        match [==catenation, a, b]:
            if (isEmpty(a) | isEmpty(b)):
                return empty
            return [catenation, compact(a), compact(b)]

        match [==repeat, x ? isEmpty(x)]:
            return [term, [null]]

        match [==repeat, inner]:
            return [repeat, compact(inner)]

        match _:
            return l


def testEmptyDerive(assert):
    assert.equal(derive(empty, 'x'), empty)

unittest([testEmptyDerive])

def testExactlyDerive(assert):
    assert.equal(trees(derive([exactly, 'x'], 'x')), ['x'])

unittest([testExactlyDerive])

def testReduceDerive(assert):
    def plusOne(x):
        return [x + 1]
    assert.equal(trees(derive([reduction, [exactly, 'x'], plusOne], 'x')),
                 ['y'])

unittest([testReduceDerive])

def testAlternationOptimizationEmpty(assert):
    def single := [alternation, [empty]]
    assert.equal(compact(single), empty)

def testAlternationOptimizationTree(assert):
    def deep := [alternation, [
        [alternation, [
            [alternation, [[exactly, 'x'], empty]],
            [alternation, [empty]],
            [exactly, 'y'],
        ]],
        [exactly, 'z'],
    ]]
    # Note that the optimizing traversal inverts the tree, so the leaves
    # are listed here in backwards order from their original positions.
    assert.equal(compact(deep), [alternation, [
        [exactly, 'z'],
        [exactly, 'y'],
        [exactly, 'x']]])

def testAlternationPair(assert):
    def l := [alternation, [[exactly, 'x'], [exactly, 'y']]]
    assert.equal(trees(derive(l, 'x')), ['x'])
    assert.equal(trees(derive(l, 'y')), ['y'])

def testAlternationMany(assert):
    def l := [alternation, [[exactly, 'x'], [exactly, 'y'], [exactly, 'z']]]
    assert.equal(trees(derive(l, 'x')), ['x'])
    assert.equal(trees(derive(l, 'y')), ['y'])
    assert.equal(trees(derive(l, 'z')), ['z'])
    assert.equal(trees(derive(l, 'w')), [])

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
    def l := [catenation, [term, ['x']], [term, ['y']]]
    assert.equal(trees(compact(l)), [['x', 'y']])

def testCatenationDerive(assert):
    def l := [catenation, [exactly, 'x'], [exactly, 'y']]
    assert.equal(trees(derive(derive(l, 'x'), 'y')), [['x', 'y']])

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
    assert.equal(trees(derive(l, 'x')), [['x', null]])
    assert.equal(trees(derive(derive(l, 'x'), 'x')), [['x', ['x', null]]])

unittest([
    testRepeatNull,
    testRepeatDerive,
])

def _pureToList(f):
    return fn x { [f(x)] }

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
            return makeDerp([alternation, [language, other.unwrap()]])

        to mod(other):
            # Inspired by lens, which uses `%` for its modification/map API.
            # Their mnemonic is *mod*ification, for *mod*ulus.
            return makeDerp([reduction, language, _pureToList(other)])

        to repeated():
            # Repeat!
            return makeDerp([repeat, language])

        # Parser API.

        to size() :Int:
            return parserSize(language)

        to leaders():
            # XXX return _leaders(language).asSet()
            return _leaders(language)

        to compacted():
            return makeDerp(compact(language))

        to feed(c):
            # traceln(`Leaders: ${parser.leaders()}`)
            traceln(`Character: $c`)
            def derived := derive(language, c)
            traceln(`Raw size: ${parserSize(derived)}`)
            def compacted := compact(derived)
            if (isEmpty(compacted)):
                traceln("Language is empty!")
            traceln(`Compacted size: ${parserSize(compacted)}`)
            def p := makeDerp(compacted)
            traceln(`Compacted: $p`)
            return p

        to feedMany(cs):
            var p := parser
            for c in cs:
                p := p.feed(c)
            return p

        to results():
            return trees(language)

def ex(x):
    return makeDerp([exactly, x])

[
    => makeDerp,
    => ex,
    "anything" => fn {makeDerp(anything)},
]
