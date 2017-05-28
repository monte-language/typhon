import "unittest" =~ [=> unittest]
exports (makeQuasiParser, makeMarley, ::"marley``")

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

object terminal as DeepFrozen:
    pass

object nonterminal as DeepFrozen:
    pass

# def RuleTag :DeepFrozen := Any[Same[terminal], Same[nonterminal]]
def Rule :DeepFrozen := DeepFrozen # Pair[List[Pair[RuleTag, DeepFrozen]], DeepFrozen]
def Rules :DeepFrozen := List[Rule]
def Grammar :DeepFrozen := Map[Str, Rules]


def makeTable(grammar :Grammar, tables :List[Set]) as DeepFrozen:
    return object table:
        to _printOn(out):
            out.print("Parsing table: ")
            for i => states in (tables):
                out.print(`State $i:`)
                for [head, rules, j, _, _] in (states):
                    def formattedRules := [for [_, item] in (rules) item]
                    out.print(` : $head → $formattedRules ($j) ;`)

        to _uncall():
            [makeTable, "run", [grammar, tables], [].asMap()]

        to addState(k :(0..tables.size()), state):
            return if (k == tables.size()):
                makeTable(grammar, tables.with([state].asSet()))
            else:
                def states := tables[k].with(state)
                makeTable(grammar, tables.with(k, states))

        to contains(index :(0..tables.size()), state) :Bool:
            return index < tables.size() && tables[index].contains(state)

        to get(index :(0..tables.size())) :Set:
            return if (index == tables.size()):
                [].asSet()
            else:
                tables[index]

        to getRuleNamed(rule :Str) :Rule:
            return grammar[rule]

        to headsAt(position :(0..tables.size())) :List:
            return if (position == tables.size()):
                # We have no results (yet) at this position.
                []
            else:
                def rv := [].diverge()
                for [head, rules, j, result, reduction] in (tables[position]):
                    if (rules == [] && j == 0):
                        rv.push([head, M.call(reduction, "run", result,
                                 [].asMap())])
                rv.snapshot()


def advance(position :Int, token, var table, ej) as DeepFrozen:
    def prior := position - 1
    def queue := [for state in (table[prior]) [prior, state]].diverge()
    if (queue.size() == 0):
        # The table isn't going to advance at all from this token; the parse
        # has failed.
        throw.eject(ej, "Parser cannot advance")

    def enqueue(k, state):
        if (!table.contains(k, state)):
            traceln(`table didn't have $k $state`)
            queue.push([k, state])
            table addState= (k, state)

    var heads :List[Str] := []

    while (queue.size() != 0):
        def [k, [head, rules, j, result, reduction]] := queue.pop()
        # traceln(`Twiddling $state with k $k at position $position`)
        # This switch cannot fail, since it only dispatches on the second
        # field of the state and is exhaustive.
        switch (rules):
            match []:
                # Completion.
                def reduced := M.call(reduction, "run", result, [].asMap())
                # traceln(`$reduction($result) -> $reduced`)
                for oldState in (table[j]):
                    if (oldState =~
                        [oldHead, [==[nonterminal, head]] + tail, i, tree,
                         red]):
                        # traceln(`Completed $oldHead $i..$k`)
                        enqueue(k, [oldHead, tail, i, tree.with(reduced),
                                    red])
            match [[==nonterminal, rule]] + _:
                # Prediction.
                for [production, reduction] in (table.getRuleNamed(rule)):
                    # traceln(`Predicted $rule → $production`)
                    enqueue(k, [rule, production, k, [], reduction])
            match [[==terminal, literal]] + tail:
                # Scan.
                # Scans can only take place when the token is in the position
                # immediately following the position of the scanning rule.
                if (k == prior):
                    if (literal.matches(token)):
                        # traceln(`Scanned ${M.toQuote(token)} =~ $literal`)
                        enqueue(k + 1, [head, tail, j, result.with(token),
                                        reduction])
                    else:
                        # traceln(`Failed ${M.toQuote(token)} !~ $literal`)
                        heads with= (literal.error())

    if (table[position].size() == 0):
        # Parse error: No progress was made.
        def headStrs := ", ".join(heads)
        throw.eject(ej, `Expected one of: $headStrs`)

    return table


def initialTable(grammar :Grammar, startRule :Str) as DeepFrozen:
    var startingSet := [].asSet()
    def queue := [].diverge()
    def queueRule(ruleKey):
        for [production, reduction] in (grammar[ruleKey]):
            # NB: We used to push the ruleKey into the head of the result too,
            # but we no longer do that since reductions are guaranteed to be
            # paired with each rule correctly already. ~ C.
            queue.push([ruleKey, production, 0, [], reduction])

    # Do the initial prediction.
    queueRule(startRule)
    while (queue.size() != 0):
        def rule := queue.pop()
        # traceln(`initialTable: Initially predicting rule $rule`)
        if (!startingSet.contains(rule)):
            startingSet with= (rule)
            # If nonterminal, then predict into that nonterminal's next rule.
            if (rule =~ [_, [[==nonterminal, nextRule]] + _, _, _, _]):
                queueRule(nextRule)

    def tables := [startingSet]
    return makeTable(grammar, tables)


