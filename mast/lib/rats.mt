import "unittest" =~ [=> unittest]
import "tests/proptests" =~ [
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
exports (Rat, main)

interface Rat :DeepFrozen:
    "Rational numbers."

# The prime base for our representation.
def p :Int := 5
def complementDigit(i :Int) as DeepFrozen:
    return p - i - 1

def makeCycleMachine(f :DeepFrozen) :DeepFrozen as DeepFrozen:
    return object cycleMachine as DeepFrozen:
        to lambda(initialState) :Int:
            # Brent's power-of-two trickery.
            var power :Int := 1
            var lambda :Int := 1
            var tortoise := initialState
            var hare := f(tortoise)[1]
            while (tortoise != hare):
                if (power == lambda):
                    tortoise := hare
                    power *= 2
                    lambda := 0
                hare := f(hare)[1]
                lambda += 1
            return lambda

        to findCycle(initialState) :Pair[Int, Int]:
            def lambda := cycleMachine.lambda(initialState)
            var tortoise := initialState
            var hare := initialState
            var mu :Int := 0

            for i in (0..!lambda):
                hare := f(hare)[1]

            while (tortoise != hare):
                tortoise := f(tortoise)[1]
                hare := f(hare)[1]
                mu += 1

            return [lambda, mu]

        to collectCycle(initialState) :Pair[List, List]:
            def [lambda, var mu] := cycleMachine.findCycle(initialState)
            var state := initialState
            def xs := [for _ in (0..!(mu + lambda)) {
                def [x, s] := f(state)
                state := s
                x
            }]
            # Try to shrink.
            while (mu > 0 && xs[mu - 1] == xs[mu - 1 + lambda]):
                mu -= 1
            # Make the slices.
            def rv := [xs.slice(0, mu), xs.slice(mu, mu + lambda)]
            # traceln(`mu $mu lambda $lambda table $xs`)
            # traceln(`collectCycle($initialState) -> $rv`)
            return rv

# XXX tighter bound might be p ** 2 - p + 1
def carryTable :List[Pair[Int, Int]] := [for i in (0..!(p ** 2)) [i // p, i % p]]
# traceln(`carryTable $carryTable`)

def rollState([ds, q]) as DeepFrozen:
    return switch (ds) {
        match [head] + tail { [head, [tail, q]] }
        match [] {
            def [qh] + qt := q
            [qh, [[], qt + [qh]]]
        }
    }

def addStep([left :Pair, right :Pair, carry :Int]) as DeepFrozen:
    def [leftDigit, leftNext] := rollState(left)
    def [rightDigit, rightNext] := rollState(right)
    def [carryNext, digit] := carryTable[leftDigit + rightDigit + carry]
    return [digit, [leftNext, rightNext, carryNext]]

def addMachine :DeepFrozen := makeCycleMachine(addStep)

def halfMulStep([left :Pair, right :Int, carry :Int]) as DeepFrozen:
    # NB: `right` is single digit, `left` is [ds, q]
    def [leftDigit, leftNext] := rollState(left)
    def [carryNext, digit] := carryTable[leftDigit * right + carry]
    return [digit, [leftNext, right, carryNext]]

def halfMulMachine :DeepFrozen := makeCycleMachine(halfMulStep)

def fullMulStep([left :Pair, right :Pair, acc :Pair]) as DeepFrozen:
    def [rightDigit, rightNext] := rollState(right)
    def mulPartial := halfMulMachine.collectCycle([left, rightDigit, 0])
    def sum := addMachine.collectCycle([acc, mulPartial, 0])
    def [digit, accNext] := rollState(sum)
    return [digit, [left, rightNext, accNext]]

def mulMachine :DeepFrozen := makeCycleMachine(fullMulStep)

def allZero(l) :Bool as DeepFrozen:
    for i in (l):
        if (i != 0):
            return false
    return true

object zeroRat as DeepFrozen implements Rat:
    to _printOn(out):
        out.print("<rat(0)>")

    to isZero():
        return true

    to belowZero():
        return false

    to aboveZero():
        return false

    to atMostZero():
        return true

    to atLeastZero():
        return true

    to op__cmp(other):
        return -other

    to negate():
        return zeroRat

    to add(other :Rat):
        return other

    to subtract(other :Rat):
        return -other

    to multiply(_ :Rat):
        return zeroRat

object makeRat as DeepFrozen:
    # XXX this could directly negate as it iterates through digits, but it
    # doesn't, because it is very hard to get right
    to fromInt(var i :Int) :Rat:
        if (i == 0):
            return zeroRat

        def digits := [].diverge()
        def isNegative :Bool := if (i.belowZero()) {
            i := -i
            true
        } else { false }
        var exponent :Int := 0
        var canExponent :Bool := true
        while (i > 0):
            def v := i % p
            if (canExponent && v == 0):
                exponent += 1
            else:
                canExponent := false
                digits.push(v)
            i //= p
        def rv := makeRat.improper(digits.snapshot(), [0], exponent)
        return if (isNegative) { -rv } else { rv }

    to improper(digits :List[Int], quote :List[Int], exponent :Int) :Rat:
        "Fix up `digits` and `quote` to a canonical form, and make a `Rat`."
        # traceln(`improper($digits $quote $exponent)`)

        return if (allZero(digits) && allZero(quote)) { zeroRat } else {
            var e := exponent
            # If we must introduce a leading zero, then we must temporarily adjust
            # the exponent to compensate.
            var ds := if (digits.isEmpty()) { e -= 1; [0] } else { digits }
            var q := if (quote.isEmpty()) { [0] } else { quote }
            # Remove all leading zeroes.
            while (ds =~ [==0] + tail) {
                e += 1
                ds := tail
            }
            # It seems common that the quote is doubled up.
            q := switch (q) {
                match [x, ==x] { [x] }
                match quo { quo }
            }
            # If necessary, unroll to get non-zero digits.
            while (ds.isEmpty()) {
                def [d] + qs := q
                if (d == 0) { e += 1 } else { ds := [d] }
                q := qs.with(d)
            }
            makeRat(ds, q, e)
        }

    to run(digits :List[Int] ? (!digits.isEmpty()),
           quote :List[Int] ? (!quote.isEmpty()), exponent :Int) :Rat:
        return object rat as DeepFrozen implements Rat:
            "A rational number in ℚ."

            to _printOn(out):
                var ds := digits
                var q := quote
                # Our digits must be capped with a non-zero digit. If there
                # are no such digits, then we are zero, which isn't possible
                # here.
                while (ds.last() == 0):
                    def [head] + tail := q
                    ds with= (head)
                    q := tail.with(head)

                var n :Int := 0
                for i => digit in (ds.reverse()):
                    n *= p
                    n += digit
                var approx :Double := {
                    var top :Int := p ** ds.size()
                    var bottom :Int := p ** q.size() - 1
                    var d :Int := 0
                    for i => digit in (q.reverse()) {
                        d *= p
                        d += digit
                    }
                    # traceln(`exponent $exponent n $n d $d top $top bottom $bottom`)
                    n - d * top / bottom
                }
                approx *= p ** exponent
                out.print(`<rat($approx)>`)

            to isZero() :Bool:
                return false

            to aboveZero() :Bool:
                return digits.last() > quote.last()

            to belowZero() :Bool:
                return digits.last() < quote.last()

            to atLeastZero() :Bool:
                return rat.aboveZero()

            to atMostZero() :Bool:
                return rat.belowZero()

            to op__cmp(other :Rat):
                return rat - other

            to digits():
                return [digits, quote, exponent]

            to negate():
                # Complement all digits and then add one.
                def ds := [for d in (digits) complementDigit(d)]
                def q := [for d in (quote) complementDigit(d)]
                def base := makeRat(ds, q, exponent)
                return base + makeRat([1], [0], exponent)

            to add(other :Rat):
                # Easy case, because why not?
                if (other == zeroRat):
                    return rat

                var ourDigits := digits
                def [var otherDigits, otherQuote, otherExponent] := other.digits()
                # Choose the bigger exponent and bump up the smaller side to
                # match.
                def finalExponent := if (exponent < otherExponent) {
                    otherDigits := [0] * (otherExponent - exponent) + otherDigits
                    exponent
                } else {
                    ourDigits := [0] * (exponent - otherExponent) + ourDigits
                    otherExponent
                }
                # Carry digit is initially 0.
                def initialState := [[ourDigits, quote],
                                     [otherDigits, otherQuote], 0]
                def [ds, q] := addMachine.collectCycle(initialState)
                return makeRat.improper(ds, q, finalExponent)

            to subtract(other :Rat):
                return rat + -other

            to multiply(other :Rat):
                # Quick case.
                if (other == zeroRat):
                    return zeroRat

                def [otherDigits, otherQuote, otherExponent] := other.digits()
                # No, really, this works.
                def finalExponent := exponent + otherExponent

                # Initial accumulator of 0'.
                def initialState := [[digits, quote],
                                     [otherDigits, otherQuote], [[], [0]]]
                def [ds, q] := mulMachine.collectCycle(initialState)
                return makeRat.improper(ds, q, finalExponent)

def ratComparison(hy, i):
    def r :Rat := makeRat.fromInt(i)
    if (i > 0):
        hy.assert(r.aboveZero())
        hy.assert(r.atLeastZero())
    else if (i < 0):
        hy.assert(r.belowZero())
        hy.assert(r.atMostZero())
    else:
        hy.assert(r.isZero())
        hy.assert(r.atLeastZero())
        hy.assert(r.atMostZero())

def ratAddition(hy, x, y):
    def r1 :Rat := makeRat.fromInt(x + y)
    def r2 :Rat := makeRat.fromInt(x) + makeRat.fromInt(y)
    hy.asBigAs(r1, r2)

def ratAdditionInverse(hy, x):
    def r :Rat := makeRat.fromInt(x)
    hy.sameEver(r - r, zeroRat)
    hy.sameEver(r + -r, zeroRat)

    def s :Rat := makeRat.fromInt(-x)
    hy.sameEver(r + s, zeroRat)

def ceiling := 2 ** 16
unittest([
    prop.test([arb.Int(=> ceiling)], ratComparison),
    prop.test([arb.Int(=> ceiling), arb.Int(=> ceiling)], ratAddition),
    prop.test([arb.Int(=> ceiling)], ratAdditionInverse),
])

def main(_argv) as DeepFrozen:
    def one := makeRat.fromInt(1)
    def negativeOne := makeRat.fromInt(-1)
    traceln(one, negativeOne)
    traceln(one + negativeOne)
    return 0
