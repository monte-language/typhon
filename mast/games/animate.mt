import "fun/mcurses" =~ [=> activateTerminal]
import "fun/shapes" =~ [=> triangle]
import "lib/colors" =~ [=> composite, => pd, => makeColor]
import "lib/console" =~ [=> consoleDraw]
import "lib/entropy/entropy" =~ [=> makeEntropy]
exports (main)

def N :Int := 2**4
def makeMMASlot(var v) as DeepFrozen:
    return object MMASlot:
        to get():
            return v
        to put(x):
            v := ((N - 1) * v + x) / N

def makePath(var x :Double, var dx :Double) as DeepFrozen:
    return def path.advance(t :Double) :Double:
        x += dx * t
        if (x < 0.0) { dx :=   dx.abs()  }
        if (x > 1.0) { dx := -(dx.abs()) }
        return x

def makeTriangle.withEntropy(entropy) as DeepFrozen:
    def color := M.call(makeColor, "RGB", [for _ in (0..!4) {
        1.0 - entropy.nextExponential(7.0)
    }], [].asMap())
    def paths := [for _ in (0..!6) {
        makePath(entropy.nextDouble(), entropy.nextExponential(5.0))
    }]

    return def advanceTri(t):
        return M.call(triangle, "run",
                      [color] + [for p in (paths) p.advance(t)], [].asMap())

def drawOnto(height, width, drawable, cursor, header) as DeepFrozen:
    def [_] + rows := consoleDraw.drawingFrom(drawable)(height, width)
    # Draw only once, by compositing the header on top of the first row.
    def headed := if (header.size() > width) { header.slice(0, width) } else {
        header + b` ` * (width - header.size())
    }
    return promiseAllFulfilled([
        cursor<-clear(),
        cursor<-move(0, 0),
        cursor<-write(b``.join([headed] + rows)),
    ])

def startCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-enterAltScreen(), cursor<-hideCursor()) -> { null }

def stopCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-showCursor(), cursor<-leaveAltScreen()) -> { null }

def FPS_LIMIT :Double := 60.0

def main(_argv, => currentRuntime, => stdio, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def [tri] + tris := [for _ in (0..!5) makeTriangle.withEntropy(entropy)]
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    var stop := false
    var target :Double := FPS_LIMIT
    def &renderingTime := makeMMASlot(100.0)
    def &fps := makeMMASlot(target)
    def go(t):
        if (stop) { return }
        fps := t.reciprocal()
        var drawable := tri(t)
        for tri in (tris):
            drawable := pd(drawable, tri(t), composite.over)
        def header := b`  `.join([
            b`Hello from the other side`,
            b`FPS: ${M.toString(fps)}/${M.toString(target)}`,
            # XXX Monte parser bug: I can't start this long out-of line with
            # ${ and have to instead start it with a (.
            b`Rendering time per fragment: ${M.toString(
                (renderingTime / (term.width() * term.height())).floor()
            )}us`,
        ])
        def p := Timer.measureTimeTaken(fn {
            drawOnto(term.height(), term.width(), drawable, cursor, header)
        })
        when (p) ->
            def [_, rt] := p
            renderingTime := rt * 1_000_000
            # Geometric mean of target and FPS, rendering time is
            # seconds/frame so is already reciprocated
            target := (target.reciprocal() + rt).reciprocal() * 2
            # Buuuut! Hard-clamp at 60.
            if (target > FPS_LIMIT) { target := FPS_LIMIT }
            when (def d := Timer.fromNow(target.reciprocal())) -> { go<-(d) }
    return when (startCanvasMode<-(cursor)) ->
        go(1.0)
        when (Timer.fromNow(60.0)) ->
            stop := true
            when (stopCanvasMode<-(cursor), term<-quit()) -> { 0 }
