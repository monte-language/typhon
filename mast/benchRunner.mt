import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
exports (runBenchmarks)

def benchmarks :List[Str] := [
    "brot",
    # XXX stack overflow? "marley",
    "montstone",
    "nqueens",
    "primeCount",
    "richards",
]

def formatResults(loops :Int, duration :Double) :Str as DeepFrozen:
    def usec := duration * 1000000 / loops
    if (usec < 1000):
        return `$usec μs`
    else:
        def msec := usec / 1000
        if (msec < 1000):
            return `$msec ms`
        else:
            def sec := msec / 1000
            return `$sec s`

def runBenchmarks(benchmarks, bench, benchFile) as DeepFrozen:
    traceln(`Preparing report`)
    var pieces :List[Str] := []

    pieces with= (`<!doctype HTML>
    <head>
    <title>Monte Benchmarks</title>
    </head>
    <body>
    <h1>Benchmarks</h1>
    <ul>`)

    for [label, runner] in benchmarks:
        def [loops :Int, duration :Double] := bench(runner, label)
        def formatted :Str := formatResults(loops, duration)
        pieces with= (`<li><em>$label</em>: $formatted/iteration</li>`)
        # traceln(`Took $loops loops in $duration seconds ($formatted/iteration)`)

    pieces with= (`</ul>
    </body>`)

    def html := UTF8.encode("".join(pieces), null)

    return benchFile.setContents(html)
