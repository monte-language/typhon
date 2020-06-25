import "lib/ints" =~ [=> greatestCommonDenominator]
exports (makeFraction)

object makeFraction as DeepFrozen:
    to un(specimen, ej):
        def [_, =="fromRatio", args, _] exit ej := specimen._uncall()
        return args

    to zero():
        return makeFraction.fromRatio(0, 1)

    to one():
        return makeFraction.fromRatio(1, 1)

    to fromContinuedFraction(coefficients :List[Int]):
        "The regularized continued fraction with `coefficients`."

        var rv := makeFraction.one()
        for x in (coefficients.reverse()):
            rv := rv.reciprocal() + makeFraction.fromRatio(x, 1)
        return rv

    to fromRatio(numerator :Int, denominator :Int):
        # Make sure that the denominator is positive, flipping the numerator
        # as needed.
        def flip := denominator.belowZero().pick(-1, 1)
        def factor := greatestCommonDenominator(numerator.abs(),
                                                denominator.abs())
        def n :Int := flip * numerator // factor
        def d :Int := flip * denominator // factor

        return object fraction as DeepFrozen:
            "A ratio of integers."

            to _uncall():
                return [makeFraction, "fromRatio", [n, d], [].asMap()]

            to _printOn(out):
                out.print(`$numerator/$denominator`)

            to numerator() :Int:
                return n

            to denominator() :Int:
                return d

            to asDouble() :Double:
                return n / d

            to op__cmp(other):
                return fraction - other

            to aboveZero() :Bool:
                return n.aboveZero()

            to atLeastZero() :Bool:
                return n.atLeastZero()

            to atMostZero() :Bool:
                return n.atMostZero()

            to belowZero() :Bool:
                return n.belowZero()

            to isZero() :Bool:
                return n.isZero()

            to add(via (makeFraction.un) [on, od]):
                return makeFraction.fromRatio(n * od + d * on, d * od)

            to subtract(other):
                return fraction + -other

            to multiply(via (makeFraction.un) [on, od]):
                return makeFraction.fromRatio(n * on, d * od)

            to divide(other):
                return fraction * other.reciprocal()

            to negate():
                return makeFraction.fromRatio(-n, d)

            to abs():
                return makeFraction.fromRatio(n.abs(), d)

            to reciprocal():
                return makeFraction.fromRatio(d, n)

            to approximant(limit :Int):
                "
                The nearest fraction with denominator no greater than
                `limit`.
                "

                # Continued fraction theory tells us that our return value
                # will be a best approximant, which corresponds to a
                # truncation of the continued fraction. Additionally, the
                # denominator of the truncation [x0; x1, x2, ..., xn] is at
                # least the product x0 * x1 * x2 * ... * xn, so we can
                # truncate at that point and then guess-and-check to see if
                # we're small enough.

                var product := 1
                var p := n.abs()
                var q := d
                def xs := [].diverge()
                while (q != 0 && product < limit):
                    def [quotient, remainder] := p.divMod(q)
                    product *= quotient
                    xs.push(quotient)
                    p := q
                    q := remainder
                # We'll make two candidates. The first uses the truncation
                # as-is, and the second compensates the final coefficient
                # depending on which direction to round towards.
                var first := makeFraction.fromContinuedFraction(xs.snapshot())
                # Take a step or two in order to remove any
                # problematically-large coefficients at the end.
                while (first.denominator() >= limit):
                    xs.pop()
                    first := makeFraction.fromContinuedFraction(xs.snapshot())
                # If the final coefficient is 1, then we can and should tuck
                # it into the penultimate coefficient:
                # 1/(xn + 1/1) == 1/(xn + 1)
                if (xs.last() == 1):
                    xs.pop()
                    xs.push(xs.pop() + 1)
                # Rounding direction based on how many flips we took. Whether
                # the approximant is below or above the target is whether the
                # number of coefficients is even.
                def above := (xs.size() % 2).isZero()
                xs.push(xs.pop() + above.pick(-1, 1))
                def second := makeFraction.fromContinuedFraction(xs.snapshot())
                # Pick the closer candidate, and fix the sign.
                def abs := fraction.abs()
                def rv := ((abs - first).abs() < (abs - second).abs()).pick(first, second)
                return if (n.belowZero()) { -rv } else { rv }

    to fromDouble(x :Double):
        def [mantissa, exponent] := x.normalizedExponent()
        var m := 0x0
        for i => b in (mantissa.asBytes()):
            m |= b << (7 - i) * 8
        # Mask off the 52 stored bits, and add the 53rd bit on top.
        m &= 0x0fffffffffffff
        m |= 0x10000000000000
        var e := 53 - exponent
        def rv := if (e.belowZero()) {
            makeFraction.fromRatio(m * (1 << -e), 1)
        } else { makeFraction.fromRatio(m, 1 << e) }
        # Check sign bit and negate if needed.
        return if (x.asBytes()[0] >= 0x80) { -rv } else { rv }
