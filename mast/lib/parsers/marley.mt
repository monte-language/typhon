import "unittest" =~ [=> unittest]
exports (makeMarley, marley__quasiParser)

# Copyright (C) 2015 Google Inc. All rights reserved.
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

# Earley's algorithm. Some slight improvements have been made here; it's not
# as good as Marpa but it's slightly better than original Earley due to
# better-behaved data structures.

# This version of Earley is fully incremental and token-at-a-time. It is
# polymorphic over the token and input types and can support non-character
# parses.

def Rule := List[Pair[DeepFrozen, DeepFrozen]]
def Rules := List[Rule]
def Grammar := Map[Str, Rules]

object terminal as DeepFrozen:
    pass

object nonterminal as DeepFrozen:
    pass


def makeTable(grammar, startRule) as DeepFrozen:
    def tableList := [[].asSet()].diverge()
    var queue := [].diverge()

    for production in grammar[startRule]:
        tableList[0] with= ([startRule, production, 0, [startRule]])

    def grow(k):
        while (tableList.size() <= k):
            # traceln(`Size is ${tableList.size()} and k is $k, so growing`)
            tableList.push([].asSet())

    return object table:
        to _printOn(out):
            out.print("Parsing table: ")
            for i => states in tableList:
                out.print(`State $i: `)
                for [head, rules, j] in states:
                    def formattedRules := [for [_, item] in (rules) item]
                    out.print(`: $head → $formattedRules ($j) ;`)

        to addState(k :Int, state):
            grow(k)
            if (!tableList[k].contains(state)):
                tableList[k] with= (state)
                queue.push([k, state])

        to nextState():
            if (queue.size() != 0):
                return queue.pop()
            return null

        to queueStates(k :Int):
            grow(k)
            for state in tableList[k]:
                queue.push([k, state])

        to get(index :Int) :Set:
            grow(index)
            return tableList[index]

        to headsAt(position :Int) :List:
            if (position >= tableList.size()):
                # We have no results (yet) at this position.
                return []

            def rv := [].diverge()
            for [head, rules, j, result] in tableList[position]:
                if (rules == [] && j == 0):
                    rv.push([head, result])
            return rv.snapshot()

        to hasQueuedStates() :Bool:
            return queue.size() > 0


def advance(position, token, grammar, table, ej) as DeepFrozen:
    table.queueStates(position - 1)
    if (!table.hasQueuedStates()):
        # The table isn't going to advance at all from this token; the parse
        # has failed.
        throw.eject(ej, "Parser cannot advance")

    var heads := []

    while (true):
        def [k, state] exit __break := table.nextState()
        # traceln(`Twiddling $state with k $k at position $position`)
        switch (state):
            match [head, ==[], j, result]:
                # Completion.
                for oldState in table[j]:
                    if (oldState =~
                        [oldHead, [==[nonterminal, head]] + tail, i, tree]):
                        table.addState(k,
                                       [oldHead, tail, i, tree.with(result)])
            match [_, [[==nonterminal, rule]] + _, _, _]:
                # Prediction.
                for production in grammar[rule]:
                    table.addState(k, [rule, production, k, [rule]])
            match [head, [[==terminal, literal]] + tail, j, result]:
                # Scan.
                # Scans can only take place when the token is in the position
                # immediately following the position of the scanning rule.
                if (k == position - 1):
                    if (literal.matches(token)):
                        table.addState(k + 1,
                                       [head, tail, j, result.with(token)])
                    else:
                        heads with= (literal.error())
            match _:
                # This usually means that the table got corrupted somehow.
                # Double imports can cause this.
                pass

    if (table[position].size() == 0):
        # Parse error: No progress was made.
        throw.eject(ej, `Expected one of $heads`)


def makeMarley(grammar, startRule) as DeepFrozen:
    def table := makeTable(grammar, startRule)
    var position :Int := 0
    var failure :NullOk[Str] := null

    return object marley:
        to getFailure() :NullOk[Str]:
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            for [head, result] in table.headsAt(position):
                if (head == startRule):
                    return true
            return false

        to results() :List:
            def rv := [].diverge()
            for [head, result] in table.headsAt(position):
                if (head == startRule):
                    rv.push(result)
            return rv.snapshot()

        to feed(token):
            traceln(`Feeding $token to $table`)
            if (failure != null):
                traceln(`Parser already failed: $failure`)
                return

            position += 1
            traceln(`Advancing position $position in table $table`)
            escape ej:
                advance(position, token, grammar, table, ej)
            catch reason:
                failure := reason

        to feedMany(tokens):
            for token in tokens:
                marley.feed(token)


