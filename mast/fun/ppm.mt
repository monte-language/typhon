exports (makePPM)

# Pixel area: 4 / (w * h)
# Pixel radius: √(area / pi) = 2 / √(w * h * pi) = (2 / √pi) / √(w * h)
# This constant is the first half of that.
def R :Double := 2.0 / (0.0.arcCosine() * 2.0).squareRoot()

def makePPM.drawingFrom(d) as DeepFrozen:
    "
    Draw from drawable/shader `d` repeatedly to form an image.
    "

    return def draw(width :(Int > 0), height :(Int > 0)):
        def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
        def body := [].diverge(0..!256)
        def aspectRatio :Double := width / height
        # See formula for the constant R.
        def pixelRadius :Double := R / (width * height).asDouble().squareRoot()
        var h := 0
        var w := 0

        return object drawingIterable:
            to next(ej):
                if (h >= height) { throw.eject(ej, "done") }
                def color := d.drawAt(w / width, h / height, => aspectRatio,
                                      => pixelRadius)
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
