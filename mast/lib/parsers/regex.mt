import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (Regex)

interface _Regex :DeepFrozen:
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

object nullRegex as DeepFrozen implements _Regex:
    "∅, the regular expression which doesn't match."

    to _printOn(out) :Void:
        out.print("∅")

    to possible() :Bool:
        return false

    to acceptsEmpty() :Bool:
        return false

    to derive(_) :_Regex:
        return nullRegex

    to leaders() :Set:
        return [].asSet()

object emptyRegex as DeepFrozen implements _Regex:
    "ε, the regular expression which matches only the empty string."

    to _printOn(out) :Void:
        out.print("ε")

    to possible() :Bool:
        return true

    to acceptsEmpty() :Bool:
        return true

    to derive(_) :_Regex:
        return nullRegex

    to leaders() :Set:
        return [].asSet()

    to asString() :Str:
        return ""

object Regex extends _Regex as DeepFrozen:
    "Regular expressions."

    to "ø"() :Regex:
        return nullRegex

    to "ε"() :Regex:
        return emptyRegex

    to "|"(left :DeepFrozen, right :DeepFrozen) :Regex:
        if (!left.possible()):
            return right
        if (!right.possible()):
            return left
        return object orRegex as DeepFrozen implements _Regex:
            "An alternating regular expression."

            to _printOn(out) :Void:
                out.print(`($left)|($right)`)

            to possible() :Bool:
                return left.possible() || right.possible()

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() || right.acceptsEmpty()

            to derive(character) :Regex:
                return Regex."|"(left.derive(character),
                                 right.derive(character))

            to leaders() :Set:
                return left.leaders() | right.leaders()

    to "&"(left :DeepFrozen, right :DeepFrozen) :Regex:
        if (!left.possible() || !right.possible()):
            return nullRegex

        # Honest Q: Would using a lazy slot to cache left.acceptsEmpty() help here
        # at all? ~ C.

        return object andRegex as DeepFrozen implements _Regex:
            "A catenated regular expression."

            to _printOn(out) :Void:
                out.print(`$left$right`)

            to possible() :Bool:
                return left.possible() && right.possible()

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() && right.acceptsEmpty()

            to derive(character) :_Regex:
                def deriveLeft := Regex."&"(left.derive(character), right)
                return if (left.acceptsEmpty()):
                    Regex."|"(deriveLeft, right.derive(character))
                else:
                    deriveLeft

            to leaders() :Set:
                return if (left.acceptsEmpty()):
                    left.leaders() | right.leaders()
                else:
                    left.leaders()

    to "*"(regex :DeepFrozen) :Regex:
        return object starRegex as DeepFrozen implements _Regex:
            "The Kleene star of a regular expression."

            to _printOn(out) :Void:
                out.print(`$regex*`)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return true

            to derive(character) :_Regex:
                return Regex."&"(regex.derive(character), starRegex)

            to leaders() :Set:
                return regex.leaders()

    to "=="(value :DeepFrozen) :Regex:
        return object equalRegex as DeepFrozen implements _Regex:
            "A regular expression that matches exactly one value."

            to _printOn(out) :Void:
                out.print(M.toQuote(value))

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (character == value):
                    emptyRegex
                else:
                    nullRegex

            to leaders() :Set:
                return [value].asSet()

    to "∈"(values :Set[DeepFrozen]) :Regex:
        return object containsRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value in a finite set."

            to _printOn(out) :Void:
                def guts := "".join([for value in (values) M.toQuote(value)])
                out.print(`[$guts]`)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                for value in (values):
                    if (value == character):
                        return emptyRegex
                return nullRegex

            to leaders() :Set:
                return values

    to "?"(predicate :DeepFrozen) :Regex:
        return object suchThatRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value passing a predicate.

             The predicate must be `DeepFrozen` to prevent certain stateful
             shenanigans."

            to _printOn(out) :Void:
                predicate._printOn(out)

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (predicate(character)):
                    emptyRegex
                else:
                    nullRegex

            to leaders() :Set:
                return [].asSet()

    match [=="anyOf", rs, _]:
        var regex := nullRegex
        for r in (rs):
            regex := Regex."|"(regex, r)
        regex

def regexCat(hy, c1, c2):
    def regex := Regex."&"(Regex."=="(c1), Regex."=="(c2))
    hy.assert(regex.derive(c1).derive(c2).acceptsEmpty())

unittest([
    prop.test([arb.Char(), arb.Char()], regexCat),
])

object exprHoleTag as DeepFrozen {}

def makeQuasiLexer(regex :DeepFrozen, classifier :DeepFrozen, name :Str) as DeepFrozen:
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
                        var scanner := regex
                        var start :Int := 0
                        for i => c in (piece):
                            traceln(`scanner $scanner start $start i $i c $c`)
                            scanner derive= (c)
                            if (!scanner.acceptsEmpty()):
                                # Scanner just died; mark the token and
                                # reboot.
                                scanner := regex.derive(c)
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

def parens := Regex."∈"("()".asSet())
def identifier(members :Set[DeepFrozen]) as DeepFrozen:
    def char := Regex."∈"(members)
    return Regex."&"(char, Regex."*"(char))
def whitespace := Regex."*"(Regex."∈"(" \n".asSet()))
def comma := Regex."=="(',')
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
def termPieces := Regex.anyOf(parens, identifier(idChars), whitespace, comma)
def ::"term``" := makeQuasiLexer(termPieces, class, "term")(makeParser)
traceln(term`add(.int.(${2}), .int.(${5}))`)
