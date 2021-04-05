exports (makeSchwartzian)

# https://en.wikipedia.org/wiki/Schwartzian_transform

# Curry ala https://docs.python.org/3/library/functools.html#functools.cmp_to_key
# For intuitive explanation, see https://stackoverflow.com/questions/32752739
def comparisonToKey(cmp) as DeepFrozen:
    return def keyMaker(x):
        return object comparisonKey:
            to op__cmp(y):
                return cmp(x, y.unwrap())
            to unwrap():
                return x

object makeSchwartzian as DeepFrozen:
    "
    The Schwartzian transformation, or decorate-sort-undecorate (DSU), is an
    idiom for arbitrarily projecting a custom sort operation onto a
    collection.
    "

    to fromComparison(cmp):
        "
        Make a Schwartzian transformation from a comparison function.

        The comparison function `f` should implement `.run(x, y) :Comparable`.
        "

        return makeSchwartzian.fromKeyFunction(comparisonToKey(cmp))

    to fromKeyFunction(keyMaker):
        "Make a Schwartzian transformation from a key function."

        return object schwartzianTransformation:
            to sort(l :List) :List:
                "Transform `l.sort()`."

                def decorated := [for x in (l) [keyMaker(x), x]]
                def sorted := decorated.sort()
                def undecorated := [for [_, x] in (sorted) x]
                return undecorated

            to sortKeys(m :Map) :Map:
                "Transform `m.sortKeys()`."

                def decorated := [for k => v in (m) [keyMaker(k), k] => v]
                def sorted := decorated.sortKeys()
                def undecorated := [for [_, k] => v in (sorted) k => v]
                return undecorated

            to sortValues(m :Map) :Map:
                "Transform `m.sortValues()`."

                def decorated := [for k => v in (m) k => [keyMaker(v), v]]
                def sorted := decorated.sortValues()
                def undecorated := [for k => [_, v] in (sorted) k => v]
                return undecorated
