def charSpace :DeepFrozen := OrderedSpaceMaker(Char, "Char")
def intSpace :DeepFrozen := OrderedSpaceMaker(Int, "Int")
def doubleSpace :DeepFrozen := OrderedSpaceMaker(Double, "Double")

object __makeOrderedSpace extends OrderedSpaceMaker as DeepFrozen:
    to spaceOfValue(value):
        "Given a value of a type whose reflexive (x <=> x) instances are
         fully ordered, this returns the corresponding OrderedSpace."

        if (value =~ i :Int):
            return intSpace
        else if (value =~ d :Double):
            return doubleSpace
        else if (value =~ c :Char):
            return charSpace
        else:
            # XXX does not work in any known implementation
            def type := value._getAllegedType()
            return OrderedSpaceMaker(type, M.toQuote(type))

    to op__till(start, bound):
        "start..!bound is equivalent to
         (space >= start) & (space < bound)"

        def space := __makeOrderedSpace.spaceOfValue(start)
        return (space >= start) & (space < bound)

    to op__thru(start, stop):
        "start..stop is equivalent to
         (space >= start) & (space <= stop)"

        def space := __makeOrderedSpace.spaceOfValue(start)
        return (space >= start) & (space <= stop)

[
    "Char" => charSpace,
    "Int" => intSpace,
    "Double" => doubleSpace,
    => __makeOrderedSpace,
]
