import "fun/mcurses" =~ [=> activateTerminal]
import "fun/shapes" =~ [=> triangle]
import "lib/console" =~ [=> consoleDraw]
import "lib/entropy/entropy" =~ [=> makeEntropy]
exports (main)

# Plan:
# Uncook
# Get canvas size
# Draw triangle onto canvas
# Put paths onto triangle corners
# Wait for like 10s
# But also, wait for like 100ms
# And then advance the paths and redraw
# Recook
# Exit

def makePath(var x :Double, var dx :Double) as DeepFrozen:
    return def path.advance(t :Double) :Double:
        x += dx * t
        if (x < 0.0) { dx :=   dx.abs()  }
        if (x > 1.0) { dx := -(dx.abs()) }
        return x

def N :Int := 2**5
def makeFrameCounter() as DeepFrozen:
    var fps := 1.0
    return def counter.observe(t):
        return fps := ((N - 1) * fps + (t.reciprocal().floor())) / N

def target :Double := 60.0
def drawOnto(height, width, t, cursor, paths, fps) as DeepFrozen:
    def d := M.call(triangle, "run", [for p in (paths) p.advance(t)], [].asMap())
    def rows := consoleDraw.drawingFrom(d)(height, width)
    return promiseAllFulfilled([
        cursor<-clear(),
        cursor<-move(0, 0),
        cursor<-write(b``.join(rows)),
        cursor<-move(0, 0),
        cursor<-write(b`Hello from the other side  FPS: ${M.toString(fps)}/${M.toString(target)}`),
    ])

def startCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-enterAltScreen(), cursor<-hideCursor()) -> { null }

def stopCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-showCursor(), cursor<-leaveAltScreen()) -> { null }

def main(_argv, => currentRuntime, => stdio, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def paths := [for _ in (0..!6) {
        makePath(entropy.nextDouble(), entropy.nextExponential(5.0))
    }]
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    def counter := makeFrameCounter()
    var stop := false
    def go(t):
        if (stop) { return }
        def fps := counter.observe(t)
        when (drawOnto(term.height(), term.width(), t, cursor, paths, fps)) ->
            when (def d := Timer.fromNow(target.reciprocal())) -> { go<-(d) }
    return when (startCanvasMode<-(cursor)) ->
        go(1.0)
        when (Timer.fromNow(60.0)) ->
            stop := true
            when (stopCanvasMode<-(cursor), term<-quit()) -> { 0 }
