exports (makeMatrix, chu)

object makeMatrix as DeepFrozen:
    # Addressing is column-major. x_ij -> i + j * stride
    # But also recall that matrices go:
    # [ 00 01 ... 0j ]
    # [ 10 11
    # [ ...   ...
    # [ i0        ij ]

    to un(specimen, ej):
        def [==makeMatrix, =="run", [i, j, l], _] exit ej := specimen._uncall()
        return [i, j, l]

    to run(i :Int, j :Int, l :List ? (l.size() == i * j)):
        return object matrix:
            to _uncall():
                return [makeMatrix, "run", [i, j, l], [].asMap()]

            to _printOn(out):
                for row in (0..!i):
                    out.print(M.toString([for column in (0..!j) matrix[row, column]]))

            to get(row :(0..!i), column :(0..!j)):
                return l[row + column * i]

            to dual():
                return makeMatrix(j, i, [for x in (0..!i * j) {
                    def [column, row] := x.divMod(j)
                    matrix[column, row]
                }])

            to tensor(other):
                def via (makeMatrix.un) [oi, oj, ol] := other
                # http://boole.stanford.edu/pub/bridge.pdf p8
                def ni := i * oi
                # Iterate over columns, building up a column for each pair of
                # functions.
                var F := []
                var nj := 0
                for f in (0..!oj ** i):
                    for g in (0..!j ** oi):
                        def col := [for x in (0..!ni) {
                            def [a, b] := x.divMod(i)
                            # How to apply a function encoded as a number like
                            # this? f has i different choices, each with width
                            # oj. This is like using oj as a base. To
                            # evaluate, first divide by the base at the index,
                            # then take the modulus of the width.
                            def fa := (f // oj ** a) % i
                            def gb := (g // j ** b) % oi
                            def val := matrix[a, gb]
                            if (val != other[b, fa]) { continue }
                            val
                        }]
                        F += col
                        nj += 1
                return makeMatrix(ni, nj, F.snapshot())

            to separate():
                def seen := [].asSet().diverge()
                def toSkip := [].diverge()
                for row in (0..!i):
                    def r := [for column in (0..!j) matrix[row, column]]
                    toSkip.push(seen.contains(r))
                    seen.include(r)
                return if (toSkip.isEmpty()) { matrix } else {
                    def cols := [for index => x in (l)
                                 ? (!toSkip[index % i]) x]
                    makeMatrix(seen.size(), j, cols)
                }

            to implies(other):
                return matrix.tensor(other.dual()).separate().dual()

            to plus(other):
                def via (makeMatrix.un) [oi, oj, ol] := other
                def ni := i + oi
                def nj := j * oj
                def cols := [for index in (0..!ni * nj) {
                    def [ab, xy] := index.divMod(ni)
                    def [x, y] := xy.divMod(j)
                    if (ab < i) { matrix[ab, x] } else { other[ab - i, y] }
                }]
                return makeMatrix(ni, nj, cols)

            to with(other):
                return matrix.dual().plus(other.dual()).dual()

    to identity(n :Int):
        return makeMatrix(n, n, [for x in (0..!n ** 2) {
            def [i, j] := x.divMod(n)
            i == j
        }])

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
