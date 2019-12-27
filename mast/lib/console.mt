exports (consoleDraw)

# Console (emulator) drawing utilities.

def resetColor :Bytes := b`$\x1b[0m`

# Color modelling: RGB channels can be at three different intensity levels:
# Absent, present, lots. If lots, then use bold and only lots channels;
# otherwise, use present channels.
# Whoever laid out the ANSI codes was aware of the vague concept of doing
# things with bitmasks. Thanks!
def rgb(r :Bool, g :Bool, b :Bool) :Bytes as DeepFrozen:
    def i := 0x30 + (r.pick(1, 0) | g.pick(2, 0) | b.pick(4, 0))
    return _makeBytes.fromInts([i])
def plainColor(c :Bytes) :Bytes as DeepFrozen:
    return b`$\x1b[3` + c + b`m`
def boldColor(c :Bytes) :Bytes as DeepFrozen:
    return b`$\x1b[9` + c + b`m`

# Gentle cross-hatching with isotropic characters. Ramp length of 6 is
# important for index maths later on.
def hatchRamp :Bytes := b` .o+X#`

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

def consoleDraw.drawingFrom(d) as DeepFrozen:
    "Draw a drawable `d` to any number of rows of characters."
    # def d := makeSuperSampler(drawable)
    return def draw(height :(Int > 0), width :(Int > 0)):
        "Draw a drawable to `height` rows of characters."
        def aspectRatio := width / height
        return [for h in (0..!height) {
            b``.join([for w in (0..!width) {
                def [r, g, b] := d.drawAt(w / width, h / height,
                                          => aspectRatio)
                def sum := r + g + b
                # XXX gamma?
                if (r > 0.5 || g > 0.5 || b > 0.5) {
                    # Lots. 0.5 < sum < 3.0, so 0 < sum * 2 - 1 < 5
                    def i := (sum * 2 - 1).floor().min(5)
                    boldColor(rgb(r > 0.5, g > 0.5, b > 0.5)) + hatchRamp[i]
                } else {
                    # Absent/present. 0.0 < sum < 1.5, so 0 < sum * 10 / 3 < 5
                    def i := (sum / 0.3).floor()
                    plainColor(rgb(r > 0.1, g > 0.1, b > 0.1)) + hatchRamp[i]
                }
            }]) + resetColor
        }]
