exports (makeDual, minimize)

def E :Double := 2.71828_18284_59045_23536_02874

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

            to real():
                return real

            to epsilon():
                return epsilon

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
                    makeDual(rv, rv * ((epsilon * er / real) + (ee * real.log())))
                }

            to exp():
                def rv := E ** real
                return makeDual(rv, rv * epsilon)

            to sin():
                return makeDual(real.sin(), real.cos() * epsilon)

            to cos():
                return makeDual(real.cos(), real.sin() * -epsilon)

def minimize(f, starts :List[Double],
             => var gamma :Double := (1/128),
             => epsilon :Double := (10.0 ** -7)) :List[Double] as DeepFrozen:
    var minimum :List[Double] := starts
    var counter :Int := 0
    while (gamma > 0.0):
        counter += 1
        def elevation := M.call(f, "run", minimum, [].asMap())
        def ds := [for i => _ in (minimum) {
            def args := [for j => a in (minimum) {
                makeDual(a, (i == j).pick(1.0, 0.0))
            }]
            M.call(f, "run", args, [].asMap())
        }]
        def next := [for i => a in (minimum) a - gamma * ds[i].epsilon()]
        def ledge := M.call(f, "run", next, [].asMap())
        def error := {
            var eps := 0.0
            for d in (ds) { eps += d.epsilon() ** 2 }
            eps.sqrt()
        }
        if (ledge >= elevation):
            # traceln("overshoot ds", ds, "minimum", minimum, "next", next, "gamma", gamma)
            gamma *= 0.25
            continue
        if (error <= epsilon):
            return next
        # Set up for the next loop.
        minimum := next
        if (counter % 1000 == 0 && gamma < 1.0):
            gamma *= 2.0
        if (counter % 10000 == 0):
            traceln("iteration", counter, "minimum", minimum, "error", error)
    return minimum
