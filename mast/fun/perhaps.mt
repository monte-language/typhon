import "fun/monads" =~ [=> makeMonad]
exports (ddist, bddist, weighted, bayes, guard)

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
        traceln(`branch $branch p $p failure $failure branch == failure ${branch == failure}`)
        if (branch != failure):
            total += p
            rv.push([branch, p])
    # NB: Original paper uses Maybe, but we throw instead.
    if (total.isZero()):
        throw(`All viable branches have been rejected`)
    return weighted(_makeMap.fromPairs(rv.snapshot()))

def guard(m :DeepFrozen, test :Bool) as DeepFrozen:
    return if (test) { m.pure(null) } else { m.zero() }