def makeMarley(grammar :Grammar, startRule :Str) as DeepFrozen:
    var table := initialTable(grammar, startRule)
    var position :Int := 0
    var failure :NullOk[Str] := null

    return object marley:
        to getFailure() :NullOk[Str]:
            return failure

        to failed() :Bool:
            return failure != null

        to finished() :Bool:
            for [head, result] in (table.headsAt(position)):
                if (head == startRule):
                    return true
            return false

        to results() :List:
            def rv := [].diverge()
            for [head, result] in (table.headsAt(position)):
                if (head == startRule):
                    rv.push(result)
            return rv.snapshot()

        to oneResult():
            def results := marley.results()
            return switch (results):
                match [rv]:
                    rv
                match []:
                    throw(`marley.oneResult/0: Parse failed: $failure`)
                match _:
                    throw(`marley.oneResult/0: Couldn't choose one parse tree from the parse forest $results`)

        to feed(token):
            if (failure != null):
                # traceln(`Parser already failed: $failure`)
                return

            position += 1
            # traceln(`feed(${M.toQuote(token)}): Position $position, table $table`)
            escape ej:
                table := advance(position, token, table, ej)
            catch reason:
                failure := reason

        to forceFeed(token):
            "Feed and require success, or throw on failure."

            marley.feed(token)
            if (marley.failed()):
                throw(`marley.forceFeed/1: Parse failed at ${M.toQuote(token)}: $failure`)

        to feedMany(tokens):
            for token in (tokens):
                marley.feed(token)


def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
def exactly(token) as DeepFrozen implements makerAuditor:
    "Create a matcher which matches only a single `DeepFrozen` token by
     equality."

    return object exactlyMatcher as Selfless implements valueAuditor:
        to _printOn(out):
            out.print(`==${M.toQuote(token)}`)

        to _uncall():
            return serializer(exactly, [token])

        to matches(specimen) :Bool:
            return token == specimen

        to error() :Str:
            return `exactly $token`


object nullReduction as DeepFrozen:
    match [=="run", _, _]:
        null

def singleReduction(x) as DeepFrozen:
    return x

object defaultReduction as DeepFrozen:
    match [=="run", args, _]:
        args

def constant(x :DeepFrozen) as DeepFrozen:
    return object constantReduction as DeepFrozen:
        match [=="run", _, _]:
            x


def parens :Grammar := [
    "parens" => [
        [[], nullReduction],
        [[[terminal, exactly('(')], [nonterminal, "parens"],
         [terminal, exactly(')')]], nullReduction],
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
            [[[nonterminal, "S"]], singleReduction],
        ],
        "S" => [
            [[[nonterminal, "S"], [terminal, exactly('+')],
              [nonterminal, "M"]],
             def add(x, _, y) as DeepFrozen { return x + y }],
            [[[nonterminal, "M"]], singleReduction],
        ],
        "M" => [
            [[[nonterminal, "M"], [terminal, exactly('*')],
              [nonterminal, "T"]],
             def mul(x, _, y) as DeepFrozen { return x * y }],
            [[[nonterminal, "T"]], singleReduction],
        ],
        "T" => [
            [[[terminal, exactly('1')]], constant(1)],
            [[[terminal, exactly('2')]], constant(2)],
            [[[terminal, exactly('3')]], constant(3)],
            [[[terminal, exactly('4')]], constant(4)],
        ],
    ]
    def wpParser := makeMarley(wp, "P")
    wpParser.feedMany("2+3*4")
    assert.equal(wpParser.finished(), true)
    assert.equal(wpParser.results(), [14])

