exports (counter, set, lastWriteWins)

# CRDTs, or semilattices with a unit.

object counter as DeepFrozen:
    "
    A semilattice on the natural numbers.

    This semilattice is known in CRDT literature as G-Counter when only
    addition is allowed, or PN-Counter when both addition and subtraction are
    allowed.
    "

    to unit():
        return 0

    to join(x, y):
        return x.max(y)

object set as DeepFrozen:
    "
    A semilattice on sets.

    This semilattice is known in CRDT literature as G-Set. Two sets can be
    used to build what is known as 2P-Set.
    "

    to unit():
        return [].asSet()

    to join(x, y):
        return x | y

# XXX could all allow parameterization

def joinMaps(m, n) as DeepFrozen:
    def rv := [].asMap().diverge()
    for k in (m.getKeys() + n.getKeys()):    
        rv[k] := m.fetch(k, fn { 0 }).max(n.fetch(k, fn { 0 }))
    return rv.snapshot()

object lastWriteWins as DeepFrozen:
    "
    A semilattice on sets which allows repeated insertion and deletion.

    This semilattice is known in CRDT literature as LWW-Element-Set.
    "

    to unit():
        return [[].asMap(), [].asMap()]

    to join(x, y):
        def [ax, rx] := x
        def [ay, ry] := y
        return [joinMaps(ax, ay), joinMaps(rx, ry)]

    to asSet(x):
        "
        Project a single set from an object in this semilattice.

        There are no non-trivial properties of the projected set which are
        monotonically preserved by joins. As a result, the projection is not
        necessarily the final state of the system.
        "

        def [ax, rx] := x
        return [for k => v in (ax) ? (rx.fetch(k, fn { 0 }) < v) k].asSet()
