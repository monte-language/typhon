exports (triangle)

def triangle(x1, y1, x2, y2, x3, y3) as DeepFrozen:
    def denom := (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3) 
    return def tri.drawAt(x, y):
        def r := ((y2 - y3) * (x - x3) + (x3 - x2) * (y - y3))/denom
        def g := ((y3 - y1) * (x - x3) + (x1 - x3) * (y - y3))/denom
        def b := 1.0 - r - g
        return if (r < 0.0 || g < 0.0 || b < 0.0) { [0.0] * 3 } else { [r, g, b] }
