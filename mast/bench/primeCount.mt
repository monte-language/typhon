import "bench" =~ [=> bench]
exports ()

# https://bjpelc.wordpress.com/2015/01/10/yet-another-language-speed-test-counting-primes-c-c-java-javascript-php-python-and-ruby-2/
# Please don't change the structure; it is meant to mirror similar programs in
# other languages, per the original microbenchmark.

def sqrt(i :Int) :Double as DeepFrozen:
    return (i + 0.0).squareRoot()

def isPrime(n :Int) :Bool as DeepFrozen:
    if (n < 2):
        return true
    else if (n == 2):
        return true
    else if (n % 2 == 0):
        return false

    def upperLimit := sqrt(n).floor()

    var i := 3
    while (i <= upperLimit):
        if (n % i == 0):
            return false
        i += 2

    return true

def countPrimes(lim :Int) :Int as DeepFrozen:
    var noPrimes :Int := 0
    var n :Int := 0

    while (n <= lim):
        if (isPrime(n)):
            noPrimes += 1
        n += 1

    return noPrimes


def lim :Int := 2 ** 12
bench(fn {countPrimes(lim)}, `Prime-counting function: π($lim)`)
