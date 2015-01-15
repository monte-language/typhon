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

def Bool := boolean
def Int := int
def String := str

def parseMonte(tokens, ej):
    # An ejection means failed parse. It'll generally come with some sort of
    # error report.

    def iterator := tokens._makeIterator()
    var token := null

    object monteParser:
        to current():
            return token

        to next():
            token := iterator.next(ej)[1]
            return token

        to expression(rbp :Int):
            # traceln(`expr $rbp`)
            var t := token    
            monteParser.next()
            var left := t.nud(monteParser)
            # traceln(`left of $t is $left`)
            while (rbp < token.lbp()):
                t := token
                monteParser.next()
                left := t.led(monteParser, left)
                # traceln(`left of $t is $left`)
            return left

        to expr():
            return monteParser.expression(0)

        to pattern(rbp :Int):
            # traceln(`patt`)
            var t := token
            monteParser.next()
            var left := t.nup(monteParser)
            # traceln(`left of $t is $left`)
            while (rbp < token.pbp()):
                t := token
                monteParser.next()
                left := t.lep(monteParser, left)
                # traceln(`left of $t is $left`)
            return left

        to patt():
            return monteParser.pattern(0)

        to noun():
            if (token.label() == "noun"):
                def rv := token.noun()
                monteParser.next()
                return rv
            monteParser.error(`expected noun, not $token`)

        to advance(t, err):
            if (t != token):
                monteParser.error(err)
            monteParser.next()

        to choose(t) :Bool:
            "If `t` is the current token, commit to it and advance."
            if (t == token):
                monteParser.next()
                return true
            return false

        to error(err):
            throw.eject(ej, [err, token])

    # Prime the parser.
    token := monteParser.next()
    return monteParser

# Declare some tokens.

def closeParen
def openBracket
def openParen
def colon
def dot

# Core stuff.

object token:
    to label():
        return "token"

    to lbp():
        return 0

    to nud(parser):
        parser.error("Invalid start of expression")

    to led(parser, left):
        parser.error("Invalid mid-expression token")

    to pbp():
        return 0

    to nup(parser):
        parser.error("Invalid start of pattern")

    to lep(parser, left):
        parser.error("Invalid mid-pattern token")

object end extends token:
    to lbp():
        return 0
    to pbp():
        # Mostly just for testing purposes.
        return 0

def literal(value):
    return object literalToken extends token:
        to label():
            return "literal"

        to nud(parser):
            return term`LiteralExpr($value)`

# Comma and combinator.

object comma extends token:
    pass

def commaSep(parser, action, terminal):
    "Consume zero or more comma-separated items with optional trailing comma."
    if (parser.choose(terminal)):
        # Zero case; there are no items to consume. Hooray!
        return []

    var rv := []
    while (true):
        rv := rv.with(action(parser))
        if (!parser.choose(comma)):
            # We have no more trailing commas. We must consume the terminal.
            # XXX should we include the terminal name in the error message?
            parser.advance(terminal,
                "Expected comma-separated item or end symbol")
            return rv

# Tokens and helpers for blocks.

object closeBrace extends token:
    pass

object openBrace extends token:
    to nud(parser):
        if (parser.choose(closeBrace)):
            # Empty hide expression. Legal and often an alternative to pass.
            return term`HideExpr(SeqExpr([]))`
        def expr := parser.expr()
        parser.advance(closeBrace, "Runaway hide expression")
        return term`HideExpr($expr)`

object indent extends token:
    pass

object dedent extends token:
    pass

def block(parser):
    if (parser.choose(colon)):
        parser.advance(indent, "colon implies indented block")
        def body := parser.expr()
        parser.advance(dedent, "didn't dedent after indented block")
        return body
    else:
        parser.advance(openBrace, "block body must be inside braces")
        def body := parser.expr()
        parser.advance(closeBrace,
            "runaway block body; expected closing brace")
        return body

# Guards.

object closeBracket extends token:
    pass

def guard(parser):
    def g := if (parser.choose(openParen)) {
        def expr := parser.expr()
        parser.advance(closeParen, "Guard expression not terminated")
        expr
    } else {
        def expr := parser.current().term()
        parser.next()
        expr
    }
    def ps := if (parser.choose(openBracket)) {
        commaSep(parser, fn p {p.expr()}, closeBracket)
    } else {
        []
    }
    return term`Guard($g, $ps)`

bind colon extends token:
    to lbp():
        return 15

    to led(parser, left):
        def g := guard(parser)
        return term`Coerce($left, $g)`

42

# QLs.

object backtick extends token:
    to nup(parser):
        var pieces := []
        while (!parser.choose(backtick)):
            def piece := parser.next().nud(parser)
            if (piece =~ term`LiteralExpr(@lit)`):
                pieces := pieces.with(term`QuasiText($lit)`)
        return term`QuasiPattern(null, $pieces)`

def noun(value):
    return object nounToken extends token:
        to label():
            return "noun"

        to noun():
            return value

        to term():
            return term`NounExpr($value)`

        to nud(parser):
            if (value == "meta"):
                # It's time for meta! Who likes meta? We like meta! I think.
                parser.advance(dot, "meta expression should start 'meta.'")
                def metaNoun := parser.noun()
                def metaType := switch (metaNoun) {
                    match =="getState" {"State"}
                    match =="scope" {"Scope"}
                    match =="context" {"Context"}
                }
                parser.advance(openParen, "meta expression can't be curried")
                parser.advance(closeParen,
                    "meta expression takes no arguments")
                return term`Meta($metaType)`

            return nounToken.term()

        to pbp():
            return 5

        to nup(parser):
            if (parser.choose(backtick)):
                def term`QuasiPattern(null, @pieces)` := backtick.nup(parser)
                return term`QuasiPattern(NounExpr($value), $pieces)`
            else if (parser.choose(colon)):
                # Looks like there's a guard.
                def g := guard(parser)
                if (value == "_"):
                    return term`IgnorePattern($g)`
                return term`FinalPattern(NounExpr($value), $g)`
            if (value == "_"):
                return term`IgnorePattern(null)`
            return term`FinalPattern(NounExpr($value), null)`

