import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/samplers" =~ [=> samplerConfig, => costOfConfig]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/csg" =~ [=> CSG, => expandCSG, => asSDF, => costOfSolid, => drawSDF]
import "lib/promises" =~ [=> makeSemaphoreRef]
import "fun/png" =~ [=> makePNG]
exports (main)

# Use the normal to show the gradient.
def debugNormal :DeepFrozen := CSG.Lambert(CSG.Normal(), CSG.Color(0.1, 0.1, 0.1))
# Use the gradient to show the gradient.
def debugGradient :DeepFrozen := CSG.Lambert(CSG.Gradient(), CSG.Color(0.1, 0.1, 0.1))
# http://devernay.free.fr/cours/opengl/materials.html
# A basic rubber material. Note that, unlike Kilgard's rubber, we put the
# color in the diffuse component instead of specular; rubber *does* absorb
# pigmentation and is naturally white.
def rubber(color) as DeepFrozen:
    return CSG.Phong(
        CSG.Color(0.4, 0.4, 0.4),
        color,
        CSG.Color(0.1, 0.1, 0.1),
        10.0,
    )
def checker :DeepFrozen := CSG.Lambert(CSG.Checker(), CSG.Color(0.1, 0.1, 0.1))
def white :DeepFrozen := CSG.Color(1.0, 1.0, 1.0)
def green :DeepFrozen := CSG.Color(0.04, 0.7, 0.04)
def red :DeepFrozen := CSG.Color(0.7, 0.04, 0.04)
def emerald :DeepFrozen := CSG.Phong(
    CSG.Color(0.633, 0.727811, 0.633),
    CSG.Color(0.07568, 0.61424, 0.07568),
    CSG.Color(0.0215, 0.1745, 0.0215),
    76.8,
)
def jade :DeepFrozen := CSG.Phong(
    CSG.Color(0.316228, 0.316228, 0.316228),
    CSG.Color(0.54, 0.89, 0.63),
    CSG.Color(0.135, 0.2225, 0.1575),
    12.8,
)
# def ivory := makeMatte([0.6, 0.3, 0.1], V(0.4, 0.4, 0.3), 50.0)
def ivory :DeepFrozen := CSG.Phong(
    CSG.Color(0.3, 0.3, 0.3),
    CSG.Color(0.4, 0.4, 0.3),
    CSG.Color(0.1, 0.1, 0.1),
    50.0,
)
# def glass := makeGlassy(1.5, [0.0, 0.5, 0.1, 0.8], V(0.6, 0.7, 0.8), 125.0)
# XXX needs to be glassy
def glass :DeepFrozen := CSG.Phong(
    CSG.Color(0.5, 0.5, 0.5),
    CSG.Color(0.0, 0.0, 0.0),
    CSG.Color(0.1, 0.1, 0.1),
    125.0,
)
# def mirror := makeGlassy(1.0, [0.0, 10.0, 0.8, 0.0], V(1.0, 1.0, 1.0), 1425.0)
# XXX glassy
def mirror :DeepFrozen := CSG.Phong(
    CSG.Color(1.0, 1.0, 1.0),
    CSG.Color(0.0, 0.0, 0.0),
    CSG.Color(0.8, 0.8, 0.8),
    128.0,
)
# Improvised.
def iron :DeepFrozen := CSG.Phong(
    CSG.Color(0.7, 0.7, 0.7),
    CSG.Color(0.56, 0.57, 0.58),
    CSG.Color(0.1, 0.1, 0.1),
    25.0,
)

# Debugging spheres, good for testing shadows.
def boxes :DeepFrozen := CSG.OrthorhombicCrystal(CSG.Sphere(1.0, debugNormal),
                                                 5.0, 5.0, 5.0)
# Sphere study.
# Effective marble should have the color throughout the stone, with a polished
# surface creating a shiny white layer.
def material := CSG.Phong(
    CSG.Color(0.8, 0.8, 0.8),
    CSG.Marble(2.0, 0.5, 2.0),
    CSG.Color(0.1, 0.1, 0.1), 75.0)
def study :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(100.0, checker), 0.0, -100.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0, material), 0.0, 2.0, 0.0),
])
# Holey beads in a lattice.
def crystal :DeepFrozen := CSG.OrthorhombicClamp(CSG.Difference(
    CSG.Intersection(CSG.Sphere(1.2, emerald),
                     [CSG.Cube(1.0, emerald)]),
    CSG.InfiniteCylindricalCross(0.5, 0.5, 0.5, emerald),
), 3.0, 3.0, 0.0, 4.0)
# Imitation tinykaboom.
def kaboom :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0, debugNormal),
    CSG.Noise(3.4, 3.4, 3.4, 5), 3.0)
