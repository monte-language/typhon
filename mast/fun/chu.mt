import "lib/matrices" =~ [=> makeMatrix, => Mat]
import "lib/iterators" =~ [=> zip]
exports (chu)

# NB: lib/matrices is column-oriented

object chu as DeepFrozen:
    to invert(m :Mat) :Mat:
        return makeMatrix([for col in (m.columns()) {
            [for x in (col) x ^ 1]
        }])

    to CABA(size :(Int >= 0)) :Mat:
        return makeMatrix([for i in (0..!(2 ** size)) {
            [for b in (0..!size) (i >> b) & 1]
        }])

    to isPointed(m :Mat) :Bool:
        for row in (m.transpose().columns()):
            if (!row.contains(1)):
                return true
        return false

    to pointAt(m :Mat, r :(Int >= 0)) :Mat:
        return makeMatrix([for col in (m.columns()) {
            col.with(r, 0)
        }].asSet().asList())

    to linearOrder(size :(Int >= 0)) :Mat:
        return makeMatrix([for i in (0..!size) {
            [for b in (0..!size) (i <= b).pick(0, 1)]
        }])

    to isPoset(m :Mat) :Bool:
        def columns := m.columns().asSet()
        for c1 in (columns):
            for c2 in (columns):
                def intersection := [for [x1, x2] in (zip(c1, c2)) x1 & x2]
                def union := [for [x1, x2] in (zip(c1, c2)) x1 | x2]
                if (!columns.contains(intersection) ||
                    !columns.contains(union)):
                    return false
        return true

    to isCompleteSemilattice(m :Mat) :Bool:
        def rows := m.transpose().columns().asSet()
        for r1 in (rows):
            for r2 in (rows):
                def union := [for [x1, x2] in (zip(r1, r2)) x1 | x2]
                if (!rows.contains(union)):
                    return false
        def columns := m.columns().asSet()
        for c1 in (columns):
            for c2 in (columns):
                def union := [for [x1, x2] in (zip(c1, c2)) x1 | x2]
                if (!columns.contains(union)):
                    return false
        return true
