exports (calculateGraph)

# "Graphing" calculators are ubiquitous in USA engineering culture.

# Subglyph sampling: Break row into two-high subrows and subcolumns.
def glyphs :Map[List[NullOk[Int]], Char] := [
    [0   , 0   ] => '-',
    [0   , 1   ] => '\\',
    [1   , 0   ] => '/',
    [1   , 1   ] => '_',
    [0   , null] => '\'',
    [1   , null] => ',',
    [null, 0   ] => '`',
    [null, 1   ] => '.',
]

def glyphsSize :Int := 2

def calculateGraph(f, height :Int, width :Int, x1 :Double, y1 :Double,
                   x2 :(Double > x1), y2 :(Double > y1)) :List[Str] as DeepFrozen:
    "
    Draw `f`, a function on Doubles, on a canvas of whitespace.

    The canvas will be `height` by `width` characters, with viewport from
    `[x1, y1]` to `[x2, y2]`. Aspect ratio must be double-checked manually by
    the caller.

    The canvas will also get axes and undefined regions indicated with lines
    and shading.
    "

    # NB: The viewport is upside-down.

    def canvas := [for _ in (0..!height) ([' '] * width).diverge()]
    def sx := (x2 - x1) / width
    def sy := (y2 - y1) / height

    def y2sr(y :Double) :Int:
        if (y == NaN) { throw("nope") }
        # Remember to flip here.
        return ((height - ((y - y1) / sy)) * glyphsSize).floor()

    # Draw x=0.
    def x0 := (-x1 / sx).floor()
    if (0 <= x0 && x0 < width):
        for row in (0..!height):
            canvas[row][x0] := '|'

    # Draw y=0.
    def y0 := (-y1 / sy).floor()
    if (0 <= y0 && y0 < height):
        for column in (0..!width):
            canvas[y0][column] := '='

    # Draw the origin.
    if (0 <= x0 && 0 <= y0 && x0 < width && y0 < height):
        canvas[y0][x0] := '+'

    for column in (0..!width):
        try:
            # Note that we do the viewport transformations inverted after going
            # through f(), changing multiplication to division and addition to
            # subtraction.
            def ys := [for i in (0..!glyphsSize) {
                f(column * sx + (0.05 * i) + x1)
            }]
            def superrows := [for y in (ys) y2sr(y)]
            def rows := [for sr in (superrows)
                         ? (sr.atLeastZero() && sr < canvas.size() * glyphsSize) {
                sr // glyphsSize
            }].asSet()
            for row in (rows):
                def subrows := [for sr in (superrows) {
                    if (sr.divMod(glyphsSize) =~ [==row, subrow]) { subrow }
                }]
                canvas[row][column] := glyphs[subrows]
        catch _:
            # We either got a NaN, or f() threw an exception; maybe we're not
            # defined on this range. And that's okay!
            for row in (0..!height):
                canvas[row][column] := 'X'
    return [for row in (canvas) _makeStr.fromChars(row)]
