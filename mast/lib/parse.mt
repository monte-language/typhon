import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (Parse)

# Parse: Dead-simple reasonably-performing incremental parser toolkit.

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
