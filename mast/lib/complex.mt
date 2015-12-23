imports
exports (Complex, makeComplex)

interface Complex:
    "Complex numbers in ℂ."

    to real() :Double
    to imag() :Double

    to abs() :Double
    to add(other)
    to multiply(other)


def makeComplex(r :Double, i :Double) as DeepFrozen:
    return object complex as DeepFrozen implements Complex:
        to real() :Double:
            return r

        to imag() :Double:
            return i

        to abs() :Double:
            return (r * r + i * i).sqrt()

        to add(other :Complex) :Complex:
            return makeComplex(r + other.real(), i + other.imag())

        to multiply(other :Complex) :Complex:
            return makeComplex(r * r - i * i, 2.0 * r * i)
