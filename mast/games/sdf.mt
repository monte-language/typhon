import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/samplers" =~ [=> samplerConfig, => costOfConfig]
import "lib/csg" =~ [=> CSG, => expandCSG, => costOfSolid]
import "lib/promises" =~ [=> makeSemaphoreRef, => makeLoadBalancingRef]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer]
import "lib/monte/monte_parser" =~ [=> parseModule]
import "lib/muffin" =~ [=> makeLimo]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/csg" =~ [=> asSDF, => drawSDF]
import "lib/amp" =~ [=> makeAMPPool]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
import "lib/nproc" =~ [=> getNumberOfProcessors]
import "lib/vamp" =~ [=> makeVampEndpoint]
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

def copyCSGTo(ref) as DeepFrozen:
    return object copier:
        match [verb, args, namedArgs]:
            M.send(ref, verb, args, namedArgs)

def distributedTraceToPNG(Timer, entropy, width :Int, height :Int, solid, vp, pool, nproc) as DeepFrozen:
    traceln(`Tracing solid with $nproc workers: $solid`)
    # def config := samplerConfig.QuasirandomMonteCarlo(3)
    def config := samplerConfig.Center()
    def cost := config(costOfConfig) * solid(costOfSolid) * width * height
    traceln(`Cost: $cost (log-cost: ${cost.asDouble().logarithm()})`)
    # Prepare some noise. lib/noise explains how to do this.
    def indices := entropy.shuffle(_makeList.fromIterable(0..!(2 ** 10)))

    # Set up our work delegation: Messages go first to a rate-limiting
    # semaphore, and then to the worker backends via load-balancing.
    def [workerRef, addWorkerRef] := makeLoadBalancingRef()
    # Rate-limit the amount of enqueued work.
    # XXX dynamically discover this; should be 2 * workers + 1
    def [drawableRef, activeWorkers, queuedWork] := makeSemaphoreRef(workerRef, nproc)
    def drawer := makePNG.drawingFrom(drawableRef, config)(width, height)

    # Wait for somebody to connect. When they connect, set them up and add
    # them to the load balancer.
    def readyResolver := def ready
    pool.whenClient(fn module {
        traceln(`Pool $pool whenClient module $module`)
        def remoteSolid := solid(copyCSGTo(module["CSG"]))
        def remoteNoise := module["makeSimplexNoise"]<-fromShuffledIndices(indices)
        def remoteSDF := remoteSolid<-(module["asSDF"]<-(remoteNoise))
        def remoteDrawable := module["drawSDF"]<-(remoteSDF)
        when (remoteDrawable) -> {
            traceln(`Built remote drawable $remoteDrawable`)
            addWorkerRef(remoteDrawable)
            readyResolver.resolveRace(null)
        } catch problem {
            traceln(`Problem setting up client: $problem`)
        }
    })

    # Start them.
    vp.connectWorkers(nproc)
    traceln("Waiting for workers to connect…")
    return when (ready) ->
        traceln("Got workers, starting work!")
        def start := Timer.unsafeNow()
        var i := 0
        def go():
            return when (drawer.next(__return)) ->
                i += 1
                if (i % 2000 == 0):
                    def duration := Timer.unsafeNow() - start
                    def pixelsPerSecond := i / duration
                    def timeRemaining := ((width * height) - i) / pixelsPerSecond
                    def normPixels := `(${(pixelsPerSecond * cost).logarithm()} work/s)`
                    def workerStatus := `(${activeWorkers()}/$nproc working, ${queuedWork()} queued)`
                    traceln(`Status: ${(i * 100) / (width * height)}% ($pixelsPerSecond px/s) $normPixels $workerStatus (${timeRemaining}s left)`)
                go<-()
        # Feed each worker.
        def runs := [for _ in (0..nproc) go<-()]
        when (promiseAllFulfilled(runs)) ->
            drawer.finish()

