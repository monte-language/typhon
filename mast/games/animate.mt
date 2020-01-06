import "fun/mcurses" =~ [=> activateTerminal]
import "fun/shapes" =~ [=> triangle]
import "lib/colors" =~ [=> composite, => pd]
import "lib/console" =~ [=> consoleDraw]
import "lib/entropy/entropy" =~ [=> makeEntropy]
exports (main)

def target :Double := 60.0
def N :Int := 2**5
def makeFrameCounter() as DeepFrozen:
    var fps := 1.0
    return def counter.observe(t):
        return fps := ((N - 1) * fps + (t.reciprocal().floor())) / N

def makePath(var x :Double, var dx :Double) as DeepFrozen:
    return def path.advance(t :Double) :Double:
        x += dx * t
        if (x < 0.0) { dx :=   dx.abs()  }
        if (x > 1.0) { dx := -(dx.abs()) }
        return x

def makeTriangle.withEntropy(entropy) as DeepFrozen:
    def paths := [for _ in (0..!6) {
        makePath(entropy.nextDouble(), entropy.nextExponential(5.0))
    }]

    return def advanceTri(t):
        return M.call(triangle, "run", [for p in (paths) p.advance(t)], [].asMap())

def drawOnto(height, width, drawable, cursor, fps, renderingTime) as DeepFrozen:
    def rows := consoleDraw.drawingFrom(drawable)(height, width)
    return promiseAllFulfilled([
        cursor<-clear(),
        cursor<-move(0, 0),
        cursor<-write(b``.join(rows)),
        cursor<-move(0, 0),
        cursor<-write(b`Hello from the other side  FPS: ${M.toString(fps)}/${M.toString(target)}  Rendering time: ${M.toString(renderingTime.floor())}ms`),
    ])

def startCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-enterAltScreen(), cursor<-hideCursor()) -> { null }

def stopCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-showCursor(), cursor<-leaveAltScreen()) -> { null }

def main(_argv, => currentRuntime, => stdio, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def [tri] + tris := [for _ in (0..!2) makeTriangle.withEntropy(entropy)]
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    def counter := makeFrameCounter()
    var stop := false
    var renderingTime := 0.0
    def go(t):
        if (stop) { return }
        def fps := counter.observe(t)
        var drawable := tri(t)
        for tri in (tris):
            drawable := pd(drawable, tri(t), composite.over)
        def p := Timer.measureTimeTaken(fn {
            drawOnto(term.height(), term.width(), drawable, cursor, fps,
                     renderingTime)
        })
        when (p) ->
            def [_, rt] := p
            renderingTime := rt * 1000
            when (def d := Timer.fromNow(target.reciprocal())) -> { go<-(d) }
    return when (startCanvasMode<-(cursor)) ->
        go(1.0)
        when (Timer.fromNow(120.0)) ->
            stop := true
            when (stopCanvasMode<-(cursor), term<-quit()) -> { 0 }
