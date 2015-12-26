imports
exports (Regex)

interface _Regex :DeepFrozen:
    "Regular expressions."

    to acceptsEmpty() :Bool:
        "Whether this regular expression accepts the empty string.
        
         Might calls this function δ()."

    to derive(character):
        "Compute the derivative of this regular expression with respect to the
         given character.
         
         The derivative is fully polymorphic."

object Regex extends _Regex as DeepFrozen:
    "Regular expressions."

    to "ø"() :Regex:
        return object nullRegex as DeepFrozen implements _Regex:
            "∅, the regular expression which doesn't match."

            to acceptsEmpty() :Bool:
                return false

            to derive(_) :_Regex:
                return nullRegex

    to "ε"() :Regex:
        return object emptyRegex as DeepFrozen implements _Regex:
            "ε, the regular expression which matches only the empty string."

            to acceptsEmpty() :Bool:
                return true

            to derive(_) :_Regex:
                return Regex."ø"()

    to "|"(left :_Regex, right :_Regex) :Regex:
        return object orRegex as DeepFrozen implements _Regex:
            "An alternating regular expression."

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() || right.acceptsEmpty()

            to derive(character) :Regex:
                return Regex."|"(left.derive(character),
                                 right.derive(character))

    to "&"(left :_Regex, right :_Regex) :Regex:
        # Honest Q: Would using a lazy slot to cache left.acceptsEmpty() help here
        # at all? ~ C.

        return object andRegex as DeepFrozen implements _Regex:
            "A catenated regular expression."

            to acceptsEmpty() :Bool:
                return left.acceptsEmpty() && right.acceptsEmpty()

            to derive(character) :_Regex:
                def deriveLeft := Regex."&"(left.derive(character), right)
                return if (left.acceptsEmpty()):
                    Regex."|"(deriveLeft, right.derive(character))
                else:
                    deriveLeft

    to "*"(regex :_Regex) :Regex:
        return object starRegex as DeepFrozen implements _Regex:
            "The Kleene star of a regular expression."

            to acceptsEmpty() :Bool:
                return true

            to derive(character) :_Regex:
                return Regex."&"(regex.derive(character), starRegex)

    to "=="(value :DeepFrozen) :Regex:
        return object equalRegex as DeepFrozen implements _Regex:
            "A regular expression that matches exactly one value."

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (character == value):
                    Regex."ε"()
                else:
                    Regex."ø"()

    to "∈"(values :Set[DeepFrozen]) :Regex:
        return object containsRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value in a finite set."

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                for value in values:
                    if (value == character):
                        return Regex."ε"()
                return Regex."ø"()

    to "?"(predicate :DeepFrozen) :Regex:
        return object suchThatRegex as DeepFrozen implements _Regex:
            "A regular expression that matches any value passing a predicate.

             The predicate must be `DeepFrozen` to prevent certain stateful
             shenanigans."

            to acceptsEmpty() :Bool:
                return false

            to derive(character) :_Regex:
                return if (predicate(character)):
                    Regex."ε"()
                else:
                    Regex."ø"()
