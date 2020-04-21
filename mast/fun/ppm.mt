import "lib/samplers" =~ [=> makeDiscreteSampler]
exports (makePPM)

def makePPM.drawingFrom(drawable, config) as DeepFrozen:
    "
    Draw from `drawable` repeatedly to form an image.

    `config` should be a sampling configuration.
    "

    return def draw(width :(Int > 0), height :(Int > 0)):
        def discreteSampler := makeDiscreteSampler(drawable, config, width, height)

        def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
        def body := [].diverge(0..!256)
        var h := 0
        var w := 0

        return object drawingIterable:
            to next(ej):
                if (h >= height) { throw.eject(ej, "done") }
                def color := discreteSampler.pixelAt(w, h)
                def [r, g, b, _] := color.sRGB()
                body.push((255 * r).floor())
                body.push((255 * g).floor())
                body.push((255 * b).floor())
                w += 1
                if (w >= width):
                    w -= width
                    h += 1

            to finish():
                return preamble + _makeBytes.fromInts(body)
