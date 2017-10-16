import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (Parse)

# Parse: Dead-simple reasonably-performing incremental parser toolkit.
# Based largely on this functional pearl:
# http://matt.might.net/papers/might2011derivatives.pdf

def singletonSet(specimen, ej) as DeepFrozen:
    def s :Set ? (s.size() == 1) exit ej := specimen
    return s.asList()[0]

# Not using lib/enum because we might need to be prelude-compatible at some
# point in the future.
object empty as DeepFrozen {}
object eps as DeepFrozen {}
object red as DeepFrozen {}
object cat as DeepFrozen {}
object alt as DeepFrozen {}
object rep as DeepFrozen {}

object exactly as DeepFrozen {}
# These two are not in the original paper. They permit matching inputs not by
# equality, but by set membership or predicate.
object oneOf as DeepFrozen {}
object suchThat as DeepFrozen {}

def emptyYet(x) as DeepFrozen { return _equalizer.sameYet(x, empty) }

def kleeneMemo(f :DeepFrozen, default :DeepFrozen) as DeepFrozen:
    object pending as DeepFrozen {}
    return object memoized as DeepFrozen:
        match [=="run", topArgs, _]:
            var table := [].asMap()
            object recurse:
                match [=="run", args, _]:
                    if (table.contains(args)):
                        if (table[args] == pending):
                            def rv := default()
                            table with= (args, rv)
                            rv
                        else:
                            table[args]
                    else:
                        table with= (args, pending)
                        def rv := M.call(f, "run", [recurse] + args, [].asMap())
                        table with= (args, rv)
                        rv
            M.call(recurse, "run", topArgs, [].asMap())

def _parseNull(parseNull, parser) :Set as DeepFrozen:
    return switch (parser) {
        match ==empty { [].asSet() }
        match [==eps, set] { set }
        match [==cat, l, r] {
            var s := [].asSet()
            for p in (parseNull(l)) {
                for q in (parseNull(r)) { s with= ([p, q]) }
            }
            s
        }
        match [==alt, l, r] { parseNull(l) | parseNull(r) }
        match [==rep, _] { [[]].asSet() }
        match [==red, l, f] { [for x in (parseNull(l)) f(x)].asSet() }

        match [==exactly, _] { [].asSet() }
        match [==oneOf, _] { [].asSet() }
        match [==suchThat, _] { [].asSet() }
    }
def parseNull :DeepFrozen := kleeneMemo(_parseNull, [].asSet)

def breakOut(parser) as DeepFrozen:
    var m := [empty => 0]
    def stack := [parser].diverge()
    var label :Int := 1
    while (!stack.isEmpty()):
        def piece := stack.pop()
        if (!m.contains(piece)):
            m with= (piece, label)
            label += 1
            for p in (piece):
                if (p =~ _ :List):
                    stack.push(p)
    traceln(`breakOut has ${m.size()}`)
    return m

