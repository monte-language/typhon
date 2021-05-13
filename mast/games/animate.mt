import "fun/mcurses" =~ [=> activateTerminal]
import "lib/colors" =~ [=> makeColor]
import "lib/console" =~ [=> consoleDraw]
import "lib/entropy/entropy" =~ [=> makeEntropy]
import "lib/vectors" =~ [=> V, => glsl]
exports (main)

def nextColor(entropy) as DeepFrozen:
    "Choose random bright pastel colors."

    return makeColor.RGB(
        1.0 - entropy.nextExponential(7.0),
        1.0 - entropy.nextExponential(7.0),
        1.0 - entropy.nextExponential(7.0),
        1.0)

# From John Buffer's NoCol:
# https://github.com/johnBuffer/NoCol/blob/d60bc4029186dac888a96b38a7410e81aea89471/src/main.cpp#L97-L123

def makeNoColSimulation.withEntropy(entropy) as DeepFrozen:
    "Simulate particle-like collisions."

    # A ball is a tuple [color, radius, position, velocity]. We use the fact
    # that the first two elements are immutable to produce pairs for maps:
    var balls := [for _ in (0..!5) {
        [nextColor(entropy), entropy.nextDouble() / 10]
    } => {
        [V(entropy.nextDouble(), entropy.nextDouble()),
         V(entropy.nextDouble(), entropy.nextDouble()) / 25]
    }]
    # The amount of collision that a ball has recently experienced. Set to 1.0
    # after collision and decays with time.
    def collided := [for k => _ in (balls) k => 0.0].diverge()

    def center := V(0.5, 0.5)

    def simulation.advance(t :Double):
        # Take a timestep.
        balls := [for k => [position, velocity] in (balls) k => {
            def scale := 0.05 * t
            collided[k] := 0.0.max(collided[k] - scale)
            def dp := velocity * scale
            def dv := (center - position) * scale
            [position + dp, velocity + dv]
        }]

        # Look for collisions, and improve them.
        def bs := balls.diverge()
        for k1 => _ in (balls):
            for k2 => _ in (balls):
                if (k1 == k2):
                    continue
                def [_, r1] := k1
                def [_, r2] := k2
                def [p1, v1] := bs[k1]
                def [p2, v2] := bs[k2]
                def diff := p2 - p1
                def dist := (r1 + r2) ** 2 - glsl.dot(diff, diff)
                if (dist.atLeastZero()):
                    def dp := glsl.normalize(diff) * 0.5 * dist
                    bs[k1] := [p1 - dp, v1]
                    bs[k2] := [p2 + dp, v2]
                    collided[k1] := collided[k2] := 1.0
        balls := bs.snapshot()

    def simDrawable.drawAt(x :Double, y :Double):
        # Find the nearest ball, and return that color.
        def v := V(x, y)
        var bestDist := Infinity
        var bestColor := makeColor.clear()
        for [color, radius] => [position, _] in (balls):
            def diff := (v - position).abs()
            # Avoid a square root.
            def dist := radius ** 2 - glsl.dot(diff, diff)
            if (dist.atLeastZero() && dist < bestDist):
                bestDist := dist
                def collidedRecently := collided[[color, radius]]
                bestColor := if (collidedRecently.aboveZero()) {
                    makeColor.RGB(1.0, 1.0, 1.0, 1.0)
                } else { color }
        return bestColor

    return [simulation, simDrawable]

def drawOnto(height, width, drawable, cursor, header) as DeepFrozen:
    # Don't even render on the first row.
    def rows := consoleDraw.drawingFrom(drawable)(height - 1, width)
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

def N :Int := 2**1
def makeMMASlot(var v) as DeepFrozen:
    return object MMASlot:
        to get():
            return v
        to put(x):
            v := ((N - 1) * v + x) / N

def main(_argv, => currentRuntime, => stdio, => Timer) as DeepFrozen:
    def entropy := makeEntropy(currentRuntime.getCrypt().makeSecureEntropy())
    def [animation, drawable] := makeNoColSimulation.withEntropy(entropy)
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    var stop := false
    var target :Double := FPS_LIMIT
    def &renderingTime := makeMMASlot(100.0)
    def &fps := makeMMASlot(target)
    def go(t):
        if (stop) { return }
        fps := t.reciprocal()
        animation.advance(t)
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
        when (Timer.fromNow(90.0)) ->
            stop := true
            when (stopCanvasMode<-(cursor), term<-quit()) -> { 0 }