def exactly(token :DeepFrozen) as DeepFrozen:
    "Create a matcher which matches only a single `DeepFrozen` token by
     equality."

    return object exactlyMatcher as DeepFrozen:
        to _uncall():
            return [exactly, [token], [].asMap()]

        to matches(specimen) :Bool:
            return token == specimen

        to error() :Str:
            return `exactly $token`


def parens :Grammar := [
    "parens" => [
        [],
        [[terminal, exactly('(')], [nonterminal, "parens"],
         [terminal, exactly(')')]],
    ],
]

def testMarleyParensFailed(assert):
    def parenParser := makeMarley(parens, "parens")
    parenParser.feedMany("asdf")
    assert.equal(parenParser.failed(), true)
    assert.equal(parenParser.finished(), false)

def testMarleyParensFinished(assert):
    def parenParser := makeMarley(parens, "parens")
    parenParser.feedMany("((()))")
    assert.equal(parenParser.failed(), false)
    assert.equal(parenParser.finished(), true)

def testMarleyParensPartial(assert):
    def parenParser := makeMarley(parens, "parens")
    parenParser.feedMany("(()")
    assert.equal(parenParser.failed(), false)
    assert.equal(parenParser.finished(), false)

def testMarleyWP(assert):
    def wp := [
        "P" => [
            [[nonterminal, "S"]],
        ],
        "S" => [
            [[nonterminal, "S"], [terminal, exactly('+')],
             [nonterminal, "M"]],
            [[nonterminal, "M"]],
        ],
        "M" => [
            [[nonterminal, "M"], [terminal, exactly('*')],
             [nonterminal, "T"]],
            [[nonterminal, "T"]],
        ],
        "T" => [
            [[terminal, exactly('1')]],
            [[terminal, exactly('2')]],
            [[terminal, exactly('3')]],
            [[terminal, exactly('4')]],
        ],
    ]
    def wpParser := makeMarley(wp, "P")
    wpParser.feedMany("2+3*4")
    assert.equal(wpParser.finished(), true)

## Disabled until Transparent auditor available.
# unittest([
#     testMarleyParensFailed,
#     testMarleyParensFinished,
#     testMarleyParensPartial,
#     testMarleyWP,
# ])

def alphanumeric :Set[Char] := ([for c in ('a'..'z' | 'A'..'Z' | '0'..'9') c]).asSet()
def escapeTable :Map[Char, Char] := ['n' => '\n']

def makeScanner(characters) as DeepFrozen:
    var pos :Int := 0

    return object scanner:
        to advance():
            pos += 1

        to peek():
            return if (pos < characters.size()) {
                characters[pos]
            } else {null}

        to expect(c):
            if (characters[pos] != c):
                throw("Problem here")
            scanner.advance()

        to nextChar():
            def rv := characters[pos]
            pos += 1
            return rv

        to eatWhitespace():
            def whitespace := [' ', '\n'].asSet()
            while (whitespace.contains(scanner.peek())):
                scanner.advance()

        to nextToken():
            scanner.eatWhitespace()
            while (true):
                traceln(`Scanning ${scanner.peek()}`)
                switch (scanner.nextChar()):
                    match c ? (alphanumeric.contains(c)):
                        # Identifier.
                        var s := c.asString()
                        traceln(`Found identifier $s`)
                        while (true):
                            if (scanner.peek() =~ c ? (alphanumeric.contains(c))):
                                s += c.asString()
                                traceln(`Now it's $s`)
                            else:
                                traceln(`Finally, $s`)
                                return ["identifier", s]
                            scanner.advance()
                    match =='-':
                        scanner.expect('>')
                        return "arrow"
                    match =='\'':
                        var c := scanner.nextChar()
                        if (c == '\\'):
                            # Escape character.
                            c := escapeTable[scanner.nextChar()]
                        scanner.expect('\'')
                        return ["character", c]
                    match =='|':
                        return "pipe"
                    match c:
                        return ["unknown", c]

        to hasTokens() :Bool:
            traceln(`Considering whether we have more tokens`)
            scanner.eatWhitespace()
            return pos < characters.size()