def derive(c, parser) as DeepFrozen:
    # NB: Cycles are likelier to happen on earlier pieces. (Proof: Think about
    # it for a bit.) This reversal makes emptyYet likelier to return true. ~ C.
    def breakout := breakOut(parser).reverse()
    def table := [for piece => _ in (breakout) piece => Ref.promise()]
    def go(piece):
        return table[piece][0]
    def derived := [for piece => _ in (table) piece => {
        def next := switch (piece) {
            match ==empty { empty }
            match [==eps, _] { empty }
            match [==cat, l, r] {
                def dl := go(l)
                def [lhs, skipLeft] := if (emptyYet(dl)) {
                    [empty, true]
                } else if (dl =~ [==eps, via (singletonSet) t1]) {
                    [[red, r, fn t2 { [t1, t2] }], false]
                } else { [[cat, dl, r], false] }
                def dr := go(r)
                def [rhs, skipRight] := if (emptyYet(dr)) {
                    [empty, true]
                } else {
                    def nullable := parseNull(l)
                    if (nullable.isEmpty()) {
                        [empty, true]
                    } else if (nullable.size() == 1) {
                        def t1 := nullable.asList()[0]
                        [[red, dr, fn t2 { [t1, t2] }], false]
                    } else {
                        [[cat, [eps, nullable], dr], false]
                    }
                }
                if (skipLeft) {
                    if (skipRight) { empty } else { rhs }
                } else if (skipRight) { lhs } else { [alt, lhs, rhs] }
            }
            match [==alt, l, r] {
                def dl := go(l)
                def dr := go(r)
                if (emptyYet(dl)) { dr } else if (emptyYet(dr)) {
                    dl
                } else { [alt, dl, dr] }
            }
            match [==rep, l] {
                def dl := go(l)
                if (emptyYet(dl)) { [eps, [[]].asSet()] } else {
                    [red, [cat, dl, piece], fn [h, t] { [h] + t }]
                }
            }
            match [==red, l, var f] {
                var dl := go(l)
                # if (dl =~ [==red, inner, g]) {
                #     dl := inner
                #     f := fn x { traceln(1, x); f(g(x)) }
                # }
                if (emptyYet(dl)) { empty } else if (dl =~ [==eps, ts]) {
                    [eps, [for t in (ts) f(t)].asSet()]
                } else { [red, dl, f] }
            }
            match [==exactly, specimen] {
                if (c == specimen) { [eps, [c].asSet()] } else { empty }
            }
            match [==oneOf, set] {
                if (set.contains(c)) { [eps, [c].asSet()] } else { empty }
            }
            match [==suchThat, pred] {
                if (pred(c)) { [eps, [c].asSet()] } else { empty }
            }
        }
        table[piece][1].resolve(next)
        next 
    }]
    return derived[parser]

def _sizeOf(sizeOf, parser) :Int as DeepFrozen:
    return 1 + switch (parser) {
        match ==empty { 0 }
        match [==eps, _] { 0 }
        match [==cat, l, r] { sizeOf(l) + sizeOf(r) }
        match [==alt, l, r] { sizeOf(l) + sizeOf(r) }
        match [==rep, l] { sizeOf(l) }
        match [==red, l, _] { sizeOf(l) }

        match [==exactly, _] { 0 }
        match [==oneOf, _] { 0 }
        match [==suchThat, _] { 0 }
    }
def zero :Int := 0
def sizeOf :DeepFrozen := kleeneMemo(_sizeOf, &zero.get)

def testParse(var parser, input):
    traceln(`initial parser sizeOf ${sizeOf(parser)}`)
    for char in (input):
        parser := derive(char, parser)
        traceln(`fed char $char, got sizeOf ${sizeOf(parser)}`)
        # throw("plz")
    return parseNull(parser)

def optional(parser) as DeepFrozen:
    return [alt, [eps, [null].asSet()], parser]
def joinedBy(parser, comma) as DeepFrozen:
    return [red, [cat, [red, parser, _makeList],
                  [rep, [red, [cat, comma, parser], fn [_, x] { x }]]],
            fn [h, t] { h + t }]
def bracket(parser, bra, ket) as DeepFrozen:
    return [red, [cat, bra, [cat, parser, ket]], fn [_, [x, _]] { x }]
# XXX shitty name
def makeId(members :Set[DeepFrozen]) as DeepFrozen:
    def char := [oneOf, members]
    # XXX factor to oneOrMore
    return [red, [red, [cat, char, [rep, char]], fn [h, t] { [h] + t }],
            _makeStr.fromChars]

{
    def whitespace := [rep, [oneOf, " \n".asSet()]]
    def comma := [cat, [exactly, ','], optional(whitespace)]
    def id := makeId("abcdefghijklmnopqrstuvwxyz.".asSet())
    def number := [red, makeId("1234567890".asSet()), _makeInt]
    def [term, atom] := [[cat, id, bracket(optional(joinedBy(atom, comma)),
                          [exactly, '('], [exactly, ')'])],
                         [alt, number, term]]
    # def ::"term``" := makeQuasiLexer(termPieces, class, "term")(makeParser)
    traceln(testParse(term, "add(.int.(2), .int.(5))"))
}

