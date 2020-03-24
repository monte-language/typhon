exports (makeMatrix)

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

            to row(row :(0..!i)):
                return [for column in (0..!j) l[row + column * i]]

            to column(column :(0..!j)):
                return [for row in (0..!i) l[row + column * i]]

            to complement():
                return makeMatrix(j, i, [for x in (0..!i * j) {
                    def [column, row] := x.divMod(j)
                    matrix[column, row]
                }])

            to not():
                return makeMatrix(i, j, [for x in (l) !x])

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
                            def [a, b] := x.divMod(oi)
                            # How to apply a function encoded as a number like
                            # this? f has i different choices, each with width
                            # oj. This is like using oj as a base. To
                            # evaluate, first divide by the base at the index,
                            # then take the modulus of the width.
                            def fa := (f // oj ** a) % oj
                            def gb := (g // j ** b) % j
                            def val := matrix[a, gb]
                            if (val != other[b, fa]) { continue }
                            val
                        }]
                        F += col
                        nj += 1
                return makeMatrix(ni, nj, F.snapshot())

            to collapse():
                def seenRows := [].asSet().diverge()
                def rowsToSkip := [].diverge()
                for row in (0..!i):
                    def r := matrix.row(row)
                    rowsToSkip.push(seenRows.contains(r))
                    seenRows.include(r)
                def seenCols := [].asSet().diverge()
                def colsToSkip := [].diverge()
                for col in (0..!i):
                    def c := matrix.column(col)
                    colsToSkip.push(seenCols.contains(c))
                    seenCols.include(c)
                return if (rowsToSkip.isEmpty() && colsToSkip.isEmpty()) { matrix } else {
                    def data := [for index => x in (l) ? ({
                        def [c, r] := index.divMod(i)
                        !rowsToSkip.contains(r) && !colsToSkip.contains(c)
                    }) x]
                    makeMatrix(seenRows.size(), seenCols.size(), data)
                }

            to implies(other):
                return ~(matrix.tensor(~other)).collapse()

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
                return ~(~matrix).plus(~other)

            to isPointed() :Bool:
                for row in (0..!i):
                    def next := __continue
                    for x in (matrix.row(row)):
                        if (!x) { next() }
                    return true
                return false

            to discreteness() :Double:
                def p := 2 ** i - j
                def q := 2 ** j - i
                # NB: http://boole.stanford.edu/pub/gamut.pdf p5 claims this
                # cannot divide by zero.
                return (p - q) / (p + q)

    to identity(n :Int):
        return makeMatrix(n, n, [for x in (0..!n ** 2) {
            def [i, j] := x.divMod(n)
            i == j
        }])

    to unit():
        return makeMatrix(1, 2, [false, true])

    to completeAtomicBooleanAlgebra(n :Int):
        "The complete atomic Boolean algebra (CABA) with `n` elements."
        # [ 0 0 0 ... ]
        # [ 1 0 0     ]
        # [ 0 1 0     ]
        # [ 1 1 0     ]
        # [ 0 0 1     ]
        # [ 1 0 1     ]
        # [ 0 1 1     ]
        # [ 1 1 1     ]
        # [ ...       ]
        return makeMatrix(2 ** n, n, [for x in (0..!n * 2 ** n) {
            def [i, j] := x.divMod(2 ** n)
            !(1 << i & j).isZero()
        }])
