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

object terminal:
    pass

object nonterminal:
    pass

def makeTable(grammar, startRule):
    def tableList := [[].asSet()].diverge()
    var queue := [].diverge()

    for production in grammar[startRule]:
        tableList[0] with= [startRule, production, 0, [startRule]]

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
                    def formattedRules := [item for [_, item] in rules]
                    out.print(`: $head → $formattedRules ($j) ;`)

        to addState(k :Int, state):
            grow(k)
            if (!tableList[k].contains(state)):
                tableList[k] with= state
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
            def rv := [].diverge()
            for [head, rules, j, result] in tableList[position]:
                if (rules == [] && j == 0):
                    rv.push([head, result])
            return rv.snapshot()

def advance(position, token, grammar, table):
    table.queueStates(position - 1)
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
                    if (literal == token):
                        table.addState(k + 1,
                                       [head, tail, j, result.with(token)])

def makeMarley(grammar, startRule):
    def table := makeTable(grammar, startRule)
    var position :Int := 0

    return object marley:
        to finished() :Bool:
            for [head, result] in table.headsAt(position):
                if (head == startRule):
                    return true
            return false

        to results() :List:
            return [result for [head, result] in table.headsAt(position)]

        to feed(token):
            position += 1
            advance(position, token, grammar, table)

        to feedMany(tokens):
            for token in tokens:
                marley.feed(token)

def testMarleyParens(assert):
    def parens := [
        "parens" => [
            [],
            [[terminal, '('], [nonterminal, "parens"], [terminal, ')']],
        ],
    ]
    def parenParser := makeMarley(parens, "parens")
    parenParser.feedMany("((()))")
    assert.equal(parenParser.finished(), true)

def testMarleyWP(assert):
    def wp := [
        "P" => [
            [[nonterminal, "S"]],
        ],
        "S" => [
            [[nonterminal, "S"], [terminal, '+'], [nonterminal, "M"]],
            [[nonterminal, "M"]],
        ],
        "M" => [
            [[nonterminal, "M"], [terminal, '*'], [nonterminal, "T"]],
            [[nonterminal, "T"]],
        ],
        "T" => [
            [[terminal, '1']],
            [[terminal, '2']],
            [[terminal, '3']],
            [[terminal, '4']],
        ],
    ]
    def wpParser := makeMarley(wp, "P")
    wpParser.feedMany("2+3*4")
    assert.equal(wpParser.finished(), true)

unittest([testMarleyParens, testMarleyWP])

[=> makeMarley]
