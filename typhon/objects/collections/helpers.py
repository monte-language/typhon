# Please avoid importing directly from this module if you aren't a collection.
# These are implementation details.

from rpython.rlib.listsort import make_timsort_class
from rpython.rlib.objectmodel import r_ordereddict

from typhon.errors import UserException, userError
from typhon.objects.constants import unwrapBool

# Backing storage for maps and sets, including hash definitions.

# Let's talk about maps for a second.
#
# Maps are backed by ordered dictionaries. This is an RPython-level hash table
# that is ordered, using insertion order, and has predictable
# insertion-order-based iteration order. Therefore, they should back Monte
# maps perfectly.
#
# The ordered dictionary at RPython level requires a few extra pieces of
# plumbing. We are asked to provide `key_eq` and `key_hash`. These are
# functions. `key_eq` is a key equality function which determines whether two
# keys are equal. `key_hash` is a key hashing function which returns a hash
# for a key.
#
# If two objects are equal, then they hash equal.
#
# We forbid unsettled refs from being used as keys, since their equality can
# change at any time.

def resolveKey(key):
    "Resolve a key so that its value won't change, or throw an exception."

    from typhon.objects.refs import isResolved, resolution
    key = resolution(key)

    if not isResolved(key):
        raise userError(u"Unresolved promises cannot be used as map keys")

    return key

def keyEq(first, second):
    from typhon.objects.equality import isSameEver
    first = resolveKey(first)
    second = resolveKey(second)
    return isSameEver(first, second)

def keyHash(key):
    return resolveKey(key).samenessHash()

def monteMap():
    return r_ordereddict(keyEq, keyHash)

# Sets have the same hashing machinery as maps; we use a distinct type to
# leverage type-checking and to permit sets to have always-None values.

def monteSet():
    return r_ordereddict(keyEq, keyHash)

def asSet(l):
    """
    Turn a list of Monte objects into a set of Monte objects.
    """

    s = monteSet()
    for x in l:
        s[x] = None
    return s

emptySet = monteSet()


# Comparison routines.

def monteLessThan(left, right):
    """
    try:
        return left.op__cmp(right).belowZero()
    catch _:
        return right.op__cmp(left).aboveZero()
    """

    try:
        comparison = left.call(u"op__cmp", [right])
        b = comparison.call(u"belowZero", [])
        return unwrapBool(b)
    except UserException:
        comparison = right.call(u"op__cmp", [left])
        b = comparison.call(u"aboveZero", [])
        return unwrapBool(b)

def monteLTKey(left, right):
    """
    return left[0] < right[0]
    """

    return monteLessThan(left[0], right[0])

def monteLTValue(left, right):
    """
    return left[1] < right[1]
    """

    return monteLessThan(left[1], right[1])

MonteSorter = make_timsort_class(lt=monteLessThan)
KeySorter = make_timsort_class(lt=monteLTKey)
ValueSorter = make_timsort_class(lt=monteLTValue)
