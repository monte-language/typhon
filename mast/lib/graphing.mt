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
    "

    def canvas := [for _ in (0..!height) ([' '] * width).diverge()]
    def sx := (x2 - x1) / width
    def sy := (y2 - y1) / height
    for column in (0..!width):
        # Note that we do the viewport transformations inverted after going
        # through f(), changing multiplication to division and addition to
        # subtraction.
        def ys := [for i in (0..!glyphsSize) {
            # If f() isn't defined on the interval, then that's fine; just NaN
            # instead, and we'll handle NaN in a moment.
            try { f(column * sx + (0.05 * i) + x1) } catch _ { NaN }
        }]
        # The viewport is upside-down, remember?
        def superrows := [for y in (ys) ? (y != NaN) {
            ((height - ((y - y1) / sy)) * glyphsSize).floor()
        }]
        def rows := [for sr in (superrows)
                     ? (sr.atLeastZero() && sr < canvas.size() * glyphsSize) {
            sr // glyphsSize
        }].asSet()
        for row in (rows):
            def subrows := [for sr in (superrows) {
                if (sr.divMod(glyphsSize) =~ [==row, subrow]) { subrow }
            }]
            canvas[row][column] := glyphs[subrows]
    return [for row in (canvas) _makeStr.fromChars(row)]
