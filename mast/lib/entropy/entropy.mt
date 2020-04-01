import "lib/doubles" =~ [=> makeKahan]
import "lib/entropy/pool" =~  [=> makePool]
exports (makeEntropy)

def makeEntropy(generator) as DeepFrozen:
    "Augment a random number generator."

    def pool := makePool(generator)

    return object entropy:
        "
        An ergonomic source of random values.

        Methods whose verbs begin with \"next\" are probabalistic.
        "

        # Methods inherited from our component objects.

        to availableEntropy() :Int:
            return pool.availableEntropy()

        to getAlgorithm() :Str:
            return generator.getAlgorithm()

        # Primitive value generation.

        to nextBool() :Bool:
            "
            Either `true` or `false`.

            Uses 1 bit.
            "

            return pool.getSomeBits(1).isZero()

        to nextInt(n :(Int > 0)) :(0..n):
            "
            An `Int` in `0..n`.

            Uses Θ(lg `n`) bits.
            "

            # Unbiased selection: If a sample doesn't fit within the bound,
            # then discard it and take another one.
            def k := n.bitLength()
            var rv := pool.getSomeBits(k)
            while (rv > n):
                rv := pool.getSomeBits(k)
            return rv

        to nextDouble() :(0.0..!1.0):
            "
            A `Double` in `(0.0..!1.0)`.

            Uses 53 bits.
            "

            return pool.getSomeBits(53) / (1 << 53)

        # Draws from common probability distributions.

        to nextExponential(lambda :Double):
            "
            The exponential distribution with half-life λ.

            Uses 53 bits.
            "

            # This kind of inversion lets us avoid a conditional check for 0.0
            # before taking a logarithm.
            def d := 1.0 - entropy.nextDouble()
            return -(d.logarithm()) / lambda

        to nextSphere(n :(Int >= 1)):
            "
            A tuple on the unit `n`-sphere.

            Uses `n` * 53 bits.
            "

            # http://extremelearning.com.au/how-to-generate-uniformly-random-points-on-n-spheres-and-n-balls/
            # Since x will be small, x ** 2 may be denorm'd; use Kahan compensation.
            def d := makeKahan()
            def us := [for _ in (0..n) {
                def x := entropy.nextDouble()
                d(x ** 2)
                x
            }]
            def inorm := d[].squareRoot().reciprocal()
            return [for u in (us) u * inorm]

        to nextBall(n :(Int >= 2)):
            "
            A tuple within the unit `n`-ball.

            Uses (`n` + 1) * 53 bits.
            "

            # https://mathoverflow.net/questions/33129/
            # Intuition: https://www.youtube.com/watch?v=GNcFjFmqEc8
            return entropy.nextSphere(n + 1).slice(0, n)

        # Operations on Lists.

        to nextElement(l :List):
            "
            An element from `l`.

            Uses Θ(lg `l.size()`) bits.
            "

            return l[entropy.nextInt(l.size())]

        to shuffle(l :List) :List:
            "
            Permute `l`.

            Uses Θ(`l.size()` * lg `l.size()`) bits.
            "

            def fl := l.diverge()
            # https://en.wikipedia.org/wiki/Fisher%E2%80%93Yates_shuffle#The_modern_algorithm
            def n := l.size() - 1
            for i in (0..!n):
                def j := entropy.nextInt(n - i) + i
                def temp := fl[i]
                fl[i] := fl[j]
                fl[j] := temp
            return fl.snapshot()
