imports
exports (Complex, makeComplex)

interface Complex:
    "Complex numbers in ℂ."

    to real() :Double
    to imag() :Double

    to abs() :Double
    to add(other)
    to multiply(other)
    to subtract(other)


def makeComplex(r :Double, i :Double) as DeepFrozen:
    return object complex as DeepFrozen implements Complex:
        "A complex number in ℂ.

         This complex number uses `Double` internally and is thus subject to
         all the limitations of doing computation with `Double`."

        to _printOn(out):
            out.print(`ℂ($r + $iι)`)

        to real() :Double:
            return r

        to imag() :Double:
            return i

        to conjugate() :Complex:
            return makeComplex(r, -i)

        to abs() :Double:
            return (r * r + i * i).sqrt()

        to add(other :Complex) :Complex:
            return makeComplex(r + other.real(), i + other.imag())

        to subtract(other :Complex) :Complex:
            return makeComplex(r - other.real(), i - other.imag())

        to multiply(other :Complex) :Complex:
            def or := other.real()
            def oi := other.imag()
            return makeComplex(r * or - i * oi, r * oi + or * i)
