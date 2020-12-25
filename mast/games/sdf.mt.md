```
import "lib/argv" =~ [=> flags]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/samplers" =~ [=> samplerConfig, => costOfConfig]
import "lib/csg" =~ [=> CSG, => expandCSG, => costOfSolid]
import "lib/promises" =~ [=> makeSemaphoreRef, => makeLoadBalancingRef]
import "lib/muffin" =~ [=> makeFileLoader, => loadTopLevelMuffin]
import "lib/noise" =~ [=> makeSimplexNoise]
import "lib/csg" =~ [=> asSDF, => drawSDF]
import "lib/amp" =~ [=> makeAMPPool]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
import "lib/nproc" =~ [=> getNumberOfProcessors]
import "lib/vamp" =~ [=> makeVampEndpoint]
import "fun/png" =~ [=> makePNG]
exports (main)
```

This module implements a basic raytracer built upon the theory of
[constructive solid
geometry](https://en.wikipedia.org/wiki/Constructive_solid_geometry). We take
expressions in a simple applicative mini-language and compile them into
[signed distance
functions](https://en.wikipedia.org/wiki/Signed_distance_function), this
module's namesake. We then repeatedly evaluate the function in order to
discover where the geometry is and how to illuminate it.

We will need to load Monte source code. We'll load the code as muffin modules,
using the newer loader.

```
def gettingMuffin(makeFileResource) as DeepFrozen:
    return def getMuffin(base :Str, top :Str):
        def loader := makeFileLoader(fn name {
            makeFileResource(`$base/$name`)<-getContents()
        })
        return loadTopLevelMuffin(loader, top)
```

We need two copies of the pixel-scheduling loop. The first copy is distributed
and shares work across many subprocesses. It's not (yet) fast enough to make
up for overhead, though, so it's disabled by default.

```
def copyCSGTo(ref) as DeepFrozen:
    return object copier:
        match [verb, args, namedArgs]:
            M.send(ref, verb, args, namedArgs)

def distributedTraceToPNG(Timer, entropy, width :Int, height :Int, config, solid, vp, pool, nproc) as DeepFrozen:
    traceln(`Tracing solid with $nproc workers: $solid`)
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

def port :Int := 9876
```

And we have a local pixel-scheduler which simply runs every pixel, one by one,
in a tight loop.

```
def localTraceToPNG(Timer, entropy, width :Int, height :Int, config, solid) as DeepFrozen:
    traceln(`Tracing solid locally: $solid`)
    def cost := config(costOfConfig) * solid(costOfSolid) * width * height
    traceln(`Cost: $cost (log-cost: ${cost.asDouble().logarithm()})`)
    # Prepare some noise. lib/noise explains how to do this.
    def indices := entropy.shuffle(_makeList.fromIterable(0..!(2 ** 10)))

    def drawableRef := drawSDF(solid(asSDF(makeSimplexNoise.fromShuffledIndices(indices))))
    def drawer := makePNG.drawingFrom(drawableRef, config)(width, height)

    # Just run every pixel at once, and then monitor progress in callbacks.
    def start := Timer.unsafeNow()
    var i := 0
    while (true):
        drawer.next(__break)
        i += 1
        if (i % 2000 == 0):
            def duration := Timer.unsafeNow() - start
            def pixelsPerSecond := i / duration
            def timeRemaining := ((width * height) - i) / pixelsPerSecond
            def normPixels := `(${(pixelsPerSecond * cost).logarithm()} work/s)`
            traceln(`Status: ${(i * 100) / (width * height)}% ($pixelsPerSecond px/s) $normPixels (${timeRemaining}s left)`)
    return drawer.finish()
```

Our entrypoint sets up a context, loads the desired geometry from a Monte
module, and starts rendering.

```
def main(argv,
         => currentProcess, => makeProcess,
         => currentRuntime,
         => makeFileResource,
         => Timer,
         => makeTCP4ServerEndpoint) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    var outPath := "sdf.png"
    var w := 160
    var h := 100
    var distributeWork :Bool := false
    var config := samplerConfig.Center()
    def parser := flags () out path {
        outPath := path
    } size s {
        def `@{via (_makeInt) nw}x@{via (_makeInt) nh}` := s
        # Dimensions can only be assigned atomically.
        w := nw
        h := nh
    } supersample count {
        # NB: Since we have no runtime randomness in our SDF and texturing,
        # the correct way to get a smoothly dithered antialiasing is to use
        # QMC rather than a fixed pattern; otherwise, we'll see the pattern in
        # every smooth surface.
        config := samplerConfig.QuasirandomMonteCarlo(_makeInt(count))
    } multiprocess {
        distributeWork := true
    }
    def [_, _, csgBase :Str, csgName :Str] := parser(argv)
    traceln(`Will load $csgName from $csgBase and render ${w}x$h PNG to $outPath (multiprocessing? $distributeWork)`)
    traceln(`Sampling configuration: $config`)
    def getMuffin := gettingMuffin(makeFileResource)
    def csgSource := getMuffin(csgBase, csgName)
    def solid := when (csgSource) -> {
        def csgModule := eval(csgSource, safeScope)
        csgModule(null, => CSG)["geometry"](expandCSG)
    }
    def png := if (distributeWork) {
        # Debug subprocessing.
        currentRuntime.getConfiguration().setLoggingTags([b`serious`, b`process`])
        def ep := makeTCP4ServerEndpoint(port)
        def vp := makeVampEndpoint(currentProcess, makeProcess, b`127.0.0.1`, port)
        def which := makeWhich(makeProcess,
                               makePathSearcher(makeFileResource,
                                                currentProcess.getEnvironment()[b`PATH`]))
        def nproc := getNumberOfProcessors(which("nproc"))
        def muffin := getMuffin("mast", "lib/csg")
        traceln("Waiting for boot muffin…")
        when (muffin) -> {
            traceln("Got boot muffin!")
            def pool := makeAMPPool(muffin, ep)
            when (solid, pool, nproc) -> {
                traceln(`Pool is ready, starting $nproc workers…`)
                distributedTraceToPNG(Timer, entropy, w, h, config, solid, vp, pool, nproc)
            }
        }
    } else {
        when (solid) -> { localTraceToPNG(Timer, entropy, w, h, config, solid) }
    }
    return when (png) ->
        traceln(`Created PNG of ${png.size()}b`)
        when (makeFileResource(outPath)<-setContents(png)) ->
            # If we have subprocesses, then we'll just kill ourselves and
            # that'll kill them too.
            if (distributeWork) { currentProcess.interrupt() }
            0
```
