exports (makePowerLevel, neper, bel, decibel, semitone, cent)

# Nepers and bels are logarithmic unit-like labels used to quantify the power
# differences between signals. They don't have to be used in signal analysis,
# but they're very common there because of the high dynamic range often
# required when working with signals. The generic name for these labels are
# "power levels".

def makePowerLevel(base :Double) as DeepFrozen:
    "Manipulate Doubles with the log semiring `base`."

    return object powerLevel as DeepFrozen:
        to add(x :Double, y :Double):
            return (base ** x + base ** y).logarithm(base)

        to subtract(x :Double, y :Double):
            return (base ** x - base ** y).logarithm(base)

        to multiply(x :Double, y :Double):
            return x + y

        to approxDivide(x :Double, y :Double):
            return x - y

# These are SI-adjacent not-quite-units.
def neper :DeepFrozen := makePowerLevel(1.0.exponential())
def bel :DeepFrozen := makePowerLevel(10.0)

# This constant, approximately 1.258925, is the base for decibels.
def dB :Double := 10.0 ** 10.0.reciprocal()
def decibel :DeepFrozen := makePowerLevel(dB)

# This constant, approximately 1.059463, is the base for 12-tone equal
# temperament.
def halfStep :Double := 2.0 ** 12.0.reciprocal()
def semitone :DeepFrozen := makePowerLevel(halfStep)

# Cents are like 1200-tone equal temperament.
def cent :DeepFrozen := makePowerLevel(2.0 ** 1200.0.reciprocal())