unittest([
    testMarleyParensFailed,
    testMarleyParensFinished,
    testMarleyParensPartial,
    testMarleyWP,
])

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

        to accept(c):
            return if (characters[pos] == c):
                scanner.advance()
                true
            else:
                false

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
                # traceln(`Scanning ${scanner.peek()}`)
                switch (scanner.nextChar()):
                    match c ? (alphanumeric.contains(c)):
                        # Identifier.
                        var s := c.asString()
                        # traceln(`Found identifier $s`)
                        while (true):
                            if (scanner.peek() =~ c ? (alphanumeric.contains(c))):
                                s += c.asString()
                                # traceln(`Now it's $s`)
                            else:
                                # traceln(`Finally, $s`)
                                return ["identifier", s]
                            scanner.advance()
                    match =='{':
                        var depth :Int := 1
                        var body := "{"
                        while (depth > 0):
                            def c := scanner.nextChar()
                            if (c == '{'):
                                depth += 1
                            else if (c == '}'):
                                depth -= 1
                            body += c.asString()
                        return ["reductionBody", ::"m``".fromStr(body)]
                    match =='>':
                        return "gt"
                    match =='<':
                        if (scanner.accept('-')):
                            return "arrowhead"
                        else:
                            return "lt"
                    match =='←':
                        return "arrowhead"
                    match =='-':
                        scanner.expect('<')
                        return "arrowtail"
                    match =='⤙':
                        return "arrowtail"
                    match =='\'':
                        var c := scanner.nextChar()
                        if (c == '\\'):
                            # Escape character.
                            c := escapeTable[scanner.nextChar()]
                        scanner.expect('\'')
                        return ["character", c]
                    match =='|':
                        return "pipe"
                    match ==':':
                        return "colon"
                    match =='$':
                        return "dollar"
                    match c:
                        throw(`scanner.nextToken/0: Can't handle ${M.toQuote(c)}`)

        to hasTokens() :Bool:
            # traceln(`Considering whether we have more tokens`)
            scanner.eatWhitespace()
            return pos < characters.size()


def tag(t :Str) as DeepFrozen:
    return object tagMatcher as DeepFrozen:
        to _uncall():
            return [tag, "run", [t], [].asMap()]

        to matches(specimen) :Bool:
            return switch (specimen) {
                match [==t, _] {true}
                match ==t {true}
                match _ {false}
            }

        to error() :Str:
            return `tag $t`


object exprHoleTag as DeepFrozen {}

object exprHole as DeepFrozen:
    to matches(specimen) :Bool:
        return specimen =~ [==exprHoleTag, _]

    to error() :Str:
        return "an expression hole"


def makeReductionFor(rule, body) as DeepFrozen:
    def patts := [for [_, binding] in (rule) {
        if (binding == null) { mpatt`_` } else {
            ::"mpatt``".fromStr(binding)
        }
    }]
    def doc := "Automatically-generated reduction"
    def meth := astBuilder."Method"(doc, "run", patts, [], null, body[1], null)
    def script := astBuilder.Script(null, [meth], [], null)
    def expr := astBuilder.ObjectExpr(doc, mpatt`reduce`, m`DeepFrozen`, [],
                                      script, null)
    def localGoodies := [
        => &&exactly,
        => &&exprHole,
        => &&terminal,
        => &&nonterminal,
        => &&makeReductionFor,
    ]
    return eval(expr, safeScope | localGoodies)

def makeEmptyList() :List as DeepFrozen:
    return []

def reduceRule(pieces, piece) :List as DeepFrozen:
    return if (piece == null) { pieces } else { pieces.with(piece) }

def rulesOnly(rules) as DeepFrozen:
    return [for [r, _] in (rules) r]

def marleyQLGrammar :Grammar := [
    "identifier" => [
        [[[terminal, tag("identifier")]],
         def reduceIdentifier([_, i]) as DeepFrozen { return i }],
    ],
    "rule" => [
        [[[terminal, tag("character")]],
         def reduceCharLiteral([_, c]) as DeepFrozen {
            return [terminal, exactly(c)]
         }],
        [[[nonterminal, "identifier"]],
         def justNonTerm(i) as DeepFrozen { return [nonterminal, i] }],
        [[[terminal, tag("dollar")]], def justExprHole(_) as DeepFrozen {
            return [terminal, exprHole]
        }],
        [[[terminal, exprHole]], singleReduction],
    ],
    "ruleBinding" => [
        [[[nonterminal, "rule"]], def noBinding(rule) as DeepFrozen {
            return [rule, null]
        }],
        [[[nonterminal, "rule"], [terminal, tag("colon")],
          [nonterminal, "identifier"]],
         def reduceRuleBinding(rule, _, binding) as DeepFrozen {
             return [rule, binding]
         }],
    ],
    "rules" => [
        [[[nonterminal, "rules"], [nonterminal, "ruleBinding"]], reduceRule],
        [[], makeEmptyList],
    ],
    "ruleSet" => [
        [[[nonterminal, "rules"]],
         def useDefaultReduction(rule) as DeepFrozen {
             return [rulesOnly(rule), defaultReduction]
         }],
        [[[nonterminal, "rules"], [terminal, tag("arrowtail")],
          [terminal, exprHole]],
         def setRuleReduction(rule, _, reduction) as DeepFrozen {
             return [rulesOnly(rule), reduction]
         }],
        [[[nonterminal, "rules"], [terminal, tag("arrowtail")],
          [terminal, tag("reductionBody")]],
         def buildRuleReduction(rule, _, body) as DeepFrozen {
             return [rulesOnly(rule), makeReductionFor(rule, body)]
         }],
    ],
    "ruleSets" => [
        [[[nonterminal, "ruleSets"], [terminal, tag("pipe")],
          [nonterminal, "ruleSet"]],
         def reduceRuleSet(ruleSets, _, ruleSet) as DeepFrozen {
             return ruleSets.with(ruleSet)
         }],
        [[[nonterminal, "ruleSet"]], defaultReduction],
    ],
    "production" => [
        [[[nonterminal, "identifier"], [terminal, tag("arrowhead")],
          [nonterminal, "ruleSets"]],
         def reduceProduction(head, _, ruleSets) as DeepFrozen {
             return [head => ruleSets]
         }],
    ],
    "grammar" => [
        [[[nonterminal, "grammar"], [nonterminal, "production"]],
         def reduceGrammar(g, p) as DeepFrozen { return g | p }],
        [[[nonterminal, "production"]], singleReduction],
    ],
]


