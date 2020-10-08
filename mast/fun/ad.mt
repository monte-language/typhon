exports (makeDual, gradientAt, minimize)

object makeDual as DeepFrozen:
    to coerce(specimen, _ej) :DeepFrozen:
        return switch (specimen) {
            match d :Double { makeDual(d, 0.0) }
            match i :Int { makeDual(i.asDouble(), 0.0) }
            match _ { specimen }
        }

    to run(real :Double, epsilon :Double) :DeepFrozen:
        def D :DeepFrozen := makeDual.coerce
        return object dualNumber as DeepFrozen:
            "A dual number of the form `a+bε`."

            to _printOn(out):
                real._printOn(out)
                out.print("+")
                epsilon._printOn(out)
                out.print("ε")

            to op__cmp(via (D) other :DeepFrozen):
                return real.op__cmp(other.real())

            to real():
                return real

            to epsilon():
                return epsilon

            to abs():
                return if (real >= 0.0) { dualNumber } else {
                    makeDual(-real, -epsilon)
                }

            to negate():
                # Negation is like multiplication by -1.
                return makeDual(-real, -epsilon)

            to add(via (D) other :DeepFrozen):
                return makeDual(real + other.real(), epsilon + other.epsilon())

            to subtract(via (D) other :DeepFrozen):
                return makeDual(real - other.real(), epsilon - other.epsilon())

            to multiply(via (D) other :DeepFrozen):
                def or :DeepFrozen := other.real()
                def oe :DeepFrozen := other.epsilon()
                return makeDual(real * or, epsilon * or + real * oe)

            to approxDivide(via (D) other :DeepFrozen):
                def or :DeepFrozen := other.real()
                def oe :DeepFrozen := other.epsilon()
                return makeDual(real / or, (epsilon * or - real * oe) / (or ** 2))

            to pow(exponent :DeepFrozen):
                return if (exponent =~ i :Int) {
                    makeDual(real ** i, i * (real ** (i - 1)) * epsilon)
                } else {
                    # https://en.wikipedia.org/wiki/Differentiation_rules#Generalized_power_rule
                    def er :DeepFrozen := exponent.real()
                    def ee :DeepFrozen := exponent.epsilon()
                    def rv := real ** er
                    makeDual(rv, rv * ((epsilon * er / real) + (ee * real.logarithm())))
                }

            to exponential():
                def rv := real.exponential()
                return makeDual(rv, rv * epsilon)

            to logarithm():
                def rv := real.logarithm()
                return makeDual(rv, rv.reciprocal() * epsilon)

            to sine():
                return makeDual(real.sine(), real.cosine() * epsilon)

            to cosine():
                return makeDual(real.cosine(), real.sine() * -epsilon)

def gradientAt(f, coords :List[Double]) :List[Double] as DeepFrozen:
    "The gradient of `f` at the provided coordinates."

    return [for i => _ in (coords) {
        def args := [for j => a in (coords) {
            makeDual(a, (i == j).pick(1.0, 0.0))
        }]
        M.call(f, "run", args, [].asMap()).epsilon()
    }]

def minimize(f, starts :List[Double],
             => var gamma :Double := (1/128)) as DeepFrozen:
    "Find values near `starts` which minimize `f`, a function on Doubles."

    def invoke(args):
        return M.call(f, "run", args, [].asMap())

    return def minimizingIterable._makeIterator():
        var counter :Int := 0
        var minimum :List[Double] := starts

        return def minimizingIterator.next(ej):
            def gradient := gradientAt(f, minimum)
            def best := invoke(minimum)
            minimum := while (true) {
                def candidate := [for i => a in (minimum) a - gamma * gradient[i]]
                if (invoke(candidate) < best) { break candidate }
                # traceln(`candidate $candidate no good, gamma $gamma`)
                # Turn gamma down and try again.
                gamma *= 0.5
                if (gamma <= 0.0) {
                    throw.eject(ej,
                        "Cannot hear the gradient and the noise knob doesn't go any lower")
                }

            }
            # Slowly turn gamma back up.
            if (counter % 100 == 0 && gamma < 1.0):
                gamma *= 2.0

            def rv := [counter, minimum]
            counter += 1
            return rv