bind closeParen extends token:
    pass

42

bind openParen extends token:
    to lbp():
        return 15

    to nud(parser):
        def rv := parser.expr()
        parser.advance(closeParen, "XXX not finished")
        return rv

    to led(parser, left):
        # Call.
        var args := commaSep(parser, fn p {p.expr()}, closeParen)
        # Methods are not parsed as such; stitch curried verbs and function
        # calls together into method calls.
        if (left =~ term`VerbCurryExpr(@target, @verb)`):
             return term`MethodCallExpr($target, $verb, $args)`
        return term`FunctionCallExpr($left, $args)`

42

# Current tentative tower for patterns:
# 1, na: Such-that.
# 2, ri: Lists, maps.
# 3, na: Exact-match.
# 4, na: QLs.
# 5, na: Namers.

object question extends token:
    to pbp():
        return 1

    to lep(parser, left):
        parser.advance(openParen, "Such-that pattern requires parentheses")
        def right := parser.expr()
        parser.advance(closeParen, "Runaway such-that pattern")
        return term`SuchThatPattern($left, $right)`

# Since none of us have them memorized:
# 1, dc: Sequences.
# 2, dc: Semicolons.
# 3, ri: Assignment, augmented assignment, define.
# 4, dc: OR.
# 5, dc: AND.
# 6, na: Equality, bitwise, pattern match.
# 7, na: Ordering.
# 8, na: Interval.
# 9, le: Shift.
# 10, le: Addition, subtraction.
# 11, le: Multiplication, division, modulus, modular exponentation.
# 12, ri: Exponentation.
# 13, na: Unary prefix.
# 14, le: Indexing, send.
# 15, le: Coercion.
# 16, le: Call.

object colonEqual extends token:
    to lbp():
        return 3

    to led(parser, left):
        def right := parser.expression(3 - 1)
        return term`Assign($left, $right)`

object kwExit extends token:
    pass

object kwDef extends token:
    # Definitions are right-associative.
    to nud(parser):
        def patt := parser.patt()
        var ej := null
        if (parser.choose(kwExit)):
            # Only things that bind tighter than assignment are permitted as
            # ejectors.
            ej := parser.expression(4)
        parser.advance(colonEqual, "Runaway pattern")
        def right := parser.expression(2)
        return term`Def($patt, $ej, $right)`

object starStar extends token:
    # Exponentation is right-associative, which is a rare thing indeed.
    to lbp():
        return 12

    to led(parser, left):
        def right := parser.expression(12 - 1)
        return term`Pow($left, $right)`

def leftBin(tag, lbp :Int):
    return object leftBinaryOp extends token:
        to _printOn(out):
            out.print(`<left-associative $tag>`)

        to lbp():
            return lbp

        to led(parser, left):
            def right := parser.expression(lbp)
            return term`$tag($left, $right)`

        to nup(parser):
            parser.error(`Tried to find pattern, but found binary operator $tag`)

def newline := leftBin("SeqExpr", 1)
def semicolon := leftBin("SeqExpr", 2)
def pipePipe := leftBin("LogicalOr", 4)
def gtGt := leftBin("ShiftRight", 9)
def ltLt := leftBin("ShiftLeft", 9)
def plus := leftBin("Add", 10)
def percent := leftBin("Mod", 11)
def slash := leftBin("Divide", 11)
def slashSlash := leftBin("FloorDivide", 11)
def star := leftBin("Multiply", 11)

def unary(tag, bp :Int):
    return object unaryOp extends token:
        to _printOn(out):
            out.print(`<unary $tag>`)

        to nud(parser):
            def expr := parser.expression(bp)
            return term`$tag($expr)`

def bang := unary("LogicalNot", 13)
def tilde := unary("BinaryNot", 13)

# This requires more thought. Lots more thought.
def nonAssoc := leftBin

def ampBang := nonAssoc("ButNot", 6)
def carat := nonAssoc("BinaryXor", 6)
def gt := nonAssoc("GreaterThan", 6)
def gtEqual := nonAssoc("GreaterThanEqual", 6)
def lt := nonAssoc("LessThan", 6)
def ltEqual := nonAssoc("LessThanEqual", 6)
def pipe := nonAssoc("BinaryOr", 6)
def spaceship := nonAssoc("AsBigAs", 6)
def dotDot := nonAssoc("Thru", 8)
def dotDotBang := nonAssoc("Till", 8)

# Comparative patterns.

object bangEqual extends token:
    to lbp():
        return 6

    to led(parser, left):
        def right := parser.expression(6)
        # XXX assert that left is not a conflicting operator
        return term`NotSame($left, $right)`

    to nup(parser):
        def expr := parser.expr()
        return term`NotSamePattern($expr)`

object equalEqual extends token:
    to lbp():
        return 6

    to led(parser, left):
        def right := parser.expression(6)
        # XXX assert that left is not a conflicting operator
        return term`Same($left, $right)`

    to nup(parser):
        def expr := parser.expr()
        return term`SamePattern($expr)`

# These two have expressions on the left and patterns on the right.