def makeQuasiParser(scannerMaker :DeepFrozen, grammar :Grammar,
                    startRule :Str, name :Str) as DeepFrozen:
    return object quasiParser as DeepFrozen:
        to _printOn(out):
            out.print(`<$name````>`)

        to valueHole(index :Int):
            return [exprHoleTag, index]

        to valueMaker(pieces):
            def parser := makeMarley(grammar, startRule)

            for piece in (pieces):
                if (piece =~ [==exprHoleTag, index :Int]):
                    # Pre-scanned for us.
                    parser.forceFeed(piece)
                else:
                    def scanner := scannerMaker(piece)
                    while (scanner.hasTokens()):
                        def token := scanner.nextToken()
                        # traceln(`Next token: $token`)
                        # traceln(`Parser: ${parser.getFailure()}`)
                        parser.forceFeed(token)

            def grammar :Grammar := parser.oneResult()
            return object ruleSubstituter:
                to substitute(_):
                    return object marleyMaker:
                        to run(startRule :Str):
                           return makeMarley(grammar, startRule)

                        to getGrammar() :Grammar:
                            return grammar

def ::"marley``" :DeepFrozen := makeQuasiParser(makeScanner, marleyQLGrammar,
                                                "grammar", "marley")

def marleyInMarley :Grammar := marley`
    identifier ← ${tag("identifier")}:i ⤙ { i[1] }
    rule ← ${tag("character")}:c ⤙ { [terminal, exactly(c[1])] }
         | identifier:i ⤙ { [nonterminal, i] }
         | '$$' ⤙ { [terminal, exprHole] }
         | $$
    rules ← rules:rs rule:r ⤙ { if (r == null) { rs } else { rs.with(r) } }
          |
    ruleSet ← rules:r ⤙ { [r, makeReductionFor(r)] }
            | rules:r ${tag("arrowtail")} $$:red ⤙ { [r, red] }
    ruleSets ← ruleSets:rss ${tag("pipe")} ruleSet:rs ⤙ { rss.with(rs) }
             | ruleSet:rs ⤙ { [rs] }
    production ← identifier:i ${tag("arrowhead")} ruleSets:rss ⤙ {
        [i[1] => rss]
    }
    grammar ← grammar:g production:p ⤙ { g | p }
            | production
`.getGrammar()

traceln(marleyInMarley)


def testMarleyQPSingle(assert):
    def handwritten :Grammar := [
        "breakfast" => [
            [[[nonterminal, "eggs"], [terminal, exactly('&')],
              [nonterminal, "bacon"]], defaultReduction]
        ]
    ]
    def generated :Grammar := marley`breakfast ← eggs '&' bacon`.getGrammar()
    assert.equal(handwritten, generated)

def testMarleyQPEmpty(assert):
    def handwritten :Grammar := [
        "empty" => [[[], nullReduction]],
        "nonempty" => [[[[nonterminal, "empty"]], singleReduction]],
    ]
    def generated :Grammar := marley`
        empty ←
        nonempty ← empty
    `.getGrammar()
    assert.equal(handwritten, generated)

def testMarleyQPAlt(assert):
    def handwritten :Grammar := [
        "breakfast" => [
            [[[nonterminal, "eggs"]], singleReduction],
            [[[nonterminal, "bacon"]], singleReduction]
        ]
    ]
    def generated :Grammar := marley`breakfast ← eggs | bacon`.getGrammar()
    assert.equal(handwritten, generated)

unittest([
    testMarleyQPSingle,
    testMarleyQPEmpty,
    testMarleyQPAlt,
])
