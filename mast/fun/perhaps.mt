exports (bddist, bwsmc)

# A monadic approach to computing probabilities.
# http://www.randomhacks.net/files/build-your-own-probability-monads.pdf

# We ultimately only care about two flavors of monad from the paper. The
# "bddist" monad, maybe(writer(list, probMonoid)), gives us discrete PDFs with
# relatively precise measurements. This is a local maximum of functionality
# for us, since maybe()'s encoding costs O(0) extra space and O(1) space for
# loading this module compared to "ddist", but it does track every possibility
# which isn't proven impossible, which can be an overall limit on the number
# of possibilities that can be considered. Searching through exponentially
# large spaces is not feasible.

# Fortunately, we can do Monte Carlo, and we'll only implement the best Monte
# Carlo monad from the paper, the "bwsmc" monad,
# maybe(writer(smc, probMonoid)), where the "smc" monad is language-dependent.
# In Monte, smc is reader(list), taking an entropy and a number of particles
# to generate in reader, and tracking those particles in list. Since maybe()'s
# encoding is free, bwsmc is better than wsmc. smc is almost always better
# than one-at-a-time Monte Carlo.

# Flattened out, bddist's actions are just association lists of probabilities
# for each discrete event, with an extra event keyed to impossibility. We can
# use maps to simplify some of that logic, mapping events to probabilities.
# The guard might be like Map[NullOk[Any], Double] but with a custom failure
# so that null would still be a possible key.

# bwsmc's actions are like bddist's actions, but parameterized with a
# .run(entropy :Any, n :(Int > 0)) method which takes an entropy and a number
# of particles. When the method is run, the entropy will be called and mutated
# to generate up to n particles, with relative probabilities set by weights.

object ruledOut as DeepFrozen:
    "
    An impossibility; a possibility which has been removed from consideration
    by Bayes' Theorem.
    "

def normalizeWeights(outcomes :Map[Any, Double]) :Map[Any, Double] as DeepFrozen:
    "
    Normalize a discrete probability distribution, removing any outcomes
    which have been ruled out.
    "

    var sum := 0.0
    for k => weight in (outcomes):
        if (k == ruledOut):
            continue
        sum += weight
    def scale := sum.reciprocal()
    return [for k => weight in (outcomes)
            ? (k != ruledOut)
            k => weight * scale].sortValues().reverse()

object bddist as DeepFrozen:
    "
    Bayesian discrete probability distributions.

    This monad accurately tracks some discrete possibilities. Its results are
    precise but voluminious. Use `bwsmc` for efficient approximate methods.
    "

    to pure(x):
        return bddist.fromWeights([x => 1.0])

    to zero():
        return bddist.fromWeights([].asMap())

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[ma], lambda] := block()
                    def rv := [].asMap().diverge()
                    for k => p in (ma) {
                        def lk := lambda(k, null)
                        rv[lk] := rv.fetch(lk, fn { 0.0 }) + p
                    }
                    return bddist.fromWeights(rv.snapshot())
            match =="do":
                def doMonad.controlRun():
                    def [[ma], lambda] := block()
                    def rv := [].asMap().diverge()
                    for k => p in (ma) {
                        for lk => lp in (lambda(k, null)) {
                            rv[lk] := rv.fetch(lk, fn { 0.0 }) + p * lp
                        }
                    }
                    return bddist.fromWeights(rv.snapshot())

    to fromWeights(outcomes :Map[Any, Double]):
        "
        Normalize a map of weights so that they sum to 1.0, and put them into the
        (b)ddist monad.
        "

        return normalizeWeights(outcomes)

object bwsmc as DeepFrozen:
    "
    Bayesian weighted sequential Monte Carlo probability distributions.

    This monad takes particles on a random walk through arbitrary probability
    spaces. In exchange for being able to negotiate any probability space,
    this monad can only track a limited number of particles at once.
    "

    to pure(x):
        return bwsmc.fromWeights([x => 1.0])

    to zero():
        return bwsmc.fromWeights([])

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[ma], lambda] := block()
                    return fn entropy, n :Int {
                        def rv := [].asMap().diverge()
                        for k => p in (ma(entropy, n)) {
                            def lk := lambda(k, null)
                            rv[lk] := rv.fetch(lk, fn { 0.0 }) + p
                        }
                        normalizeWeights(rv.snapshot())
                    }
            match =="do":
                def doMonad.controlRun():
                    def [[ma], lambda] := block()
                    return fn entropy, n :Int {
                        def rv := [].asMap().diverge()
                        for k => p in (ma(entropy, n)) {
                            for lk => lp in (lambda(k, null)(entropy, n)) {
                                rv[lk] := rv.fetch(lk, fn { 0.0 }) + p * lp
                            }
                        }
                        normalizeWeights(rv.snapshot())
                    }

    to fromWeights(outcomes :Map[Any, Double]):
        "An action in the Monte Carlo monad for sampling from weighted outcomes."

        # Our strategy is to build a list of cumulative weights in (0.0..1.0), and
        # then use entropy.nextDouble() to pick from that interval.
        var total := 0.0
        def ws := [for branch => p in (normalizeWeights(outcomes))
                   [branch, total += p]]

        def takeSample(entropy):
            def d := entropy.nextDouble()
            for [b, p] in (ws):
                if (p > d):
                    return b
            return ws.last()[0]

        return def weightedSequentialMC(entropy, n :(Int > 0)):
            "
            Take a weighted sample of up to `n` particles, using
            `entropy` to perturb the random walk.
            "

            def rv := [].asMap().diverge()
            for _ in (0..!n):
                def k := takeSample(entropy)
                rv[k] := rv.fetch(k, fn { 0.0 }) + 1.0
            return normalizeWeights(rv.snapshot())