object bangTilde extends token:
    to lbp():
        return 6

    to led(parser, left):
        def right := parser.patt()
        return term`Mismatch($left, $right)`

object equalTilde extends token:
    to lbp():
        return 6

    to led(parser, left):
        def right := parser.patt()
        return term`MatchBind($left, $right)`

# These symbols can all code for either prefix or infix operators.

object amp extends token:
    to lbp():
        return 6

    to nud(parser):
        def expr := parser.expression(13)
        return term`SlotExpr($expr)`

    to led(parser, left):
        def right := parser.expression(6)
        return term`BinaryAnd($left, $right)`

    to nup(parser):
        def name := parser.current().term()
        parser.next()
        if (parser.choose(colon)):
            # Binds can have guards too.
            def g := guard(parser)
            return term`SlotPattern($name, $g)`
        return term`SlotPattern($name, null)`

object ampAmp extends token:
    to lbp():
        return 5

    to nud(parser):
        def expr := parser.expression(13)
        return term`BindingExpr($expr)`

    to led(parser, left):
        def right := parser.expression(5)
        return term`LogicalAnd($left, $right)`

    to nup(parser):
        def name := parser.current().term()
        parser.next()
        if (parser.choose(colon)):
            # Binds can have guards too.
            def g := guard(parser)
            return term`BindingPattern($name, $g)`
        return term`BindingPattern($name, null)`

object minus extends token:
    to lbp():
        return 10
    to nud(parser):
        def expr := parser.expression(13)
        return term`Minus($expr)`
    to led(parser, left):
        def right := parser.expression(10)
        return term`Subtract($left, $right)`

# If/else.

object kwElse extends token:
    pass

object kwIf extends token:
    to nud(parser):
        parser.advance(openParen,
            "if expression's condition must be parenthesized")
        def condition := parser.expr()
        parser.advance(closeParen, "runaway if expression condition")
        def consequent := block(parser)
        def alternative := if (parser.choose(kwElse)) {block(parser)}
        return term`If($condition, $consequent, $alternative)`

# For loops.

object kwIn extends token:
    pass

object kwFor extends token:
    pass

# Lists and maps.

object fatArrow extends token:
    pass

bind openBracket extends token:
    to lbp():
        return 14

    to nud(parser):
        # The listlike expressions all start with an open bracket and an
        # expression. The token after the expression determines what kind of
        # expression it will be:
        # ~ Fat arrow: Map expression or map comprehension
        # ~ Comma: List expression
        # ~ Keyword for: List comprehension

        # The special zero case.
        if (parser.choose(closeBracket)):
            return term`ListExpr([])`

        # List expression needs a list.
        var args := []

        # Now, grab the first item, and then look ahead for a fat arrow to see
        # if we should switch to map mode.
        # XXX this is where a list comprehension or map comprehension would be
        # detected.
        var mapMode :Bool := false
        def item := parser.expr()
        # Let's try to complete list comprehensions first. They're relatively
        # simple.
        if (parser.choose(kwFor)):
            var keyPatt := parser.patt()
            def valuePatt := if (parser.choose(fatArrow)) {
                # [... for k => v in ...]
                parser.patt()
            } else {
                # [... for v in ...]
                def temp := keyPatt
                keyPatt := null
                temp
            }
            parser.advance(kwIn, "list comprehension requires 'in'")
            # [ ... for ... in expr]
            def l := parser.expr()
            # [ ... for ... in ... if condition]
            def c := if (parser.choose(kwIf)) {parser.expr()} else {null}
            # Cap it off and return.
            parser.advance(closeBracket, "Runaway list comprehension")
            return term`ListComp($keyPatt, $valuePatt, $l, $c, $item)`
        else if (parser.choose(fatArrow)):
            mapMode := true
            def value := parser.expr()
            args := args.with(term`MapExprAssoc($item, $value)`)
        else:
            args := args.with(item)

        # And finish the single-arg case.
        if (!parser.choose(comma)):
            parser.advance(closeBracket, "Runaway list/map expression")
            if (mapMode):
                return term`MapExpr($args)`
            else:
                return term`ListExpr($args)`

        # Now, the general two-or-more case.
        while (!parser.choose(closeBracket)):
            if (mapMode):
                # If the next token is a fat arrow, then choose an export
                # expression and continue.
                if (parser.choose(fatArrow)):
                    def expr := parser.expr()
                    args := args.with(term`MapExprExport($expr)`)
                else:
                    def key := parser.expr()
                    parser.advance(fatArrow,
                        "Fat arrow expected for map expression")
                    def value := parser.expr()
                    args := args.with(term`MapExprAssoc($key, $value)`)
            else:
                args := args.with(parser.expr())

            # Try to eat a comma. If we can't eat a comma, then there can't be
            # any more items, so it's time to return. This includes a partial
            # unroll of the while loop's condition.
            if (!parser.choose(comma)):
                if (mapMode):
                    parser.advance(closeBracket, "Runaway map expression")
                    return term`MapExpr($args)`
                else:
                    parser.advance(closeBracket, "Runaway list expression")
                    return term`ListExpr($args)`

    to led(parser, left):
        # At current, get expressions only permit lists of arguments, due to
        # the message-passing convention not permitting keyword arguments.
        # This will probably change in the future.
        # We require one-or-more arguments to get expressions, not
        # zero-or-more.
        def args := commaSep(parser, fn p {p.expr()}, closeBracket)
        return term`GetExpr($left, $args)`

    to nup(parser):
        # XXX should also do map patterns
        def patts := commaSep(parser, fn p {p.patt()}, closeBracket)
        def tail := if (parser.choose(plus)) {parser.patt()} else {null}
        return term`ListPattern($patts, $tail)`

