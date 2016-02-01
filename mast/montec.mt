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


def parseArguments(var argv) as DeepFrozen:
    var useMixer :Bool := false
    var useNewFormat :Bool := true
    var arguments :List[Str] := []
    var verifyNames :Bool := true
    var terseErrors :Bool := false
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
            match [=="-format", =="mast"] + tail:
                argv := tail
            match [=="-format", =="trash"] + tail:
                useNewFormat := false
                argv := tail
            match [arg] + tail:
                arguments with= (arg)
                argv := tail

    return object configuration:
        to useMixer() :Bool:
            return useMixer

        to useNewFormat() :Bool:
            return useNewFormat

        to verifyNames() :Bool:
            return verifyNames

        to terseErrors() :Bool:
            return terseErrors

        to arguments() :List[Str]:
            return arguments


def main(argv, => Timer, => currentProcess, => makeFileResource, => makeStdOut,
         => unsealException) as DeepFrozen:

    def config := parseArguments(argv)

    def [inputFile, outputFile] := config.arguments()

    def compile(data :Str) :Bytes:
        "Compile a module and serialize it to a bytestring."

        var tree := null
        def lex := makeMonteLexer(data, inputFile)
        def parseTime := Timer.trial(fn {
            escape e {
                tree := parseModule(lex, astBuilder, e)
            } catch parseError {
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                stdout.receive(parseError.formatPretty())
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
                            if (config.terseErrors()) {inputFile + ":" + err.formatCompact() + "\n"
                            } else {err.formatPretty()})
                    throw("Name usage error")

        when (parseTime) ->
            traceln(`Parsed source file (${parseTime}s)`)

        def expandTime := Timer.trial(fn {tree := expand(tree, astBuilder, throw)})
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

    def p := makeFileResource(inputFile)<-getContents()
    return when (p) ->
        def via (UTF8.decode) data := p
        traceln("Read in source file")
        def bs :Bytes := compile(data)
        traceln("Writing out source file")
        when (makeFileResource(outputFile)<-setContents(bs)) ->
            0
        catch via (unsealException) problem:
            traceln(`Problem writing file: $problem`)
            1
    catch via (unsealException) problem:
        traceln(`Problem: $problem`)
        1
