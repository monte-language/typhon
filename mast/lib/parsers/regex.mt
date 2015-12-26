imports
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

    to asString() :Str:
        "Present this regular expression in a traditional text format."

object Regex extends _Regex as DeepFrozen:
    "Regular expressions."

    to "ø"() :Regex:
        return object nullRegex as DeepFrozen implements _Regex:
            "∅, the regular expression which doesn't match."

            to possible() :Bool:
                return false

            to acceptsEmpty() :Bool:
                return false

            to derive(_) :_Regex:
                return nullRegex

            to leaders() :Set:
                return [].asSet()

            to asString() :Str:
                return "[]"

    to "ε"() :Regex:
        return object emptyRegex as DeepFrozen implements _Regex:
            "ε, the regular expression which matches only the empty string."

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return true

            to derive(_) :_Regex:
                return Regex."ø"()

            to leaders() :Set:
                return [].asSet()

            to asString() :Str:
                return ""

    to "|"(left :_Regex, right :_Regex) :Regex:
        if (!left.possible()):
            return right
        if (!right.possible()):
            return left
        return object orRegex as DeepFrozen implements _Regex:
            "An alternating regular expression."

            to possible() :Bool:
                return left.possible() || right.possible()

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() || right.acceptsEmpty()

            to derive(character) :Regex:
                return Regex."|"(left.derive(character),
                                 right.derive(character))

            to leaders() :Set:
                return left.leaders() | right.leaders()

            to asString() :Str:
                return `(${left.asString()}|${right.asString()})`

    to "&"(left :_Regex, right :_Regex) :Regex:
        if (!left.possible() || !right.possible()):
            return Regex."ø"()

        # Honest Q: Would using a lazy slot to cache left.acceptsEmpty() help here
        # at all? ~ C.

        return object andRegex as DeepFrozen implements _Regex:
            "A catenated regular expression."

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

            to asString() :Str:
                return `${left.asString()}${right.asString()}`

    to "*"(regex :_Regex) :Regex:
        return object starRegex as DeepFrozen implements _Regex:
            "The Kleene star of a regular expression."

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return true

            to derive(character) :_Regex:
                return Regex."&"(regex.derive(character), starRegex)

            to leaders() :Set:
                return regex.leaders()

            to asString() :Str:
                return `(${regex.asString()})*`

    to "=="(value :DeepFrozen) :Regex:
        return object equalRegex as DeepFrozen implements _Regex:
            "A regular expression that matches exactly one value."

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (character == value):
                    Regex."ε"()
                else:
                    Regex."ø"()

            to leaders() :Set:
                return [value].asSet()

            to asString() :Str:
                return `$value`

    to "∈"(values :Set[DeepFrozen]) :Regex:
        return object containsRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value in a finite set."

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                for value in values:
                    if (value == character):
                        return Regex."ε"()
                return Regex."ø"()

            to leaders() :Set:
                return values

            to asString() :Str:
                def guts := "".join([for value in (values) M.toString(value)])
                return `[$guts]`

    to "?"(predicate :DeepFrozen) :Regex:
        return object suchThatRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value passing a predicate.

             The predicate must be `DeepFrozen` to prevent certain stateful
             shenanigans."

            to possible() :Bool:
                return true

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (predicate(character)):
                    Regex."ε"()
                else:
                    Regex."ø"()

            to leaders() :Set:
                return [].asSet()

            to asString() :Str:
                return M.toString(predicate)