def tag(t :Str) as DeepFrozen:
    return object tagMatcher as DeepFrozen:
        to _uncall():
            return [tag, [t], [].asMap()]

        to matches(specimen) :Bool:
            return switch (specimen) {
                match [==t, _] {true}
                match ==t {true}
                match _ {false}
            }

        to error() :Str:
            return `tag $t`


def marleyQLGrammar :Grammar := [
    "charLiteral" => [
        [[terminal, tag("character")]],
    ],
    "identifier" => [
        [[terminal, tag("identifier")]],
    ],
    "rule" => [
        [[nonterminal, "charLiteral"], [nonterminal, "rule"]],
        [[nonterminal, "identifier"], [nonterminal, "rule"]],
        [],
    ],
    "alternation" => [
        [[nonterminal, "rule"], [terminal, tag("pipe")],
         [nonterminal, "alternation"]],
        [[nonterminal, "rule"]],
    ],
    "arrow" => [
        [[terminal, tag("arrow")]],
    ],
    "production" => [
        [[nonterminal, "identifier"], [nonterminal, "arrow"],
         [nonterminal, "alternation"]],
    ],
    "grammar" => [
        [[nonterminal, "production"], [nonterminal, "grammar"]],
        [[nonterminal, "production"]],
    ],
]


# It's assumed that left is the bigger of the two.
def combineProductions(left :Map, right :Map) :Map as DeepFrozen:
    var rv := left
    for head => rules in right:
        if (rv.contains(head)):
            rv with= (head, rv[head] + rules)
        else:
            rv |= [head => rules]
    return rv

def testCombineProductions(assert):
    def left := ["head" => ["first"]]
    def right := ["head" => ["second"], "tail" => ["third"]]
    def expected := ["head" => ["first", "second"], "tail" => ["third"]]
    assert.equal(combineProductions(left, right), expected)

unittest([testCombineProductions])


def marleyQLReducer(t) as DeepFrozen:
    switch (t):
        match [=="charLiteral", [_, c]]:
            return [terminal, exactly(c)]
        match [=="identifier", [_, i]]:
            return [nonterminal, i]
        match [=="rule", r, inner]:
            return [marleyQLReducer(r)] + marleyQLReducer(inner)
        match [=="rule"]:
            return []
        match [=="alternation", r, _, inner]:
            return [marleyQLReducer(r)] + marleyQLReducer(inner)
        match [=="alternation", r]:
            return [marleyQLReducer(r)]
        match [=="arrow", _]:
            return null
        match [=="production", head, _, rule]:
            return [marleyQLReducer(head)[1] => marleyQLReducer(rule)]
        match [=="grammar", p, g]:
            return combineProductions(marleyQLReducer(p), marleyQLReducer(g))
        match [=="grammar", p]:
            return marleyQLReducer(p)


object marley__quasiParser as DeepFrozen:
    to valueMaker([piece]):
        def scanner := makeScanner(piece)
        def parser := makeMarley(marleyQLGrammar, "grammar")
        while (scanner.hasTokens()):
            def token := scanner.nextToken()
            traceln(`Next token: $token`)
            traceln(`Parser: ${parser.getFailure()}`)
            parser.feed(token)
        def r := parser.results()[0]
        return object ruleSubstituter:
            to substitute(_):
                return def reduced(head):
                    return makeMarley(marleyQLReducer(r), head)


def testMarleyQPSingle(assert):
    def handwritten := ["breakfast" => [[[nonterminal, "eggs"],
                                         [terminal, exactly('&')],
                                         [nonterminal, "bacon"]]]]
    def generated := marley`breakfast -> eggs '&' bacon`
    assert.equal(handwritten, generated)

def testMarleyQPDouble(assert):
    def handwritten := [
        "empty" => [[]],
        "nonempty" => [[[nonterminal, "empty"]]],
    ]
    def generated := marley`
        empty ->
        nonempty -> empty
    `
    assert.equal(handwritten, generated)

# unittest([
#     testMarleyQPSingle,
#     testMarleyQPDouble,
# ])
