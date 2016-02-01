import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
import "lib/monte/ast_dumper" =~ [=> dump :DeepFrozen]
import "lib/monte/mast" =~ [=> makeMASTContext :DeepFrozen]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [=> parseModule :DeepFrozen]
import "lib/monte/monte_expander" =~ [=> expand :DeepFrozen]
import "lib/monte/monte_optimizer" =~ [=> optimize :DeepFrozen]
import "lib/tubes" =~ [=> makeUTF8EncodePump :DeepFrozen, => makePumpTube :DeepFrozen]
import "lib/monte/monte_verifier" =~ [=> findUndefinedNames :DeepFrozen]

exports (main)


def parseArguments(var argv, ej) as DeepFrozen:
    var useMixer :Bool := false
    var useNewFormat :Bool := true
    var arguments :List[Str] := []
    var verifyNames :Bool := true
    var terseErrors :Bool := false
    var justLint :Bool := false
    def inputFile
    def outputFile
    while (argv.size() > 0):
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
            match [=="-format", =="mast"] + tail:
                argv := tail
            match [=="-format", =="trash"] + tail:
                useNewFormat := false
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

        to useNewFormat() :Bool:
            return useNewFormat

        to verifyNames() :Bool:
            return verifyNames

        to terseErrors() :Bool:
            return terseErrors

        to getInputFile() :Str:
            return inputFile

        to getOutputFile() :NullOk[Str]:
            return outputFile


def main(argv, => Timer, => currentProcess, => makeFileResource, => makeStdOut,
         => unsealException) as DeepFrozen:

    def config := parseArguments(argv, throw)
    def inputFile := config.getInputFile()
    def outputFile := config.getOutputFile()


    def parse(data :Str):
        "Parse and verify a Monte source file."

        def tree
        def lex := makeMonteLexer(data, inputFile)
        def parseTime := Timer.trial(fn {
            escape e {
                bind tree := parseModule(lex, astBuilder, e)
            } catch parseError {
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                stdout.receive(
                    if (config.terseErrors()) {
                        inputFile + ":" + parseError.formatCompact() + "\n"
                    } else {parseError.formatPretty()})

                throw("Syntax error")
            }
        })
        if (config.verifyNames()):
            def undefineds := findUndefinedNames(tree, safeScope)
            if (undefineds.size() > 0):
                    def stdout := makePumpTube(makeUTF8EncodePump())
                    stdout.flowTo(makeStdOut())
                    for n in undefineds:
                        def err := lex.makeParseError(
                            [`Undefined name ${n.getName()}`,
                             n.getSpan()])
                        stdout.receive(
                            if (config.terseErrors()) {
                                inputFile + ":" + err.formatCompact() + "\n"
                            } else {err.formatPretty()})
                    throw("Name usage error")

        when (parseTime) ->
            traceln(`Parsed source file (${parseTime}s)`)
        return tree

    def compile(var tree) :Bytes:
        "Compile a module and serialize it to a bytestring."
        def expandTime := Timer.trial(fn {tree := expand(tree, astBuilder,
                                                         throw)})
        when (expandTime) ->
            traceln(`Expanded source file (${expandTime}s)`)

        if (config.useMixer()) {
            def optimizeTime := Timer.trial(fn {tree := optimize(tree)})
            when (optimizeTime) -> {traceln(`Optimized source file (${optimizeTime}s)`)}
        }

        return if (config.useNewFormat()) {
            def context := makeMASTContext()
            context(tree)
            context.bytes()
        } else {
            var bs := [].diverge()
            def dumpTime := Timer.trial(fn {
                dump(tree, fn stuff :Bytes {bs.push(stuff)})
            })
            when (dumpTime) -> {traceln(`Dumped source file (${dumpTime}s)`)}
            b``.join(bs)
        }

    def p := makeFileResource(inputFile) <- getContents()
    return when (p) ->
        def via (UTF8.decode) data := p
        traceln("Read in source file")
        def tree := parse(data)
        if (!config.justLint()):
            def bs :Bytes := compile(tree)
            traceln("Writing out source file")
            when (makeFileResource(outputFile) <- setContents(bs)) ->
                0
            catch via (unsealException) problem:
                traceln(`Problem writing file: $problem`)
                1
        else:
            0
    catch via (unsealException) problem:
        traceln(`Problem: $problem`)
        1
