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
def colorCube(r :Double, g :Double, b :Double) :Bytes as DeepFrozen:
    return if (r < noiseFloor && g < noiseFloor && b < noiseFloor) {
        # Give a true black.
        b`$\x1b[38;5;232m`
    } else { b`$\x1b[38;5;${M.toString(rgb(r, g, b))}m` }

def ramp :Bytes := b` .*+oO0@@`
def getRamp(a :Double) :Bytes as DeepFrozen:
    var i := (a * ramp.size()).floor()
    return if (i == ramp.size()) { ramp.slice(i - 1, i) } else {
        ramp.slice(i, i + 1)
    }

# XXX common code should move up?
def makeSuperSampler(d, => epsilon :Double := 10e-5) as DeepFrozen:
    return def superSampler.drawAt(x :Double, y :Double,
                                   => aspectRatio :Double):
        def color := d.drawAt(x, y, => aspectRatio)
        # NB: Work in linear RGB!
        var channels := color.RGB()
        for dx in ([-1, 1]):
            for dy in ([-1, 1]):
                def c := d.drawAt(x + epsilon * dx, y + epsilon * dy,
                                  => aspectRatio)
                channels := [for i => chan in (c.RGB()) channels[i] + chan]
        return [for chan in (channels) chan * 0.2]

def consoleDraw.drawingFrom(drawable) as DeepFrozen:
    "Draw a drawable `d` to any number of rows of characters."
    def d := makeSuperSampler(drawable)
    return def draw(height :(Int > 0), width :(Int > 0)):
        "Draw a drawable to `height` rows of characters."
        def aspectRatio := width / height
        return [for h in (0..!height) {
            b``.join([for w in (0..!width) {
                def [r, g, b, a] := d.drawAt(w / width, h / height, => aspectRatio)
                colorCube(r, g, b) + getRamp(a)
            }]) + resetColor
        }]
