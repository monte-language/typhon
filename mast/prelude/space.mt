def charSpace :DeepFrozen := OrderedSpaceMaker(Char, "Char")
def intSpace :DeepFrozen := OrderedSpaceMaker(Int, "Int")
def doubleSpace :DeepFrozen := OrderedSpaceMaker(Double, "Double")

object _makeOrderedSpace extends OrderedSpaceMaker as DeepFrozen:
    "Maker of ordered vector spaces.

     This object implements several Monte operators, including those which
     provide ordered space syntax."

    to spaceOfValue(value):
        "Return the ordered space corresponding to a given value.

         The correspondence is obtained via Miranda _getAllegedType(), with
         special cases for `Char`, `Double`, and `Int`."

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
        "The operator `start`..!`bound`.

         This is equivalent to (space ≥ `start`) ∪ (space < `bound`) for the
         ordered space containing `start` and `bound`."

        def space := _makeOrderedSpace.spaceOfValue(start)
        return (space >= start) & (space < bound)

    to op__thru(start, stop):
        "The operator `start`..`bound`.

         This is equivalent to (space ≥ `start`) ∪ (space ≤ `bound`) for the
         ordered space containing `start` and `bound`."

        def space := _makeOrderedSpace.spaceOfValue(start)
        return (space >= start) & (space <= stop)

[
    "Char" => charSpace,
    "Int" => intSpace,
    "Double" => doubleSpace,
    => _makeOrderedSpace,
]