42

# And some other uncategorized stuff.

bind dot extends token:
    to lbp():
        return 14

    to led(parser, left):
        var right := parser.expression(15)
        return term`VerbCurryExpr($left, $right)`

42

object leftArrow extends token:
    to lbp():
        return 13

    to led(parser, left):
        var right := parser.expression(15)
        return term`SendCurryExpr($left, $right)`

object kwVia extends token:
    to nup(parser):
        parser.advance(openParen, "via expression must have parentheses")
        def expr := parser.expr()
        parser.advance(closeParen, "Runaway via expression")
        def patt := parser.patt()
        return term`ViaPattern($expr, $patt)`

object kwBind extends token:
    to nup(parser):
        def name := parser.current().term()
        parser.next()
        if (parser.choose(colon)):
            # Binds can have guards too.
            def g := guard(parser)
            return term`BindPattern($name, $g)`
        return term`BindPattern($name, null)`

object kwVar extends token:
    to nup(parser):
        def name := parser.current().term()
        parser.next()
        if (parser.choose(colon)):
            # Looks like there's a guard.
            def g := guard(parser)
            return term`VarPattern($name, $g)`
        return term`VarPattern($name, null)`

# break, continue, and return.

def brc(tag :String, parser):
    # Don't bind across semicolons; this means a power of three.
    switch (parser.current()):
        match ==end:
            return term`$tag(null)`
        match ==semicolon:
            return term`$tag(null)`
        match ==newline:
            return term`$tag(null)`
        match ==openParen:
            # Since the parens can technically be empty, we should consume
            # the paren, and then an expression, and then the close paren.
            # This gives us a chance to peek for the close paren early.
            parser.advance(openParen, "Implementation error")
            if (parser.choose(closeParen)):
                return term`$tag(null)`
            def expr := parser.expr()
            parser.advance(closeParen, "Runaway expression after return")
            return term`$tag($expr)`
        match _:
            def expr := parser.expr()
            return term`$tag($expr)`

object kwBreak extends token:
    to nud(parser):
        return brc("Break", parser)

object kwContinue extends token:
    to nud(parser):
        return brc("Continue", parser)

object kwReturn extends token:
    to nud(parser):
        return brc("Return", parser)

# Functions.

object kwFn extends token:
    to nud(parser):
        var args := []
        while (!parser.choose(openBrace)):
            # Grab another argument pattern.
            args := args.with(parser.patt())
            if (!parser.choose(comma)):
                # No more patterns can follow; we need to start the lambda.
                parser.advance(openBrace, "fns must be enclosed in braces")
                break
        def body := parser.expr()
        parser.advance(closeBrace, "runaway fn is missing closing brace")
        return term`Lambda(null, $args, $body)`

# While loops.

object kwWhile extends token:
    to nud(parser):
        parser.advance(openParen, "while condition must be parenthesized")
        def cond := parser.expr()
        parser.advance(closeParen, "runaway condition in while loop")
        def body := block(parser)
        return term`While($cond, $body, null)`

# When exprs.

object slimArrow extends token:
    pass

object kwWhen extends token:
    to nud(parser):
        parser.advance(openParen, "when objects must be parenthesized")
        def target := parser.expr()
        parser.advance(closeParen, "runaway object list in when expression")
        parser.advance(slimArrow, "slim arrow required in when expression")
        # We can't use the block() combinator because when-exprs don't have
        # colons and I don't want to specialize block() for this single case.
        if (parser.choose(openBrace)):
            def body := parser.expr()
            parser.advance(closeBrace,
                "runaway when expression body; expected closing brace")
            return term`When([$target], $body, [], null)`
        else:
            parser.advance(indent,
                "when expression's block must be indented or braced")
            def body := parser.expr()
            parser.advance(dedent, "didn't dedent after indented block")
            return term`When([$target], $body, [], null)`

# Tests.

def testParse(tokens, expected):
    escape ej:
        def result := parseMonte(tokens + [end], ej).expr()
        if (result != expected):
            traceln(`Not equal: $result != $expected`)
    catch err:
        traceln(`Failure: $err`)
        traceln(`Failing tokens: $tokens`)

def testPatt(tokens, expected):
    escape ej:
        def result := parseMonte(tokens + [end], ej).patt()
        if (result != expected):
            traceln(`Not equal: $result != $expected`)
    catch err:
        traceln(`Failure: $err`)
        traceln(`Failing tokens: $tokens`)

def testLiteral():
    testParse([literal("foo bar")], term`LiteralExpr("foo bar")`)
    testParse([literal('z')], term`LiteralExpr('z')`)
    testParse([literal(7)], term`LiteralExpr(7)`)
    testParse([literal(0.91)], term`LiteralExpr(0.91)`)

def testNoun():
    testParse([noun("foo")], term`NounExpr("foo")`)
    # XXX should URIGetter be tested here?

def testCollections():
    testParse([openBracket, closeBracket], term`ListExpr([])`)
    testParse([openBracket, literal(1), comma, noun("a"), closeBracket],
        term`ListExpr([LiteralExpr(1), NounExpr("a")])`)
    testParse([openBracket,
            literal(1), fatArrow, noun("a"), comma,
            literal(2), fatArrow, noun("b"), closeBracket],
        term`MapExpr([MapExprAssoc(LiteralExpr(1), NounExpr("a")), MapExprAssoc(LiteralExpr(2), NounExpr("b"))])`)
    testParse([openBracket,
            literal(1), fatArrow, noun("a"), comma,
            fatArrow, amp, noun("x"), comma,
            fatArrow, noun("y"), comma, closeBracket],
        term`MapExpr([MapExprAssoc(LiteralExpr(1), NounExpr("a")), MapExprExport(SlotExpr(NounExpr("x"))), MapExprExport(NounExpr("y"))])`)