# More imitation tinykaboom, but deterministic and faster.
def sines :DeepFrozen := CSG.Displacement(CSG.Sphere(3.0, jade),
    CSG.Sines(5.0, 5.0, 5.0), 3.0)
# tinyraytracer.
def tinytracer :DeepFrozen := CSG.Union(
    CSG.Translation(CSG.Sphere(100.0, rubber(green)), 0.0, -110.0, 0.0), [
    CSG.Translation(CSG.Sphere(2.0, ivory), -7.0, 0.0, -12.0),
    CSG.Translation(CSG.Sphere(2.0, glass), -4.0, -1.5, -9.0),
    CSG.Translation(CSG.Sphere(3.0, rubber(red)), -1.5, -0.5, -15.0),
    CSG.Translation(CSG.Sphere(4.0, mirror), -11.0, 5.0, -11.0),
])
# A morningstar.
def fortyFive :Double := 2.0.squareRoot().reciprocal()
def morningstar :DeepFrozen := {
    # We're going to apply displacement to the entire iron structure, to give
    # it a hammered look.
    def ironBall := CSG.Sphere(2.0, iron)
    def spikedBall := CSG.Union(ironBall, [
        CSG.CubicMirror(CSG.Cone(0.75, 4.0, iron)),
    ])
    def entireIron := CSG.Union(CSG.Box(0.3, 0.3, 5.0, iron), [
        CSG.Translation(spikedBall, 0.0, 0.0, 4.0),
    ])
    def hammered := CSG.Displacement(entireIron, CSG.Dimples(2.0, 2.0, 2.0), 0.02)
    CSG.Translation(CSG.Union(hammered, [
        CSG.Translation(CSG.Sphere(0.7, rubber(CSG.Color(0.7, 0.7, 0.5))), 0.0, 0.0, -5.0),
    ]), 0.0, 0.0, -2.0)
}
# A poor blade of grass.
def grass :DeepFrozen := CSG.Bend(CSG.Cylinder(2.0, 0.5, rubber(green)), 0.1)

def traceToPNG(Timer, entropy, width :Int, height :Int, solid) as DeepFrozen:
    traceln(`Tracing solid: $solid`)
    traceln(`Cost: ${solid(costOfSolid)}`)
    # Prepare some noise. lib/noise explains how to do this.
    def indices := entropy.shuffle(_makeList.fromIterable(0..!(2 ** 10)))
    def noise := makeSimplexNoise.fromShuffledIndices(indices)
    def sdf := solid(asSDF(noise))
    # Rate-limit the amount of enqueued work.
    # XXX dynamically discover this; should be 2 * workers + 1
    def maxWorkers :Int := 3
    def [drawable, activeWorkers] := makeSemaphoreRef(drawSDF(sdf), maxWorkers)
    # def config := samplerConfig.QuasirandomMonteCarlo(3)
    def config := samplerConfig.Center()
    def cost := config(costOfConfig) * solid(costOfSolid) * width * height
    def drawer := makePNG.drawingFrom(drawable, config)(width, height)
    def start := Timer.unsafeNow()
    var i := 0
    # NB: There are other ways to do this recursion, but we're trying to avoid
    # a Typhon implementation issue where thousands of chained promises can
    # resolve in a way which causes a stack overflow.
    def doneResolver := def done
    def go():
        def p := escape ej { drawer.next(ej) } catch _ {
            doneResolver.resolveRace(null)
            return
        }

        return when (p) ->
            go<-()
            i += 1
            if (i % 2000 == 0):
                def duration := Timer.unsafeNow() - start
                def pixelsPerSecond := i / duration
                def timeRemaining := ((width * height) - i) / pixelsPerSecond
                def normPixels := `(${(pixelsPerSecond * cost).logarithm()} work/s)`
                def workerStatus := `(${activeWorkers()}/$maxWorkers working)`
                traceln(`Status: ${(i * 100) / (width * height)}% ($pixelsPerSecond px/s) $workerStatus $normPixels (${timeRemaining}s left)`)
    # Kick off the workers with the desired parallelism.
    for _ in (0..!maxWorkers):
        go<-()
    return when (done) ->
        drawer.finish()

def main(_argv, => currentRuntime, => makeFileResource, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def solid := sines(expandCSG)
    def w := 640
    def h := 360
    def png := traceToPNG(Timer, entropy, w, h, solid)
    return when (png) ->
        traceln(`Created PNG of ${png.size()}b`)
        when (makeFileResource("sdf.png")<-setContents(png)) -> { 0 }