interface _Parse :DeepFrozen:
    "Regular expressions."

    to possible() :Bool:
        "Whether this regular expression can match anything ever."

    to acceptsEmpty() :Bool:
        "Whether this regular expression accepts the empty string.

         Might calls this function δ()."

    to derive(character):
        "Compute the derivative of this regular expression with respect to the
         given character.

         The derivative is fully polymorphic."

    to leaders() :Set:
        "Compute the set of values which can advance this regular expression."

object nullParse as DeepFrozen implements _Parse:
    "∅, the regular expression which doesn't match."

    to _printOn(out) :Void:
        out.print("∅")

    to possible() :Bool:
        return false

    to acceptsEmpty() :Bool:
        return false

    to derive(_) :_Parse:
        return nullParse

    to leaders() :Set:
        return [].asSet()

    to size() :Int:
        return 1

object emptyParse as DeepFrozen implements _Parse:
    "ε, the regular expression which matches only the empty string."

    to _printOn(out) :Void:
        out.print("ε")

    to possible() :Bool:
        return true

    to acceptsEmpty() :Bool:
        return true

    to derive(_) :_Parse:
        return nullParse

    to leaders() :Set:
        return [].asSet()

    to size() :Int:
        return 1

object Parse extends _Parse as DeepFrozen:
    "Regular expressions."

    to null() :Parse:
        return nullParse

    to empty() :Parse:
        return emptyParse

    to alt(left :DeepFrozen, right :DeepFrozen) :Parse:
        if (!left.possible()):
            return right
        if (!right.possible()):
            return left
        return object orParse as DeepFrozen implements _Parse:
            "An alternating regular expression."

            to _printOn(out) :Void:
                out.print(`($left)|($right)`)

            to possible() :Bool:
                return left.possible() || right.possible()

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() || right.acceptsEmpty()

            to derive(character) :Parse:
                return Parse.alt(left.derive(character),
                                 right.derive(character))

            to leaders() :Set:
                return left.leaders() | right.leaders()

            to size() :Int:
                return left.size() + right.size()

    to cat(left :DeepFrozen, right :DeepFrozen) :Parse:
        if (!left.possible() || !right.possible()):
            return nullParse

        # Honest Q: Would using a lazy slot to cache left.acceptsEmpty() help here
        # at all? ~ C.

        return object catParse as DeepFrozen implements _Parse:
            "A catenated regular expression."

            to _printOn(out) :Void:
                out.print(`$left$right`)

            to possible() :Bool:
                return left.possible() && right.possible()

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() && right.acceptsEmpty()

            to derive(character) :_Parse:
                def deriveLeft := Parse.cat(left.derive(character), right)
                return if (left.acceptsEmpty()):
                    Parse.alt(deriveLeft, right.derive(character))
                else:
                    deriveLeft

            to leaders() :Set:
                return if (left.acceptsEmpty()):
                    left.leaders() | right.leaders()
                else:
                    left.leaders()

            to size() :Int:
                return left.size() + right.size()

    to repeat(parse :DeepFrozen) :Parse:
        return object starParse as DeepFrozen implements _Parse:
            "The Kleene star of a regular expression."

            to _printOn(out) :Void:
                out.print(`$parse*`)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return true

            to derive(character) :_Parse:
                return Parse.cat(parse.derive(character), starParse)

            to leaders() :Set:
                return parse.leaders()

            to size() :Int:
                return 1 + parse.size()

    to exactly(value :DeepFrozen) :Parse:
        return object equalParse as DeepFrozen implements _Parse:
            "A regular expression that matches exactly one value."

            to _printOn(out) :Void:
                out.print(M.toQuote(value))

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Parse:
                return if (character == value):
                    emptyParse
                else:
                    nullParse

            to leaders() :Set:
                return [value].asSet()

            to size() :Int:
                return 1

    to contains(values :Set[DeepFrozen]) :Parse:
        return object containsParse as DeepFrozen implements _Parse:
            "A regular expression that matches any value in a finite set."

            to _printOn(out) :Void:
                def guts := "".join([for value in (values) M.toQuote(value)])
                out.print(`[$guts]`)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Parse:
                for value in (values):
                    if (value == character):
                        return emptyParse
                return nullParse

            to leaders() :Set:
                return values

            to size() :Int:
                return 1

    to suchThat(predicate :DeepFrozen) :Parse:
        return object suchThatParse as DeepFrozen implements _Parse:
            "A regular expression that matches any value passing a predicate.

             The predicate must be `DeepFrozen` to prevent certain stateful
             shenanigans."

            to _printOn(out) :Void:
                predicate._printOn(out)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Parse:
                return if (predicate(character)):
                    emptyParse
                else:
                    nullParse

            to leaders() :Set:
                return [].asSet()

            to size() :Int:
                return 1

    match [=="anyOf", rs, _]:
        var parse := nullParse
        for r in (rs):
            parse := Parse.alt(parse, r)
        parse

