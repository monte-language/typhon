import "unittest" =~ [=> unittest :Any]
import "tests/proptests" =~ [
    => Arb :DeepFrozen,
    => arb :DeepFrozen,
    => prop :DeepFrozen,
]
import "lib/iterators" =~ [=> zip :DeepFrozen]
exports (Mat, makeMatrix)

interface Mat :DeepFrozen:
    "Integer-valued two-dimensional matrices."

    to get(i :(Int >= 0), j :(Int >= 0)) :Int:
        "The value of a matrix at `[i, j]`."

    to multiply(mat :Mat) :Mat:
        "Matrix multiplication."

def sum(xs :List[Int]) :Int as DeepFrozen:
    var rv := 0
    for x in (xs):
        rv += x
    return rv

def [makerAuditor :DeepFrozen, &&valueAuditor, &&serializer] := Transparent.makeAuditorKit()
object makeMatrix as DeepFrozen implements makerAuditor:
    "Polymorphic column-major matrices."

    to run(columns) :Mat:
        def rowSize := columns[0].size()
        return object matrix as Mat implements Selfless, valueAuditor:
            to _getAllegedInterface():
                return Mat

            to _printOn(out):
                out.print(`<$rowSize×${columns.size()} mat $columns>`)

            to _uncall():
                return serializer(makeMatrix, [columns])

            to size() :Pair[Int, Int]:
                return [rowSize, columns.size()]

            to get(i :Int, j :Int) :Int:
                return columns[j][i]

            to transpose() :Mat:
                def cs := _makeList.fromIterable(M.call(zip, "run", columns,
                                                        [].asMap()))
                return makeMatrix(cs)

            to multiply(mat :Mat) :Mat:
                return makeMatrix([for j in (0..!columns.size()) {
                    [for i in (0..!mat.size()[1]) sum([for k in (0..!rowSize) {
                        columns[k][i] * mat[k, j]
                    }])]
                }])

    to identity(size :Int) :Mat:
        return makeMatrix([for j in (0..!size) {
            [for i in (0..!size) (i == j).pick(1, 0)]
        }])

def arbMat(cols :Int, rows :Int):
    def ceiling :Int := 32
    def arbInt := arb.Int(=> ceiling)
    return object arbitraryMatrix as Arb:
        to arbitrary(entropy):
            return makeMatrix([for j in (0..!cols) {
                [for i in (0..!rows) arbInt.arbitrary(entropy)]
            }])

        to shrink(_) :List:
            return []

def matrixIdentityLeft(hy, mat):
    hy.assert(mat == makeMatrix.identity(3) * mat)
def matrixIdentityRight(hy, mat):
    hy.assert(mat == mat * makeMatrix.identity(3))

def matrixTransposeIdentity(hy, mat):
    hy.assert(mat == mat.transpose().transpose())

unittest([
    prop.test([arbMat(3, 3)], matrixIdentityLeft),
    prop.test([arbMat(3, 3)], matrixIdentityRight),
    prop.test([arbMat(3, 3)], matrixTransposeIdentity),
])
