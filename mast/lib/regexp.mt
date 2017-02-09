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
    return object alt:
        to _printOn(out):
            out.print(`alt($a, $b)`)

        to matchesNull() :Bool:
            return a.matchesNull() || b.matchesNull()

        to derive(c):
            return makeAlt(a.derive(c), b.derive(c))

def makeCat(a, b) as DeepFrozen:
    return object cat:
        to _printOn(out):
            out.print(`cat($a, $b)`)

        to matchesNull() :Bool:
            return a.matchesNull() && b.matchesNull()

        to derive(c):
            var rv := makeCat(a.derive(c), b)
            if (a.matchesNull()):
                rv := b.derive(c)
            return rv

def makeEx(x) as DeepFrozen:
    return object ex:
        to _printOn(out):
            out.print(`ex($x)`)

        to matchesNull() :Bool:
            return false

        to derive(c):
            return if (x == c) { eps } else { empty }

def testRegexpPathologicalLinear(assert):
    def a := makeEx('a')
    def maybe := makeAlt(eps, a)
    def core := makeCat(maybe, a)
    for length in (1..!30):
        var regex := core
        for _ in (0..!length):
            regex := makeCat(maybe, makeCat(regex, a))
        for _ in (0..length):
            regex derive= ('a')
        assert.equal(regex.matchesNull(), true)

unittest([
    testRegexpPathologicalLinear,
])
