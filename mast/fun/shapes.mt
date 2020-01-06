import "lib/colors" =~ [=> makeColor]
exports (triangle)

def triangle(color :DeepFrozen, x1, y1, x2, y2, x3 :Double, y3 :Double) as DeepFrozen:
    def denom :Double := (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    def r1 :Double := y2 - y3
    def g1 :Double := y3 - y1
    def r2 :Double := x3 - x2
    def g2 :Double := x1 - x3
    return def tri.drawAt(var x :Double, var y :Double) as DeepFrozen:
        x -= x3
        y -= y3
        def r := (r1 * x + r2 * y)/denom
        def g := (g1 * x + g2 * y)/denom
        def b := 1.0 - r - g
        return if (r < 0.0 || g < 0.0 || b < 0.0) { makeColor.clear() } else {
            # XXX I smell texels
            color
        }
