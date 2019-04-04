exports (render, makeSphere, spheres, lights)

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

def unitVector(source, dest) as DeepFrozen:
    "The unit vector pointing from `source` towards `dest`."
    def delta := [for i => x in (source) dest[i] - x]
    return norm(delta)

# "Classes" for our various "types" of object.

def makeMaterial(diffuseColor :List[Double]) as DeepFrozen:
    return def material.shade(diffuseLightIntensity) as DeepFrozen:
        return [for m in (diffuseColor) m * diffuseLightIntensity]

def makeLight(position :List[Double], intensity :Double) as DeepFrozen:
    return def light.illuminate(point, normal) as DeepFrozen:
        def lightDir := unitVector(position, point)
        return intensity * dot(lightDir, normal).max(0.0)

def makeSphere(center :List[Double], radius :(Double > 0.0),
               material :List[Double]) as DeepFrozen:
    def r2 :Double := radius * radius
    return object sphere as DeepFrozen:
        to material():
            return material

        to normal(v):
            return unitVector(center, v)

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

def castRay(orig, dir, spheres, lights) as DeepFrozen:
    var spheresDist := Infinity
    var best := null
    for sphere in (spheres):
        def [intersects, dist] := sphere.rayIntersect(orig, dir)
        if (intersects && dist < spheresDist):
            spheresDist := dist
            best := sphere
    return if (best == null) { [0.2, 0.7, 0.8] } else {
        def hit := [for i => o in (orig) o + dir[i] * spheresDist]
        def N := best.normal(hit)
        var diffuseLightIntensity := 0.0
        for light in (lights) {
            diffuseLightIntensity += light.illuminate(hit, N)
        }
        best.material().shade(diffuseLightIntensity)
    }

def ORIGIN :List[Double] := [0.0] * 3

def render(width :Int, height :Int, spheres, lights) :Bytes as DeepFrozen:
    def fov :Double := (PI / 6).tan()
    def aspectRatio :Double := width / height
    def framebuffer := [for k in (0..!(width * height)) {
        def [j, i] := k.divMod(width)
        def x := ((2 * i + 1) / width - 1) * fov * aspectRatio
        def y := -((2 * j + 1) / height - 1) * fov
        castRay(ORIGIN, norm([x, y, -1.0]), spheres, lights)
    }]
    def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
    def body := [].diverge()
    for i in (0..!(width * height)):
        for j in (0..!3):
            var s := framebuffer[i][j].min(1.0).max(0.0)
            def x := (255 * s).floor()
            body.push(x)
    return preamble + _makeBytes.fromInts(body)

def spheres() as DeepFrozen:
    def ivory := makeMaterial([0.4, 0.4, 0.3])
    def redRubber := makeMaterial([0.3, 0.1, 0.1])
    return [
        makeSphere([-3.0, 0.0, -16.0], 2.0, ivory),
        makeSphere([-1.0, -1.5, -12.0], 2.0, redRubber),
        makeSphere([1.5, -0.5, -18.0], 3.0, redRubber),
        makeSphere([7.0, 5.0, -18.0], 4.0, ivory),
    ]

def lights() as DeepFrozen:
    return [
        makeLight([-20.0, 20.0, 20.0], 1.5),
        makeLight([30.0, 50.0, -25.0], 1.8),
        makeLight([30.0, 20.0, 30.0], 1.7),
    ]