def testBody():
    testParse([openBrace, literal(1), closeBrace],
        term`HideExpr(LiteralExpr(1))`)
    testParse([openBrace, closeBrace], term`HideExpr(SeqExpr([]))`)

def testCall():
    testParse([noun("x"), dot, noun("y"), openParen, closeParen],
        term`MethodCallExpr(NounExpr(x), "y", [])`)
    testParse([noun("x"), dot, noun("y")],
        term`VerbCurryExpr(NounExpr(x), "y")`)
    testParse([noun("x"), openParen, closeParen],
        term`FunctionCallExpr(NounExpr(x), [])`)
    testParse([openBrace, literal(1), closeBrace, dot, noun("x"), openParen, closeParen],
        term`MethodCallExpr(HideExpr(LiteralExpr(1)), "x", [])`)
    testParse([noun("x"), openParen, noun("a"), comma, noun("b"), closeParen],
        term`FunctionCallExpr(NounExpr(x), [NounExpr(a), NounExpr(b)])`)
    testParse([noun("x"), dot, noun("foo"), openParen, noun("a"), comma, noun("b"), closeParen],
        term`MethodCallExpr(NounExpr(x), "foo", [NounExpr(a), NounExpr(b)])`)
    testParse([noun("x"), openParen, noun("a"), comma, noun("b"), closeParen],
        term`FunctionCallExpr(NounExpr(x), [NounExpr(a), NounExpr(b)])`)
    testParse([noun("x"), leftArrow, openParen, noun("a"), comma, noun("b"), closeParen],
        term`FunctionSendExpr(NounExpr(x), [NounExpr(a), NounExpr(b)])`)
    testParse([noun("x"), leftArrow, noun("foo"), openParen, noun("a"), comma, noun("b"), closeParen],
        term`MethodSendExpr(NounExpr(x), "foo", [NounExpr(a), NounExpr(b)])`)
    testParse([noun("x"), leftArrow, noun("foo")],
        term`SendCurryExpr(NounExpr(x), "foo")`)
    testParse([noun("x"), openBracket, noun("a"), comma, noun("b"), closeBracket],
        term`GetExpr(NounExpr("x"), [NounExpr("a"), NounExpr("b")])`)
    testParse([noun("x"), openBracket, noun("a"), comma, noun("b"), closeBracket, dot, noun("foo"), openParen, noun("c"), closeParen],
        term`MethodCallExpr(GetExpr(NounExpr("x"), [NounExpr("a"), NounExpr("b")]), "foo", [NounExpr("c")])`)

def testPrefix():
    testParse([bang, noun("x"), dot, noun("a"), openParen, closeParen],
        term`LogicalNot(MethodCallExpr(NounExpr("x"), "a", []))`)
    testParse([tilde, literal(17)], term`BinaryNot(LiteralExpr(17))`)
    testParse([amp, noun("x")], term`SlotExpr(NounExpr("x"))`)
    testParse([ampAmp, noun("x")], term`BindingExpr(NounExpr("x"))`)
    testParse([minus, openParen, literal(3), dot, noun("pow"), openParen, literal(2), closeParen, closeParen],
        term`Minus(MethodCallExpr(LiteralExpr(3), "pow", [LiteralExpr(2)]))`)

