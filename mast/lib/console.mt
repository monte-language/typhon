import "lib/samplers" =~ [=> samplerConfig, => makeDiscreteSampler]
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
# XXX true greys?
def colorCube(r :Double, g :Double, b :Double) :Bytes as DeepFrozen:
    return b`$\x1b[38;5;${M.toString(rgb(r, g, b))}m`

def ramp :Bytes := b` .*+oO0@@`
def getRamp(a :Double) :Bytes as DeepFrozen:
    var i := (a * ramp.size()).floor()
    return if (i == ramp.size()) { ramp.slice(i - 1, i) } else {
        ramp.slice(i, i + 1)
    }

def consoleDraw.drawingFrom(d) as DeepFrozen:
    "Draw a drawable `d` to any number of rows of characters."

    # Pixel sample location: One sample drawn right in the middle of each
    # bounding box. Super-rough.
    def config :DeepFrozen := samplerConfig.Center()
    # def config :DeepFrozen := samplerConfig.Quincunx()

    return def draw(height :(Int > 0), width :(Int > 0)):
        "Draw a drawable to `height` rows of characters."

        def discreteSampler := makeDiscreteSampler(d, config, width, height)
        return [for h in (0..!height) {
            b``.join([for w in (0..!width) {
                def color := discreteSampler.pixelAt(w, h)
                def [r, g, b, a] := color.sRGB()
                colorCube(r, g, b) + getRamp(a)
            }]) + resetColor
        }]
