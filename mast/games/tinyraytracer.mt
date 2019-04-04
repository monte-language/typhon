exports (render, makeSphere, main)

# https://github.com/ssloy/tinyraytracer/wiki/Part-1:-understandable-raytracing

# We'll need some trigonometric tools.

def PI :Double := 3.14159265358979323846

def dot(lhs, rhs) as DeepFrozen:
    var rv := 0.0
    for i => l in (lhs):
        rv += l * rhs[i]
    return rv

def norm(v) as DeepFrozen:
    var sum := 0.0
    for x in (v):
        sum += x * x
    def n := sum.sqrt()
    return [for x in (v) x / n]

# "Classes" for our various "types" of object.

def makeSphere(center :List[Double], radius :(Double > 0.0),
               material :List[Double]) as DeepFrozen:
    def r2 :Double := radius * radius
    return object sphere as DeepFrozen:
        to material():
            return material

        to rayIntersect(orig, dir):
            def L := [for i => c in (center) c - orig[i]]
            def tca := dot(L, dir)
            def d2 := dot(L, L) - tca * tca
            # We need to try to take a square root, so we need this quantity to be
            # positive.
            def thcs := r2 - d2
            if (thcs.belowZero()) { return [false, null] }
            def thc := thcs.sqrt()
            return if (thc < tca) {
                [true, thc - tca]
            } else if (thc < -tca) {
                [true, thc + tca]
            } else { [false, null] }

def castRay(orig, dir, spheres) as DeepFrozen:
    var spheresDist := Infinity
    var color := [0.2, 0.7, 0.8]
    for sphere in (spheres):
        def [intersects, dist] := sphere.rayIntersect(orig, dir)
        if (intersects && dist < spheresDist):
            spheresDist := dist
            color := sphere.material()
    return color

def ORIGIN :List[Double] := [0.0] * 3

def render(width :Int, height :Int, spheres) :Bytes as DeepFrozen:
    def fov :Double := (PI / 6).tan()
    def aspectRatio :Double := width / height
    def framebuffer := [for k in (0..!(width * height)) {
        def [j, i] := k.divMod(width)
        def x := ((2 * i + 1) / width - 1) * fov * aspectRatio
        def y := -((2 * j + 1) / height - 1) * fov
        castRay(ORIGIN, norm([x, y, -1.0]), spheres)
    }]
    def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
    def body := [].diverge()
    for i in (0..!(width * height)):
        for j in (0..!3):
            var s := framebuffer[i][j].min(1.0).max(0.0)
            def x := (255 * s).floor()
            body.push(x)
    return preamble + _makeBytes.fromInts(body)

def main() as DeepFrozen:
    def ivory := [0.4, 0.4, 0.3]
    def redRubber := [0.3, 0.1, 0.1]
    return [
        makeSphere([-3.0, 0.0, -16.0], 2.0, ivory),
        makeSphere([-1.0, -1.5, -12.0], 2.0, redRubber),
        makeSphere([1.5, -0.5, -18.0], 3.0, redRubber),
        makeSphere([7.0, 5.0, -18.0], 4.0, ivory),
    ]
