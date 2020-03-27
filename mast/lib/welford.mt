import "lib/doubles" =~ [=> makeKahan]
exports (makeWelford)

# https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Welford's_online_algorithm
# https://people.xiph.org/~tterribe/notes/homs.html
# I can't figure out who Welford was, but their one-pass algorithm is a
# delightfully efficient way to keep running statistics on a sampled value.
# Their original paper is still under a paywall despite being from the 1960s,
# but the algorithm is small enough to fit in a single module. Terriberry
# gives an extension to the next two moments, and many others filled in the
# gaps.

# Only the univariate non-parallel case is covered, sorry.

def makeWelford() as DeepFrozen:
    var N :Int := 0

    def M1 := makeKahan()
    def M2 := makeKahan()
    def M3 := makeKahan()
    def M4 := makeKahan()

    return object welford:
        "
        Estimate a value by taking samples online in a single pass.

        The update takes constant time.

        The estimate includes the first four moments: Mean, variance, skew,
        and kurtosis.
        "

        to count() :Int:
            return N

        to mean() :Double:
            "The average sample."

            return M1[]

        to variance() :Double:
            "
            The spread of the samples.

            Note that this is meaningless unless at least two samples have
            been taken; be prepared to handle `NaN`.
            "

            return M2[] / (N - 1)

        to standardDeviation() :Double:
            "The square root of the variance."

            return welford.variance().squareRoot()

        to skew() :Double:
            "
            The asymmetry of the samples.

            Highly symmetric distributions will skew towards zero. Skew can be
            unbounded in either direction.
            "

            return M3[] * (N / M2[] ** 3).squareRoot()

        to kurtosis() :Double:
            "
            The surprisingness of the samples.

            Platykurtic data, or unsurprising data, will have zero kurtosis.
            Kurtosis is always positive.
            "

            return (N * M4[] / M2[] ** 2) - 3.0

        to run(sample :Double) :Void:
            "Account for `sample`."

            # Welford's algorithm for observations. First, update the count.
            N += 1
            # Prepare some coefficients.
            def delta := sample - M1[]
            def dn := delta / N
            def dn2 := dn ** 2
            def t := delta * dn * (N - 1)
            def md2 := 3 * dn * M2[]
            # The mean is updated first, and then each other coefficient is
            # done backwards, M4 to M2. That's just how the data dependencies
            # seem to go.
            M1(dn)
            M4(t * dn2 * (N * N - 3 * N + 3) + 2 * dn * md2 + 4 * dn * M3[])
            M3(t * dn * (N - 2) - md2)
            M2(t)
