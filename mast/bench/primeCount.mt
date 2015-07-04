# https://bjpelc.wordpress.com/2015/01/10/yet-another-language-speed-test-counting-primes-c-c-java-javascript-php-python-and-ruby-2/

def sqrt(i :Int) :Double:
    return (i + 0.0).sqrt()

def isPrime(n :Int) :Bool:
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


def lim :Int := 2 ** 12


def main():
    var noPrimes :Int := 0
    var n :Int := 0

    while (n <= lim):
        if (isPrime(n)):
            noPrimes += 1
        n += 1

    return noPrimes

bench(main, `Prime-counting function: π($lim)`)