def parseCat(hy, c1, c2):
    def parse := Parse.cat(Parse.exactly(c1), Parse.exactly(c2))
    hy.assert(parse.derive(c1).derive(c2).acceptsEmpty())

unittest([
    prop.test([arb.Char(), arb.Char()], parseCat),
])

object exprHoleTag as DeepFrozen {}

def makeQuasiLexer(lexer :DeepFrozen, classifier :DeepFrozen, name :Str) as DeepFrozen:
    return def makeQuasiParser(parserMaker :DeepFrozen) as DeepFrozen:
        return object quasiParser as DeepFrozen:
            to _printOn(out):
                out.print(`<$name````>`)

            to valueHole(index :Int):
                return [exprHoleTag, index]

            to valueMaker(pieces):
                def tokens := [].diverge()

                for piece in (pieces):
                    if (piece =~ [==exprHoleTag, index :Int]):
                        # Pre-scanned for us.
                        tokens.push([".hole.", index, null])
                    else:
                        var scanner := lexer
                        var start :Int := 0
                        for i => c in (piece):
                            traceln(`scanner $scanner size ${scanner.size()}`)
                            scanner derive= (c)
                            if (!scanner.acceptsEmpty()):
                                # Scanner just died; mark the token and
                                # reboot.
                                scanner := lexer.derive(c)
                                if (i <= start):
                                    throw("Scanner failed to make progress")
                                def s := piece.slice(start, i)
                                start := i
                                tokens.push([classifier(s), s, null])
                        if (!scanner.acceptsEmpty()):
                            # Ragged edge.
                            throw(`Scanner wanted one of ${scanner.leaders()}, got EOS`)
                        def s := piece.slice(start, piece.size())
                        tokens.push([classifier(s), s, null])

                def tree := parserMaker()(tokens)
                return def ruleSubstituter.substitute(_):
                    return tree

def parens := Parse.contains("()".asSet())
def identifier(members :Set[DeepFrozen]) as DeepFrozen:
    def char := Parse.contains(members)
    return Parse.cat(char, Parse.repeat(char))
def whitespace := Parse.repeat(Parse.contains(" \n".asSet()))
def comma := Parse.exactly(',')
def class(s :Str) :Str as DeepFrozen:
    return switch (s) {
        match =="(" { "openParen" }
        match ==")" { "closeParen" }
        match =="," { "comma" }
        match s ? (" \n".contains(s[0])) { "whitespace" }
        match _identifier { "identifier" }
    }
def makeParser() as DeepFrozen:
    return fn tokens { tokens }
def idChars := "abcdefghijklmnopqrstuvwxyz.".asSet()
def termPieces := Parse.anyOf(parens, identifier(idChars), whitespace, comma)
def ::"term``" := makeQuasiLexer(termPieces, class, "term")(makeParser)
traceln(term`add(.int.(${2}), .int.(${5}))`)
