import "fun/monads" =~ [=> makeMonad]
exports (ddist, bddist, bmc, weighted, bayes, guard,
         sampleWeights, sample, sampleWithRejections, sequential)

# A monadic approach to computing probabilities.
# http://www.randomhacks.net/files/build-your-own-probability-monads.pdf

object probMonoid as DeepFrozen:
    to one():
        return 1.0

    to multiply(p1, p2):
        return p1 * p2

def ddist :DeepFrozen := makeMonad.writer(makeMonad.list(), probMonoid)
def bddist :DeepFrozen := makeMonad.maybe(ddist)

def weighted(outcomes :Map[Any, Double]) :List as DeepFrozen:
    "
    Normalize a map of weights so that they sum to 1.0, and put them into the
    (b)ddist monad.
    "

    var sum := 0.0
    for _ => weight in (outcomes):
        sum += weight
    def scale := sum.reciprocal()
    return [for k => weight in (outcomes) [k, (weight * scale)]]

def bayes(action) as DeepFrozen:
    "Apply Bayes' Theorem to remove rejected possibilities."

    def failure := bddist.failure()
    var total := 0.0
    def rv := [].diverge()
    for [branch, p] in (action):
        if (branch != failure):
            total += p
            rv.push([branch, p])
    # NB: Original paper uses Maybe, but we throw instead.
    if (total.isZero()):
        throw(`All viable branches have been rejected`)
    return weighted(_makeMap.fromPairs(rv.snapshot()))

def guard(m :DeepFrozen, test :Bool) as DeepFrozen:
    return if (test) { m.pure(null) } else { m.zero() }

def mc :DeepFrozen := makeMonad.reader(makeMonad.identity())
def bmc :DeepFrozen := makeMonad.maybe(mc)

def sampleWeights(outcomes :Map[Any, Double]) as DeepFrozen:
    "An action in the Monte Carlo monad for sampling from weighted outcomes."

    # Our strategy is to build a list of cumulative weights in (0.0..1.0), and
    # then use entropy.nextDouble() to pick from that interval.
    var total := 0.0
    def ws := [for [branch, p] in (weighted(outcomes)) [branch, total += p]]

    return fn entropy {
        def d := entropy.nextDouble()
        escape ret {
            for [b, p] in (ws) {
                if (p > d) { ret(b) }
            }
            ws.last()[0]
        }
    }

def sample(entropy, action, n :Int) :List as DeepFrozen:
    "Take `n` samples from `action`."

    return [for _ in (0..!n) action(entropy)]

def sampleWithRejections(entropy, action, failure, n :Int) :List as DeepFrozen:
    "
    Take up to `n` samples from `action`, rejecting samples which result in
    `failure`.
    "

    return [for x in (sample(entropy, action, n)) ? (x != failure) x]

object smc as DeepFrozen:
    "
    A sequential Monte Carlo monad.

    This monad sends ordinary Monte Carlo actions to actions which take a
    number of particles to generate, and return a list of (up to) that many
    randomly-generated particles.
    "

    to pure(x):
        return fn n :Int { mc.pure([x]) }

    to control(verb :Str, ==1, ==1, block):
        return switch (verb):
            match =="map":
                def mapMonad.controlRun():
                    def [[ma], lambda] := block()
                    return fn n :Int {
                        mc (ma(n)) map xs { [for x in (xs) lambda(x, null)] }
                    }
            match =="do":
                def doMonad.controlRun():
                    def [[ma], lambda] := block()
                    return fn n :Int {
                        mc (ma(n)) do xs {
                            def rv := [].diverge()
                            for x in (xs) {
                                def l := lambda(x, null)(1)
                                if (!l.isEmpty()) { rv.push(l[0]) }
                            }
                            rv.snapshot()
                        }
                    }

def sequential(action) as DeepFrozen:
    "Send a Monte Carlo `action` to the sequential Monte Carlo monad."

    return fn n :Int { fn entropy { sample(entropy, action, n) } }
