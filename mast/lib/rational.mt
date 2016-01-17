exports (Rational, makeRational)

interface Rational :DeepFrozen:
    "Rational numbers in ℚ."

    to numerator() :Int
    to denominator() :Int

    to asPair() :Pair[Int, Int]

    to abs()
    to reduced()

    to add(other)
    to multiply(other)
    to subtract(other)
    to floorDivide(other)

def reduce(p :Int, q :Int) :Pair[Int, Int] as DeepFrozen:
    "Reduce a rational pair."

    def [var a :Int, var b :Int] := if (p > q) {[p, q]} else {[q, p]}
    while (b != 0):
        def temp := a % b
        a := b
        b := temp

    return [p // a, q // a]

def makeRational(n :Int, d :Int) as DeepFrozen:
    "Make a rational number with numerator `n` and denominator `d`."

    return object rational as DeepFrozen implements Rational:
        "A rational number in ℚ."

        to _getAllegedInterface():
            # XXX for regions
            return DeepFrozen

        to _printOn(out):
            out.print(`$n/$d`)

        to numerator() :Int:
            return n

        to denominator() :Int:
            return d

        to asPair() :Pair[Int, Int]:
            return [n, d]

        to abs() :Rational:
            return makeRational(n.abs(), d.abs())

        to reduced() :Rational:
            "A rational number equal to this one, but with coprime numerator
             and denominator."

            def [p, q] := reduce(n, d)
            return makeRational(p, q)

        to add(other :Rational) :Rational:
            def [p, q] := other.asPair()
            return makeRational(q * n + p * d, q * d)

        to multiply(other :Rational) :Rational:
            def [p, q] := other.asPair()
            return makeRational(p * n, q * d)

        to subtract(other :Rational) :Rational:
            def [p, q] := other.asPair()
            return makeRational(q * n - p * d, q * d)

        to floorDivide(other :Rational) :Rational:
            def [p, q] := other.asPair()
            return makeRational(q * n, p * d)

        to op__cmp(other :Rational):
            def [p, q] := other.asPair()
            return (q * n).op__cmp(p * d)
