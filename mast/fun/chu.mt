exports (chu)

object chu as DeepFrozen:
    to invert(space):
        return object invertedChuSpace:
            to rows():
                return space.columns()

            to columns():
                return space.rows()

            to get(i, j):
                return space[j, i]

    to CABA(size :Int):
        return object completeAtomicBooleanChuSpace:
            to rows():
                return size

            to columns():
                return 2 ** size

            to get(i, j) :Bool:
                return !(j & (1 << i)).isZero()

    to isPointed(space) :Bool:
        for i in (0..!space.rows()):
            def next := __continue
            for j in (0..!space.columns()):
                if (space[i, j]):
                    next()
            return true
        return false