def testPattern():
    testPatt([noun("a")], term`FinalPattern(NounExpr("a"), null)`)
    testPatt([openBracket, closeBracket], term`ListPattern([], null)`)
    testPatt([openBracket, noun("a"), closeBracket],
        term`ListPattern([FinalPattern(NounExpr("a"), null)], null)`)
    testPatt([openBracket, noun("a"), comma, noun("b"), closeBracket],
        term`ListPattern([FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], null)`)
    testPatt([openBracket, noun("a"), closeBracket, plus, noun("b")],
        term`ListPattern([FinalPattern(NounExpr("a"), null)], FinalPattern(NounExpr("b"), null))`)
    testPatt([openBracket, literal("a"), fatArrow, noun("aa"), comma,
            openParen, noun("b"), closeParen, fatArrow, noun("bb"),
            closeBracket],
        term`MapPattern([
            MapPatternRequired(MapPatternAssoc(LiteralExpr("a"), FinalPattern(NounExpr("aa"), null))),
            MapPatternRequired(MapPatternAssoc(NounExpr("b"), FinalPattern(NounExpr("bb"), null)))],
            null)`)
    testPatt([openBracket, literal("a"), fatArrow, noun("aa"), colonEqual, literal(1), closeBracket],
        term`MapPattern([
            MapPatternOptional(MapPatternAssoc(LiteralExpr("a"), FinalPattern(NounExpr("aa"), null)), LiteralExpr(1))],
            null)`)
    testPatt([openBracket, fatArrow, noun("aa"), colonEqual, literal(1), closeBracket],
        term`MapPattern([
            MapPatternOptional(MapPatternImport(FinalPattern(NounExpr("aa"), null)), LiteralExpr(1))],
            null)`)
    testPatt([openBracket, fatArrow, noun("a"), closeBracket],
        term`MapPattern([MapPatternRequired(MapPatternImport(FinalPattern(NounExpr("a"), null)))],
        null)`)
    testPatt([openBracket, literal("a"), fatArrow, noun("b"), closeBracket,
            pipe, noun("c")],
        term`MapPattern([MapPatternRequired(MapPatternAssoc, LiteralExpr("a"), FinalPattern(NounExpr("b"), null))],
        FinalPattern(NounExpr("c"), null))`)
    testPatt([noun("_")], term`IgnorePattern(null)`)
    testPatt([noun("__foo")], term`FinalPattern(NounExpr("__foo"), null)`)
    testPatt([noun("a"), colon, noun("int")],
        term`FinalPattern(NounExpr("a"), Guard(NounExpr("int"), []))`)
    testPatt([noun("a"), colon, noun("list"), openBracket, noun("int"), closeBracket],
        term`FinalPattern(NounExpr("a"), Guard(NounExpr("list"), [[NounExpr("int")]]))`)
    testPatt([backtick, literal("foo"), backtick],
        term`QuasiPattern(null, [QuasiText("foo")])`)
    testPatt([noun("baz"), backtick, literal("foo"), backtick],
        term`QuasiPattern("baz", [QuasiText("foo")])`)
    testPatt([equalEqual, literal(1)], term`SamePattern(LiteralExpr(1))`)
    testPatt([equalEqual, noun("x")], term`SamePattern(NounExpr("x"))`)
    testPatt([bangEqual, noun("x")], term`NotSamePattern(NounExpr("x"))`)
    testPatt([kwVar, noun("x")], term`VarPattern(NounExpr("x"), null)`)
    testPatt([kwBind, noun("y")], term`BindPattern(NounExpr("y"), null)`)
    testPatt([amp, noun("z")], term`SlotPattern(NounExpr("z"), null)`)
    testPatt([ampAmp, noun("z")], term`BindingPattern(NounExpr("z"), null)`)
    testPatt([kwVar, noun("x"), colon, noun("int")],
        term`VarPattern(NounExpr("x"), Guard(NounExpr("int"), []))`)
    testPatt([kwBind, noun("y"), colon, noun("float64")],
        term`BindPattern(NounExpr("y"), Guard(NounExpr("float64"), []))`)
    testPatt([amp, noun("z"), colon, noun("Foo")],
        term`SlotPattern(NounExpr("z"), Guard(NounExpr("Foo"), []))`)
    testPatt([kwVia, openParen, noun("foo"), closeParen, openBracket, noun("x"), closeBracket],
        term`ViaPattern(NounExpr("foo"), ListPattern([FinalPattern(NounExpr("x"), null)], null))`)
    testPatt([noun("x"), question, openParen, noun("y"), closeParen],
        term`SuchThatPattern(FinalPattern(NounExpr("x"), null), NounExpr("y"))`)

def testMatch():
    testParse([noun("x"), equalTilde, openBracket, noun("a"), comma, noun("b"), closeBracket],
        term`MatchBind(NounExpr("x"),
            ListPattern([FinalPattern(NounExpr("a"), null), FinalPattern(NounExpr("b"), null)], null))`)
    testParse([noun("x"), bangTilde, noun("y"), colon, noun("String")],
        term`Mismatch(NounExpr("x"), FinalPattern(NounExpr("y"), Guard(NounExpr("String"), [])))`)

def testOperators():
    testParse([noun("x"), starStar, minus, noun("y")],
        term`Pow(NounExpr("x"), Minus(NounExpr("y")))`)
    testParse([noun("x"), star, noun("y")],
        term`Multiply(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), slash, noun("y")],
        term`Divide(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), slashSlash, noun("y")],
        term`FloorDivide(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), percent, noun("y")],
        term`Mod(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), plus, noun("y")],
        term`Add(NounExpr("x"), NounExpr("y"))`)
    testParse([openParen, noun("x"), plus, noun("y"), closeParen, plus, noun("z")],
        term`Add(Add(NounExpr("x"), NounExpr("y")), NounExpr("z"))`)
    testParse([literal(1), plus, literal(1)],
        term`Add(LiteralExpr(1), LiteralExpr(1))`)
    testParse([noun("x"), minus, noun("y")],
        term`Subtract(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), minus, noun("y"), plus, noun("z")],
        term`Add(Subtract(NounExpr("x"), NounExpr("y")), NounExpr("z"))`)
    testParse([noun("x"), dotDot, noun("y")],
        term`Thru(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), dotDotBang, noun("y")],
        term`Till(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), lt, noun("y")],
        term`LessThan(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), ltEqual, noun("y")],
        term`LessThanEqual(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), spaceship, noun("y")],
        term`AsBigAs(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), gtEqual, noun("y")],
        term`GreaterThanEqual(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), gt, noun("y")],
        term`GreaterThan(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), colon, noun("y")],
        term`Coerce(NounExpr("x"), Guard(NounExpr("y"), []))`)
    testParse([noun("x"), colon, noun("y"), openBracket, noun("z"), comma, noun("a"), closeBracket],
        term`Coerce(NounExpr("x"), Guard(NounExpr("y"), [NounExpr("z"), NounExpr("a")]))`)
    testParse([noun("x"), ltLt, noun("y")],
        term`ShiftLeft(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), gtGt, noun("y")],
        term`ShiftRight(NounExpr("x"), NounExpr("y"))`)
    #self.assertEqual(parse("x << y >> z"), ["ShiftRight", ["ShiftLeft", ["NounExpr", "x"], ["NounExpr", "y"]], ["NounExpr", "z"]])
    testParse([noun("x"), equalEqual, noun("y")],
        term`Same(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), bangEqual, noun("y")],
        term`NotSame(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), ampBang, noun("y")],
        term`ButNot(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), carat, noun("y")],
        term`BinaryXor(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), amp, noun("y")],
        term`BinaryAnd(NounExpr("x"), NounExpr("y"))`)
    #self.assertEqual(parse("x & y & z"), ["BinaryAnd", ["BinaryAnd", ["NounExpr", "x"], ["NounExpr", "y"]], ["NounExpr", "z"]])
    testParse([noun("x"), pipe, noun("y")],
        term`BinaryOr(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), pipe, noun("y")],
        term`BinaryOr(NounExpr("x"), NounExpr("y"))`)
    #self.assertEqual(parse("x | y | z"), ["BinaryOr", ["BinaryOr", ["NounExpr", "x"], ["NounExpr", "y"]], ["NounExpr", "z"]])
    testParse([noun("x"), ampAmp, noun("y")],
        term`LogicalAnd(NounExpr("x"), NounExpr("y"))`)
    #self.assertEqual(parse("x && y && z"), ["LogicalAnd", ["NounExpr", "x"], ["LogicalAnd", ["NounExpr", "y"], ["NounExpr", "z"]]])
    testParse([noun("x"), pipePipe, noun("y")],
        term`LogicalOr(NounExpr("x"), NounExpr("y"))`)
    #self.assertEqual(parse("x || y || z"), ["LogicalOr", ["NounExpr", "x"], ["LogicalOr", ["NounExpr", "y"], ["NounExpr", "z"]]])

