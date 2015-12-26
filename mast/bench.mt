imports
exports (main)

def [=> UTF8 :DeepFrozen] | _ := import.script("lib/codec/utf8")

def benchmarks :List[Str] := [
    "brot",
    "marley",
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

def makeFakeStdOut() as DeepFrozen:
    return object fakeStdOut:
        to flowingFrom(_):
            null

        to receive(_):
            null

def main(=> bench, => makeFileResource, => unittest) as DeepFrozen:
    traceln(`Benchmark time!`)

    var benches :Map[Str, Any] := [].asMap()
    def benchCollector(moduleName):
        return def innerCollector(runnable, name :Str):
            benches with= (`$moduleName: $name`, runnable)

    for benchmark in benchmarks:
        traceln(`Importing $benchmark`)
        def module := import(`bench/$benchmark`)
        traceln(`Running $benchmark`)
        module["main"]("bench" => benchCollector(benchmark),
                       "makeStdOut" => makeFakeStdOut, => unittest)

    traceln(`Preparing report`)
    var pieces :List[Str] := []

    pieces with= (`<!doctype HTML>
    <head>
    <title>Monte Benchmarks</title>
    </head>
    <body>
    <h1>Benchmarks</h1>
    <ul>`)

    for label => runner in benches:
        def [loops :Int, duration :Double] := bench(runner, label)
        def formatted :Str := formatResults(loops, duration)
        pieces with= (`<li><em>$label</em>: $formatted/iteration</li>`)
        # traceln(`Took $loops loops in $duration seconds ($formatted/iteration)`)

    pieces with= (`</ul>
    </body>`)

    def html := UTF8.encode("".join(pieces), null)

    return when (makeFileResource("bench.html").setContents(html)) ->
        0
