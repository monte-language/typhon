exports (makeSchwartzian)

# https://en.wikipedia.org/wiki/Schwartzian_transform

# Curry ala https://docs.python.org/3/library/functools.html#functools.cmp_to_key
# For intuitive explanation, see https://stackoverflow.com/questions/32752739
def comparisonToKey(cmp, x) as DeepFrozen:
    return object comparisonKey:
        to op__cmp(y):
            return cmp(x, y.unwrap())
        to unwrap():
            return x

def makeSchwartzian(f) as DeepFrozen:
    "
    The Schwartzian transformation, or decorate-sort-undecorate (DSU), is an
    idiom for arbitrarily projecting a custom sort operation onto a
    collection.

    The comparison function `f` should implement `.run(x, y) :Comparable`.
    "

    return object schwartzianTransformation:
        to sort(l :List) :List:
            "Transform `l.sort()`."

            def decorated := [for x in (l) comparisonToKey(f, x)]
            def sorted := decorated.sort()
            def undecorated := [for key in (sorted) key.unwrap()]
            return undecorated

        to sortKeys(m :Map) :Map:
            "Transform `m.sortKeys()`."

            def decorated := [for k => v in (m) comparisonToKey(f, k) => v]
            def sorted := decorated.sortKeys()
            def undecorated := [for key => v in (sorted) key.unwrap() => v]
            return undecorated

        to sortValues(m :Map) :Map:
            "Transform `m.sortValues()`."

            def decorated := [for k => v in (m) k => comparisonToKey(f, v)]
            def sorted := decorated.sortValues()
            def undecorated := [for k => key in (sorted) k => key.unwrap()]
            return undecorated