def testAssign():
    testParse([noun("x"), colonEqual, noun("y")],
        term`Assign(NounExpr("x"), NounExpr("y"))`)
    testParse([noun("x"), colonEqual, noun("y"), colonEqual, noun("z")],
        term`Assign(NounExpr("x"), Assign(NounExpr("y"), NounExpr("z")))`)
    #self.assertEqual(parse("x foo= y"), ["VerbAssign", "foo", ["NounExpr", "x"], [["NounExpr", "y"]]])
    #self.assertEqual(parse("x foo= (y)"), ["VerbAssign", "foo", ["NounExpr", "x"], [["NounExpr", "y"]]])
    #self.assertEqual(parse("x foo= (y, z)"), ["VerbAssign", "foo", ["NounExpr", "x"], [["NounExpr", "y"], ["NounExpr", "z"]]])
    #self.assertEqual(parse("x[i] := y"), ["Assign", ["GetExpr", ["NounExpr", "x"], [["NounExpr", "i"]]], ["NounExpr", "y"]])
    #self.assertEqual(parse("x(i) := y"), ["Assign", ["FunctionCallExpr", ["NounExpr", "x"], [["NounExpr", "i"]]], ["NounExpr", "y"]])
    #self.assertEqual(parse("x += y"), ["AugAssign", "Add", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x -= y"), ["AugAssign", "Subtract", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x *= y"), ["AugAssign", "Multiply", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x /= y"), ["AugAssign", "Divide", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x //= y"), ["AugAssign", "FloorDivide", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x %= y"), ["AugAssign", "Mod", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x **= y"), ["AugAssign", "Pow", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x >>= y"), ["AugAssign", "ShiftRight", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x <<= y"), ["AugAssign", "ShiftLeft", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x &= y"), ["AugAssign", "BinaryAnd", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x |= y"), ["AugAssign", "BinaryOr", ["NounExpr", "x"], ["NounExpr", "y"]])
    #self.assertEqual(parse("x ^= y"), ["AugAssign", "BinaryXor", ["NounExpr", "x"], ["NounExpr", "y"]])

def testDef():
    testParse([kwDef, noun("x"), colonEqual, literal(1)],
        term`Def(FinalPattern(NounExpr("x"), null), null, LiteralExpr(1))`)
    testParse([kwDef, noun("x"), kwExit, noun("e"), colonEqual, literal(1)],
        term`Def(FinalPattern(NounExpr("x"), null), NounExpr("e"), LiteralExpr(1))`)
    #self.assertEqual(parse("def [a, b] := 1"), ["Def", ["ListPattern", [["FinalPattern", ["NounExpr", "a"], None],["FinalPattern", ["NounExpr", "b"], None]], None], None, ["LiteralExpr", 1]])
    #self.assertEqual(parse("def x"), ["Forward", ["NounExpr", "x"]])
    #self.assertEqual(parse("var x := 1"), ["Def", ["VarPattern", ["NounExpr", "x"], None], None, ["LiteralExpr", 1]])
    #self.assertEqual(parse("bind x := 1"), ["Def", ["BindPattern", ["NounExpr", "x"], None], None, ["LiteralExpr", 1]])

