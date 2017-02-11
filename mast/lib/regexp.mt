import "unittest" =~ [=> unittest]
exports ()

# Dead-simple regular expressions.

object empty as DeepFrozen:

    to _printOn(out):
        out.print("∅")

    to matchesNull() :Bool:
        return false

    to derive(_):
        return empty

object eps as DeepFrozen:

    to _printOn(out):
        out.print("ε")

    to matchesNull() :Bool:
        return true

    to derive(_):
        return empty

def makeAlt(a, b) as DeepFrozen:
    return if (a == empty):
        b
    else if (b == empty):
        a
    else:
        object alt:
            to _printOn(out):
                out.print(`alt($a, $b)`)

            to matchesNull() :Bool:
                return a.matchesNull() || b.matchesNull()

            to derive(c):
                return makeAlt(a.derive(c), b.derive(c))

def makeCat(a, b) as DeepFrozen:
    return if (a == empty || b == empty):
        empty
    else if (a == eps):
        b
    else if (b == eps):
        a
    else:
        object cat:
            to _printOn(out):
                out.print(`cat($a, $b)`)

            to matchesNull() :Bool:
                return a.matchesNull() && b.matchesNull()

            to derive(c):
                var rv := makeCat(a.derive(c), b)
                if (a.matchesNull()):
                    rv := makeAlt(rv, b.derive(c))
                return rv

def makeEx(x) as DeepFrozen:
    return object ex:
        to _printOn(out):
            out.print(`ex($x)`)

        to matchesNull() :Bool:
            return false

        to derive(c):
            return if (x == c) { eps } else { empty }

def makeStar(a) as DeepFrozen:
    return object star:
        to _printOn(out):
            out.print(`($a)*`)

        to matchesNull() :Bool:
            return true

        to derive(c):
            return makeCat(a.derive(c), star)

object any as DeepFrozen:
    to _printOn(out):
        out.print(`.`)

    to matchesNull() :Bool:
        return false

    to derive(_):
        return eps

def buildRegexp(s :Str) as DeepFrozen:
    def regexpStack := [eps].diverge()
    def cat(piece):
        def r := regexpStack.pop()
        regexpStack.push(makeCat(r, piece))

    for c in (s):
        switch (c):
            match =='.':
                cat(any)
            match =='?':
                def piece := regexpStack.pop()
                def optional := makeAlt(eps, piece)
                regexpStack.push(optional)
            match _:
                cat(makeEx(c))

    def regexp := regexpStack.pop()
    return object compiledRegexp:
        to matches(input) :Bool:
            var r := regexp
            for element in (input):
                r derive= (element)
            return r.matchesNull()

def testRegexpPathologicalLinear(assert):
    for length in (1..!30):
        def input := "a" * length
        var regexp := buildRegexp("a?" * length + input)
        assert.equal(regexp.matches(input), true)

def testRegexpMatchesAny(assert):
    def regexp := buildRegexp("b..k")
    assert.equal(regexp.matches("book"), true)
    assert.equal(regexp.matches("beak"), true)
    assert.equal(regexp.matches("brick"), false)

unittest([
    testRegexpPathologicalLinear,
    testRegexpMatchesAny,
])