def localTraceToPNG(Timer, entropy, width :Int, height :Int, solid) as DeepFrozen:
    traceln(`Tracing solid locally: $solid`)
    # def config := samplerConfig.QuasirandomMonteCarlo(3)
    def config := samplerConfig.Center()
    def cost := config(costOfConfig) * solid(costOfSolid) * width * height
    traceln(`Cost: $cost (log-cost: ${cost.asDouble().logarithm()})`)
    # Prepare some noise. lib/noise explains how to do this.
    def indices := entropy.shuffle(_makeList.fromIterable(0..!(2 ** 10)))

    def drawableRef := drawSDF(solid(asSDF(makeSimplexNoise.fromShuffledIndices(indices))))
    def drawer := makePNG.drawingFrom(drawableRef, config)(width, height)

    # Just run every pixel at once, and then monitor progress in callbacks.
    def start := Timer.unsafeNow()
    var i := 0
    def doneResolver := def done
    def progress():
        escape ej:
            drawer.next(ej)
            progress<-()
        catch _:
            doneResolver.resolve(null)
        i += 1
        if (i % 2000 == 0):
            def duration := Timer.unsafeNow() - start
            def pixelsPerSecond := i / duration
            def timeRemaining := ((width * height) - i) / pixelsPerSecond
            def normPixels := `(${(pixelsPerSecond * cost).logarithm()} work/s)`
            traceln(`Status: ${(i * 100) / (width * height)}% ($pixelsPerSecond px/s) $normPixels (${timeRemaining}s left)`)
    progress<-()
    return when (done) ->
        drawer.finish()

# XXX cribbed from tools/repl, craves to share code with montec

def makeFileLoader(root :Str, makeFileResource) as DeepFrozen:
    return def load(petname :Str):
        def path := `$root/$petname.mt`
        def bs := makeFileResource(path)<-getContents()
        return when (bs) ->
            escape ej:
                def source := UTF8.decode(bs, ej)
                def lex := makeMonteLexer(source, petname)
                [source, parseModule(lex, astBuilder, ej)]
            catch parseProblem:
                traceln(`Had trouble loading module: $parseProblem`)
                throw(parseProblem)

def getBootMuffin(makeFileResource) as DeepFrozen:
    def basePath :Str := "mast"
    def petname :Str := "lib/csg"
    def loader := makeFileLoader(basePath, makeFileResource)
    def limo := makeLimo(loader)
    return when (def p := loader(petname)) ->
        def [source :NullOk[Str], expr] := p
        limo(petname, source, expr)
    catch problem:
        traceln.exception(problem)
        throw(problem)

def port :Int := 9876

def main(_argv,
         => currentProcess, => makeProcess,
         => currentRuntime,
         => makeFileResource,
         => Timer,
         => makeTCP4ServerEndpoint) as DeepFrozen:
    currentRuntime.getConfiguration().setLoggingTags([b`serious`, b`process`])
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def ep := makeTCP4ServerEndpoint(port)
    def vp := makeVampEndpoint(currentProcess, makeProcess, b`127.0.0.1`, port)
    def w := 320
    def h := 180
    def solid := study(expandCSG)
    def distributeWork :Bool := false
    def png := if (distributeWork) {
        def which := makeWhich(makeProcess,
                               makePathSearcher(makeFileResource,
                                                currentProcess.getEnvironment()[b`PATH`]))
        def nproc := getNumberOfProcessors(which("nproc"))
        def muffin := getBootMuffin(makeFileResource)
        traceln("Waiting for boot muffin…")
        when (muffin) -> {
            traceln("Got boot muffin!")
            def pool := makeAMPPool(muffin, ep)
            when (pool, nproc) -> {
                traceln(`Pool is ready, starting $nproc workers…`)
                distributedTraceToPNG(Timer, entropy, w, h, solid, vp, pool, nproc)
            }
        }
    } else { localTraceToPNG(Timer, entropy, w, h, solid) }
    when (png) ->
        traceln(`Created PNG of ${png.size()}b`)
        when (makeFileResource("sdf.png")<-setContents(png)) ->
            currentProcess.interrupt()
            0
