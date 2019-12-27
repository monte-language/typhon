exports (consoleDraw)

# Console (emulator) drawing utilities.

def resetColor :Bytes := b`$\x1b[0m`

# Color modelling: RGB channels are mapped onto the 216-color cube, with six
# intensity levels per channel.
# Whoever laid out the ANSI codes was aware of the vague concept of doing
# things with bitmasks. Thanks!
def intensity(x :Double) :Int as DeepFrozen:
    return (x * 6).floor()
def rgb(r :Double, g :Double, b :Double) :Int as DeepFrozen:
    return 16 + 36 * intensity(r) + 6 * intensity(g) + intensity(b)
def noiseFloor :Double := 10e-2
def color(r :Double, g :Double, b :Double) :Bytes as DeepFrozen:
    return if (r < noiseFloor && g < noiseFloor && b < noiseFloor) {
        # Give a true black.
        b`$\x1b[38;5;232m`
    } else { b`$\x1b[38;5;${M.toString(rgb(r, g, b))}m` }

# XXX common code should move up?
def makeSuperSampler(d, => epsilon :Double := 10e-6) as DeepFrozen:
    return def superSampler.drawAt(x :Double, y :Double):
        def [var r, var g, var b] := d.drawAt(x, y)
        for dx in ([-1, 1]):
            for dy in ([-1, 1]):
                def [dr, dg, db] := d.drawAt(x + epsilon * dx,
                                             y + epsilon * dy)
                r += dr
                g += dg
                b += db
        # Is it HDR if we don't clamp?
        return [r * 0.2, g * 0.2, b * 0.2]

def consoleDraw.drawingFrom(drawable) as DeepFrozen:
    "Draw a drawable `d` to any number of rows of characters."
    def d := makeSuperSampler(drawable)
    return def draw(height :(Int > 0), width :(Int > 0)):
        "Draw a drawable to `height` rows of characters."
        def aspectRatio := width / height
        return [for h in (0..!height) {
            b``.join([for w in (0..!width) {
                def [r, g, b] := d.drawAt(w / width, h / height,
                                          => aspectRatio)
                color(r, g, b) + b`#`
            }]) + resetColor
        }]
