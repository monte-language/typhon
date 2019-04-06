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

def negate(vs) as DeepFrozen:
    return [for v in (vs) -v]

def scale(vs :List, scalar :Double) as DeepFrozen:
    return [for v in (vs) v * scalar]

def add(vs, us) as DeepFrozen:
    "`vs`+`us` for vectors."
    return [for i in (0..2) vs[i] + us[i]]

def subtract(vs, us) as DeepFrozen:
    "`vs`-`us` for vectors."
    return [for i in (0..2) vs[i] - us[i]]

def unitVector(source, dest) as DeepFrozen:
    "The unit vector pointing from `source` towards `dest`."
    def delta := subtract(dest, source)
    return norm(delta)

def reflect(I, N) as DeepFrozen:
    def d := 2.0 * dot(I, N)
    return subtract(scale(N, d), I)

def perturb(point, N, dir) as DeepFrozen:
    def eps := scale(N, 1e-3)
    return if (dot(dir, N).belowZero()) {
        subtract(point, eps)
    } else { add(point, eps) }

# "Classes" for our various "types" of object.

def makeMaterial(refractiveIndex :Double,
                 [diffuseAlbedo :Double, specularAlbedo :Double,
                  reflectiveAlbedo :Double, refractiveAlbedo :Double],
                 diffuseColor :List[Double],
                 specularExponent :Double) as DeepFrozen:
    return object material as DeepFrozen:
        to refract(I, var N):
            var cosi := dot(I, N).min(1.0).max(-1.0)
            def eta := if (cosi.belowZero()) {
                N := negate(N)
                cosi := -cosi
                refractiveIndex
            } else {
                1 / refractiveIndex
            }
            def k := 1 - eta * eta * (1 - cosi * cosi)
            return if (k.atLeastZero()) {
                add(scale(I, eta), scale(N, eta * cosi - k.sqrt()))
            }

        to shade(diffuseLightIntensity, specularLightIntensity, reflectColor,
                 refractColor):
            def spec := specularLightIntensity * specularAlbedo
            return [for i => m in (diffuseColor) {
                (m * diffuseLightIntensity * diffuseAlbedo +
                 spec +
                 reflectColor[i] * reflectiveAlbedo +
                 refractColor[i] * refractiveAlbedo)
            }]

        to specularExponent():
            return specularExponent

def makeLight(position :List[Double], intensity :Double) as DeepFrozen:
    # https://en.wikipedia.org/wiki/Phong_reflection_model#Description
    # N is our unit normal at the point
    # V is our unit vector from the point to the camera
    return object light as DeepFrozen:
        to shadow(point, N):
            def Lm := unitVector(position, point)
            def lightDistance := norm(subtract(position, point))
            def eps := scale(N, 1e-3)
            def shadowOrigin := perturb(point, N, Lm)
            return [shadowOrigin, unitVector(point, position), lightDistance]

        to illuminate(V, point, N, exp):
            # Lm is our unit vector from the point to the light
            def Lm := unitVector(position, point)
            # Rm is our unit vector physically reflected from the point
            def Rm := reflect(Lm, N)
            def diff := intensity * dot(Lm, N).max(0.0)
            def spec := intensity * dot(Rm, V).max(0.0) ** exp
            return [diff, spec]

def makeSphere(center :List[Double], radius :(Double > 0.0),
               material :DeepFrozen) as DeepFrozen:
    def r2 :Double := radius * radius
    return object sphere as DeepFrozen:
        to material():
            return material

        to normal(v):
            return unitVector(center, v)

        to rayIntersect(orig, dir):
            def L := subtract(center, orig)
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

def castRay(orig, dir, spheres, lights, => depth := 0) as DeepFrozen:
    if (depth > 4) { return [0.2, 0.7, 0.8] }

    var spheresDist := Infinity
    var best := null
    for sphere in (spheres):
        def [intersects, dist] := sphere.rayIntersect(orig, dir)
        if (intersects && dist < spheresDist):
            spheresDist := dist
            best := sphere
    return if (best == null) { [0.2, 0.7, 0.8] } else {
        def mat := best.material()
        def exp := mat.specularExponent()
        def hit := add(orig, scale(dir, spheresDist))
        def N := best.normal(hit)

        def reflectDir := reflect(dir, N)
        def reflectOrig := perturb(hit, N, reflectDir)
        def reflectColor := castRay(reflectOrig, reflectDir, spheres, lights,
                                    "depth" => depth + 1)

        def refractColor := {
            def refractDir := mat.refract(dir, N)
            if (refractDir == null) { [0.0, 0.0, 0.0] } else {
                def refractOrig := perturb(hit, N, refractDir)
                castRay(refractOrig, refractDir, spheres, lights,
                        "depth" => depth + 1)
            }
        }

        var diffuse := 0.0
        var specular := 0.0
        for light in (lights) {
            # Checking if the point lies in the shadow of this light.
            # Construct a new origin and consider whether we run into any
            # spheres while trying to trace a ray back to this light.
            def [shadowOrigin, lightDir, lightDistance] := light.shadow(hit, N)

            def skipThisLight := __continue
            for sphere in (spheres) {
                def [intersects, dist] := sphere.rayIntersect(shadowOrigin, lightDir)
                if (intersects && dist < lightDistance) { skipThisLight() }
            }

            # Accumulate this light.
            def [d, s] := light.illuminate(dir, hit, N, exp)
            diffuse += d
            specular += s
        }
        mat.shade(diffuse, specular, reflectColor, refractColor)
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
        def c := framebuffer[i]
        def max := c[0].max(c[1]).max(c[2])
        def s := if (max > 1.0) { [for comp in (c) comp / max] } else { c }
        for x in (s):
            body.push((255 * x.min(1.0).max(0.0)).floor())
    return preamble + _makeBytes.fromInts(body)

def spheres() as DeepFrozen:
    def ivory := makeMaterial(1.0, [0.6, 0.3, 0.1, 0.0], [0.4, 0.4, 0.3], 50.0)
    def glass := makeMaterial(1.5, [0.0, 0.5, 0.1, 0.8], [0.6, 0.7, 0.8], 125.0)
    def redRubber := makeMaterial(1.0, [0.9, 0.1, 0.0, 0.0], [0.3, 0.1, 0.1], 10.0)
    # NB: GL traditionally caps specular exponent at 128.0
    def mirror := makeMaterial(1.0, [0.0, 10.0, 0.8, 0.0], [1.0, 1.0, 1.0], 1425.0)
    return [
        makeSphere([-3.0, 0.0, -16.0], 2.0, ivory),
        makeSphere([-1.0, -1.5, -12.0], 2.0, glass),
        makeSphere([1.5, -0.5, -18.0], 3.0, redRubber),
        makeSphere([7.0, 5.0, -18.0], 4.0, mirror),
    ]

def lights() as DeepFrozen:
    return [
        makeLight([-20.0, 20.0, 20.0], 1.5),
        makeLight([30.0, 50.0, -25.0], 1.8),
        makeLight([30.0, 20.0, 30.0], 1.7),
    ]
