import "lib/iterators" =~ [=> zip]
exports (compassSearch)

# https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.96.8672&rep=rep1&type=pdf

def boundCheck(lower :List[Double], upper :List[Double]) as DeepFrozen:
    return def check(middle :List[Double]) :Bool as DeepFrozen:
        for [l, m, u] in (zip(lower, middle, upper)):
            if (l > m || m > u):
                return false
        return true

def compassSearch(f, row :List[Double],
                  => epsilon :Double := 1e-7,
                  => lowerBounds :List[Double] := [-Infinity] * row.size(),
                  => upperBounds :List[Double] := [Infinity] * row.size()) as DeepFrozen:
    "
    Given a function on Doubles `f` which returns a Double, and a `row` of
    arguments which already are valid for `f`, return a row which minimizes
    `f`, or at least is no worse than `row`.

    The search will respect `lowerBounds` and `upperBounds` for each argument.
    "

    def check := boundCheck(lowerBounds, upperBounds)
    def call(r):
        return M.call(f, "run", r, [].asMap())
    var best := call(row)
    var rv := row
    # Customization: If we take five steps in a row, try growing k. It cannot
    # hurt more than one iteration. ~ C.
    var k := epsilon * (2.0 ** 24)
    var gallop := 0
    def consider(d, cont):
        if (check(d) && (def cd := call(d)) < best):
            gallop += 1
            if (gallop >= 5):
                gallop := 0
                k *= 2.0
            rv := d
            best := cd
            cont()

    while (k >= epsilon):
        def cont := __continue
        for i => x in (rv):
            consider(rv.with(i, x + k), cont)
            consider(rv.with(i, x - k), cont)
        gallop := 0
        k *= 0.5
    return rv