def testEjector():
    testParse([kwReturn, noun("x"), plus, noun("y")],
        term`Return(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwReturn, openParen, noun("x"), plus, noun("y"), closeParen],
        term`Return(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwReturn, openParen, closeParen], term`Return(null)`)
    testParse([kwReturn], term`Return(null)`)
    testParse([kwContinue, noun("x"), plus, noun("y")],
        term`Continue(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwContinue, openParen, noun("x"), plus, noun("y"), closeParen],
        term`Continue(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwContinue, openParen, closeParen], term`Continue(null)`)
    testParse([kwContinue], term`Continue(null)`)
    testParse([kwBreak, noun("x"), plus, noun("y")],
        term`Break(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwBreak, openParen, noun("x"), plus, noun("y"), closeParen],
        term`Break(Add(NounExpr("x"), NounExpr("y")))`)
    testParse([kwBreak, openParen, closeParen], term`Break(null)`)
    testParse([kwBreak], term`Break(null)`)

def testLambda():
    testParse([kwFn, noun("a"), comma, openBracket, noun("b"), comma, noun("c"), closeBracket,
            openBrace, literal(1), closeBrace],
        term`Lambda(null,
            [FinalPattern(NounExpr("a"), null),
                ListPattern([FinalPattern(NounExpr("b"), null),
                    FinalPattern(NounExpr("c"), null)], null)],
            LiteralExpr(1))`)

def testWhile():
    testParse([kwWhile, openParen, noun("true"), closeParen,
            openBrace, literal(1), closeBrace],
        term`While(NounExpr("true"), LiteralExpr(1), null)`)
    testParse([kwWhile, openParen, noun("true"), closeParen,
            colon, indent, literal(1), dedent],
        term`While(NounExpr("true"), LiteralExpr(1), null)`)

def testWhen():
    testParse([kwWhen, openParen, noun("d"), closeParen,
            slimArrow, openBrace, literal(1), closeBrace],
        term`When([NounExpr("d")], LiteralExpr(1), [], null)`)
    testParse([kwWhen, openParen, noun("d"), closeParen,
            slimArrow, indent, literal(1), dedent],
        term`When([NounExpr("d")], LiteralExpr(1), [], null)`)
    #    self.assertEqual(parse("when (d) ->\n 1\ncatch p:\n 2"), ["When", [["NounExpr", "d"]], ["LiteralExpr", 1], [[["FinalPattern", ["NounExpr", "p"], None], ["LiteralExpr", 2]]], None])
    #    self.assertEqual(parse("when (d) -> {1} finally {3}"), ["When", [["NounExpr", "d"]], ["LiteralExpr", 1], [], ["LiteralExpr", 3]])
    #    self.assertEqual(parse("when (d) ->\n 1\nfinally:\n 3"), ["When", [["NounExpr", "d"]], ["LiteralExpr", 1], [], ["LiteralExpr", 3]])
    #    self.assertEqual(parse("when (e, d) -> {1}"), ["When", [["NounExpr", "e"], ["NounExpr", "d"]], ["LiteralExpr", 1], [], None])
    #    self.assertEqual(parse("when (e, d) ->\n 1"), ["When", [["NounExpr", "e"], ["NounExpr", "d"]], ["LiteralExpr", 1], [], None])

def testListComp():
    testParse([openBracket, literal(1),
            kwFor, noun("k"), fatArrow, noun("v"),
            kwIn, noun("x"), closeBracket],
        term`ListComp(FinalPattern(NounExpr("k"), null), FinalPattern(NounExpr("v"), null), NounExpr("x"), null, LiteralExpr(1))`)
    testParse([openBracket, literal(1),
            kwFor, noun("v"),
            kwIn, noun("x"), closeBracket],
        term`ListComp(null, FinalPattern(NounExpr("v"), null), NounExpr("x"), null, LiteralExpr(1))`)
    testParse([openBracket, literal(1),
            kwFor, noun("v"),
            kwIn, noun("x"),
            kwIf, noun("y"), closeBracket],
        term`ListComp(null, FinalPattern(NounExpr("v"), null), NounExpr("x"), NounExpr("y"), LiteralExpr(1))`)

def testIf():
    testParse([kwIf, openParen, noun("true"), closeParen,
            openBrace, literal(1), closeBrace],
        term`If(NounExpr("true"), LiteralExpr(1), null)`)
    testParse([kwIf, openParen, noun("true"), closeParen,
            colon, indent, literal(1), dedent],
        term`If(NounExpr("true"), LiteralExpr(1), null)`)
    testParse([kwIf, openParen, noun("true"), closeParen,
            openBrace, literal(1), closeBrace,
            kwElse, openBrace, literal(2), closeBrace],
        term`If(NounExpr("true"), LiteralExpr(1), LiteralExpr(2))`)
    testParse([kwIf, openParen, noun("true"), closeParen,
            colon, indent, literal(1), dedent,
            kwElse, colon, indent, literal(2), dedent],
        term`If(NounExpr("true"), LiteralExpr(1), LiteralExpr(2))`)

def testTopSeq():
    testParse([noun("x"), colonEqual, literal(1), semicolon,
            noun("y")],
        term`SeqExpr([
            Assign(NounExpr("x"), LiteralExpr(1)),
            NounExpr("y")])`)
    testParse([kwDef, noun("foo"), openParen, closeParen,
            colon, indent, kwReturn, literal(3), dedent,
            kwDef, noun("baz"), openParen, closeParen,
            colon, indent, kwReturn, literal(4), dedent,
            noun("foo"), openParen, closeParen, plus, noun("baz"), openParen, closeParen],
        term`SeqExpr([
            Object(null, FinalPattern(NounExpr("foo"), null), [null],
                Function([], null, Return(LiteralExpr(3)))),
            Object(null, FinalPattern(NounExpr("baz"), null), [null],
                Function([], null, Return(LiteralExpr(4)))),
            Add(FunctionCallExpr(NounExpr("foo"), []), FunctionCallExpr(NounExpr("baz"), []))])`)

def testMeta():
    testParse([noun("meta"), dot, noun("getState"), openParen, closeParen],
        term`Meta("State")`)
    testParse([noun("meta"), dot, noun("scope"), openParen, closeParen],
        term`Meta("Scope")`)
    testParse([noun("meta"), dot, noun("context"), openParen, closeParen],
        term`Meta("Context")`)

testLiteral()
testNoun()
testCollections()
testBody()
testCall()
testPrefix()
testPattern()
testMatch()
testOperators()
testAssign()
testDef()
testEjector()
testLambda()
testWhile()
testWhen()
testListComp()
testIf()
testTopSeq()
testMeta()
