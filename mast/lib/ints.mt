exports (greatestCommonDenominator)

def greatestCommonDenominator(var u :Int, var v :Int) :Int as DeepFrozen:
    "The largest whole number which evenly divides both `u` and `v`."

    # Using Euclid's classic algorithm:
    # https://en.wikipedia.org/wiki/Euclidean_algorithm
    # We use modulus instead of subtraction, for speed.
    while (v != 0):
        def r := u % v
        u := v
        v := r
    return u
