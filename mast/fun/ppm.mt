exports (packPPM)

def packPPM(width :Int, height :Int,
            framebuffer :List[List[Double]] ? (framebuffer.size() == width * height)) as DeepFrozen:
    def preamble := b`P6$\n${M.toString(width)} ${M.toString(height)}$\n255$\n`
    def body := [].diverge()
    for c in (framebuffer):
        def max := c[0].max(c[1]).max(c[2])
        def s := if (max > 1.0) { [for comp in (c) comp / max] } else { c }
        for x in (s):
            body.push((255 * x.min(1.0).max(0.0)).floor())
    return preamble + _makeBytes.fromInts(body)
