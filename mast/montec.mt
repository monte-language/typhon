import "lib/argv" =~ [=> flags]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [=> parseModule :DeepFrozen]
import "lib/monte/monte_expander" =~ [=> expand :DeepFrozen]
import "lib/monte/monte_optimizer" =~ [=> optimize :DeepFrozen]
import "lib/streams" =~ [=> alterSink :DeepFrozen,
                         => flow :DeepFrozen,
                         => makeSink :DeepFrozen]
import "lib/monte/monte_verifier" =~ [
    => findUndefinedNames :DeepFrozen,
    => findUnusedNames :DeepFrozen,
    => findSingleMethodObjects :DeepFrozen,
]

exports (main)

def makeStopwatch(timer) as DeepFrozen:
    return def stopwatch(f, => source :NullOk[Str] := null):
        return object stopwatchProxy:
            match message:
                def p := timer.measureTimeTaken(fn {
                    M.callWithMessage(f, message)
                })
                when (p) ->
                    def [rv, timeTaken] := p
                    if (source == null):
                        traceln(`stopwatch: $f took ${timeTaken}s`)
                    else:
                        traceln(`stopwatch: $source: $f took ${timeTaken}s`)
                    rv

def runPipeline(starter, [var stage] + var stages) as DeepFrozen:
    var rv := when (starter) -> { stage<-(starter) }
    for s in (stages):
        rv := when (def p := rv) -> { s<-(p) }
    return rv

def parseArguments(var argv, ej) as DeepFrozen:
    var useMixer :Bool := false
    var verify :Bool := true
    var terseErrors :Bool := false
    var justLint :Bool := false
    var readStdin :Bool := false
    var muffinPath :NullOk[Str] := null

    # Parse argv.
    def parser := flags () mix {
        useMixer := true
    } noverify {
        verify := false
    } terse {
        terseErrors := true
    } lint {
        justLint := true
    } stdin {
        readStdin := true
    } muffin path {
        muffinPath := path
    }
    def arguments :List[Str] := parser(argv)

    def inputFile
    def outputFile

    if (justLint):
        bind outputFile := null
        if (arguments !~ [bind inputFile]):
            throw.eject(ej, "Usage: montec -lint [-noverify] [-terse] inputFile")
    else if (arguments !~ [bind inputFile, bind outputFile]):
        throw.eject(ej, "Usage: montec [-mix] [-noverify] [-terse] inputFile outputFile")

    return object configuration:
        to useMixer() :Bool:
            return useMixer

        to justLint() :Bool:
            return justLint

        to verify() :Bool:
            return verify

        to terseErrors() :Bool:
            return terseErrors

        to getInputFile() :Str:
            return inputFile

        to getOutputFile() :NullOk[Str]:
            return outputFile

        to readStdin() :Bool:
            return readStdin

        to muffinPath() :NullOk[Str]:
            return muffinPath


def expandTree(tree) as DeepFrozen:
    return expand(tree, astBuilder, throw)

def serialize(tree) as DeepFrozen:
    def context := makeMASTContext()
    context(tree)
    return context.bytes()

def makeMuffin(loader) as DeepFrozen:
    return def muffin(mod):
        traceln(`Got muffin request! Loader is $loader`)
        return mod


def main(argv,
         => Timer, => makeFileResource,
         => stdio) :Vow[Int] as DeepFrozen:
    def config := parseArguments(argv, throw)
    def inputFile := config.getInputFile()
    def outputFile := config.getOutputFile()

    def stopwatch := makeStopwatch(Timer)

    def stdout := alterSink.encodeWith(UTF8, stdio.stdout())

    def parse(data :Str):
        "Parse and verify a Monte source file."

        def tree
        def lex := makeMonteLexer(data, inputFile)
        escape e {
            bind tree := parseModule(lex, astBuilder, e)
        } catch parseError {
            stdout(
                if (config.terseErrors()) {
                    inputFile + ":" + parseError.formatCompact() + "\n"
                } else {parseError.formatPretty()})

            throw("Syntax error")
        }
        return [lex, tree]

    def verify([lex, tree]):
        def stdout := stdio.stdout()
        var anyErrors :Bool := false
        for [report, isSerious] in ([
            [findUndefinedNames(tree, safeScope), true],
            [findUnusedNames(tree), false],
            [findSingleMethodObjects(tree), false],
        ]):
            if (!report.isEmpty()):
                anyErrors |= isSerious
                for [message, span] in (report):
                    def err := lex.makeParseError([message, span])
                    def s := if (config.terseErrors()) {
                        `$inputFile:${err.formatCompact()}$\n`
                    } else { err.formatPretty() }
                    stdout(UTF8.encode(s, null))
        if (anyErrors):
            throw("There were name usage errors!")
        return tree

    def makeLoader(fileReader, config):
        return def loadPetname(pn :Str):
            def pipeline := [
                fileReader,
                stopwatch(parse, "source" => pn),
                if (config.verify()) {
                    stopwatch(verify, "source" => pn)
                } else { fn [_lex, tree] { tree } },
                # NB: Not expanding or optimizing here; we will expand and
                # optimize the entire program at once instead.
            ]
            return runPipeline(pn, pipeline)

    def starter := if (inputFile == "-" || config.readStdin()) {
        def [l, sink] := makeSink.asList()
        def decodedSink := alterSink.decodeWith(UTF8, sink,
                                                "withExtras" => true)
        flow(stdio.stdin(), decodedSink)
        when (l) -> { "".join(l) }
    } else {
        def p := makeFileResource(inputFile)<-getContents()
        when (p) -> { UTF8.decode(p, null) }
    }

    def writeOutputFile(bs):
        return makeFileResource(outputFile)<-setContents(bs)

    def frontend := [
        stopwatch(parse),
        if (config.verify()) { stopwatch(verify) } else {
            fn [_lex, tree] { tree }
        },
    ]
    def backend := if (config.justLint()) {[]} else {[
        if ((def path := config.muffinPath()) != null) {
            makeMuffin(makeLoader(fn petname {
                def p := makeFileResource(`$path/$petname.mt`)<-getContents()
                when (p) -> { UTF8.decode(p, null) }
            }, config))
        },
        stopwatch(expandTree),
        if (config.useMixer()) { stopwatch(optimize) },
        stopwatch(serialize),
        writeOutputFile,
    ]}
    def stages := [for s in (frontend + backend) ? (s != null) s]
    def p := runPipeline(starter, stages)
    return when (p) -> { 0 } catch problem { traceln.exception(problem); 1 }
