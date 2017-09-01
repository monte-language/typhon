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

def makePipeline(timer, [var stage] + var stages) as DeepFrozen:
    var data := null
    def resultPromises := [].diverge()

    return object pipeline:
        to promisedResult():
            def [p, r] := Ref.promise()
            resultPromises.push(r)
            return p

        to advance():
            def p := timer.sendTimestamp(fn then {
                def rv := stage<-(data)
                when (rv) -> {
                    timer.sendTimestamp(fn now {
                        def taken := now - then
                        traceln(`$stage took $taken seconds`)
                        data := rv
                    })
                }
            })
            when (p) ->
                if (stages.size() == 0):
                    # Done; notify everybody.
                    for r in (resultPromises):
                        r.resolve(data)
                else:
                    def [s] + ss := stages
                    stage := s
                    stages := ss
                    pipeline.advance()
            catch problem:
                traceln.exception(problem)
                # Done in a different sort of way.
                for r in (resultPromises):
                    r.smash(problem)

def parseArguments(var argv, ej) as DeepFrozen:
    var useMixer :Bool := false
    var arguments :List[Str] := []
    var verifyNames :Bool := true
    var terseErrors :Bool := false
    var justLint :Bool := false
    var readStdin :Bool := false
    def inputFile
    def outputFile
    while (argv.size() > 0):
        traceln(`ARGV $argv`)
        switch (argv):
            match [=="-mix"] + tail:
                useMixer := true
                argv := tail
            match [=="-noverify"] + tail:
                verifyNames := false
                argv := tail
            match [=="-terse"] + tail:
                terseErrors := true
                argv := tail
            match [=="-lint"] + tail:
                justLint := true
                argv := tail
            match [=="-stdin"] + tail:
                readStdin := true
                argv := tail
            match [arg] + tail:
                arguments with= (arg)
                argv := tail
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

        to verifyNames() :Bool:
            return verifyNames

        to terseErrors() :Bool:
            return terseErrors

        to getInputFile() :Str:
            return inputFile

        to getOutputFile() :NullOk[Str]:
            return outputFile

        to readStdin() :Bool:
            return readStdin


def main(argv, => Timer, => makeFileResource, => unsealException, => stdio) as DeepFrozen:
    def config := parseArguments(argv, throw)
    def inputFile := config.getInputFile()
    def outputFile := config.getOutputFile()

    def stdout := alterSink.encodeWith(UTF8, stdio.stdout())

    def readAllStdinText():
        def [l, sink] := makeSink.asList()
        def decodedSink := alterSink.decodeWith(UTF8, sink,
                                                "withExtras" => true)
        flow(stdio.stdin(), decodedSink)
        return when (l) -> { "".join(l) }

    def readInputFile(_):
        if (inputFile == "-" || config.readStdin()):
            return readAllStdinText()
        def p := makeFileResource(inputFile)<-getContents()
        return when (p) ->
            UTF8.decode(p, null)

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
        if (config.verifyNames()):
            def stdout := stdio.stdout()
            var anyErrors :Bool := false
            for [report, isSerious] in ([
                [findUndefinedNames(tree, safeScope), true],
                [findUnusedNames(tree), false],
                [findSingleMethodObjects(tree), false],
            ]):
                if (report.size() > 0):
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

    def expandTree(tree):
        return expand(tree, astBuilder, throw)

    def serialize(tree):
        def context := makeMASTContext()
        context(tree)
        return context.bytes()

    def writeOutputFile(bs):
        return makeFileResource(outputFile)<-setContents(bs)

    def stages := [
        readInputFile,
        parse,
        expandTree,
    ] + if (config.useMixer()) {[optimize]} else {[]} + [
        serialize,
    ] + if (config.justLint()) {[]} else {[writeOutputFile]}
    def pipeline := makePipeline(Timer, stages)
    def p := pipeline.promisedResult()
    pipeline.advance()
    return when (p) ->
        traceln("All done!")
        0
    catch via (unsealException) [problem, traceback]:
        for line in (traceback.reverse()):
            traceln(line)
        traceln(`Problem: $problem`)
        1
