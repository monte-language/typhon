exports (makePPM)

def makePPM.drawingFrom(d) as DeepFrozen:
    "
    Draw from drawable/shader `d` repeatedly to form an image.
    "
    return def draw(width :(Int > 0), height :(Int > 0)):
        def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
        def body := [].diverge(0..!256)
        def aspectRatio :Double := width / height
        for h in (0..!height):
            for w in (0..!width):
                def color := d.drawAt(w / width, h / height, => aspectRatio)
                def [r, g, b, _] := color.sRGB()
                body.push((255 * r).floor())
                body.push((255 * g).floor())
                body.push((255 * b).floor())
        return preamble + _makeBytes.fromInts(body)
