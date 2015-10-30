imports
exports (main)


def parseArguments([processName, scriptName] + var argv) as DeepFrozen:
    var useMixer :Bool := false
    var useNewFormat :Bool := false
    var arguments :List[Str] := []

    while (argv.size() > 0):
        switch (argv):
            match [=="-mix"] + tail:
                useMixer := true
                argv := tail
            match [=="-format", =="mast"] + tail:
                useNewFormat := true
                argv := tail
            match [=="-format", =="trash"] + tail:
                argv := tail
            match [arg] + tail:
                arguments with= (arg)
                argv := tail

    return object configuration:
        to useMixer() :Bool:
            return useMixer

        to useNewFormat() :Bool:
            return useNewFormat

        to arguments() :List[Str]:
            return arguments

def main(=> Timer, => currentProcess, => makeFileResource, => makeStdOut, => bench) as DeepFrozen:
    def scope := safeScope | [=> &&bench]
    def [=> dump :DeepFrozen] := import.script("lib/monte/ast_dumper", scope)
    def [=> UTF8 :DeepFrozen] := import.script("lib/codec/utf8", scope)
    def [=> makeMASTContext :DeepFrozen] := import("lib/monte/mast", [=> UTF8])
    def makeMonteLexer :DeepFrozen := import.script("lib/monte/monte_lexer", scope)["makeMonteLexer"]
    def parseModule :DeepFrozen := import.script("lib/monte/monte_parser", scope)["parseModule"]
    def [=> expand :DeepFrozen] := import.script("lib/monte/monte_expander", scope)
    def [=> optimize :DeepFrozen] := import.script("lib/monte/monte_optimizer", scope)
    def [=> makeUTF8EncodePump :DeepFrozen,
         => makeUTF8DecodePump :DeepFrozen] | _ := import.script("lib/tubes/utf8", scope)
    def [=> makePumpTube :DeepFrozen] | _ := import.script("lib/tubes/pumpTube", scope)
    def [=> findUndefinedNames :DeepFrozen,
         => walkScopeBoxes :DeepFrozen] | _ := import("lib/monte/monte_verifier")

    def compile(config, inT, inputFile, outputFile, Timer, makeFileResource,
                makeStdOut) as DeepFrozen:
        "Compile a module and write it to an output file.

         This function reads the entire input file into memory and completes all
         of its compilation steps prior to opening and writing the output file.
         This avoids the failure mode where the output file is corrupted by
         incomplete data, as well as the failure mode where the output file is
         truncated."
        var bytebuf := []
        def buf := [].diverge()

        object tyDumper:
            to flowingFrom(upstream):
                null

            to receive(s):
                buf.push(s)

            to flowAborted(reason):
                traceln(`Fount aborted unexpectedly: $reason`)

            to flowStopped(reason):
                traceln("Read in source file")

                var tree := null
                def lex := makeMonteLexer("".join(buf), inputFile)
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                def parseTime := Timer.trial(fn {
                    escape e {
                        tree := parseModule(lex, astBuilder, e)
                    } catch parseErrorMsg {
                        stdout.receive(parseErrorMsg)
                        throw("Syntax error")
                    }
                })
                def undefineds := findUndefinedNames(tree, safeScope)
                if (undefineds.size() > 0):
                    for n in undefineds:
                        escape x:
                            lex.formatError(
                                [`Undefined name ${n.getName()}`, n.getSpan()], x)
                        catch msg:
                            stdout.receive(msg)
                    throw("Name usage error")

                def redefineds := walkScopeBoxes(tree, safeScope)
                if (redefineds.size() > 0):
                    for n in redefineds:
                        escape x:
                            lex.formatError(
                                [`Redefinition of existing name "${n.getNoun().getName()}"`, n.getSpan()], x)
                        catch msg:
                            stdout.receive(msg)
                when (parseTime) ->
                    traceln(`Parsed source file (${parseTime}s)`)

                def expandTime := Timer.trial(fn {tree := expand(tree, astBuilder, throw)})
                when (expandTime) ->
                    traceln(`Expanded source file (${expandTime}s)`)

                if (config.useMixer()) {
                    def optimizeTime := Timer.trial(fn {tree := optimize(tree)})
                    when (optimizeTime) -> {traceln(`Optimized source file (${optimizeTime}s)`)}
                }

                def data := if (config.useNewFormat()) {
                    def context := makeMASTContext()
                    context(tree)
                    context.bytes()
                } else {
                    var data := [].diverge()
                    def dumpTime := Timer.trial(fn {
                        dump(tree, fn stuff :Bytes {data.push(stuff)})
                    })
                    when (dumpTime) -> {traceln(`Dumped source file (${dumpTime}s)`)}
                    b``.join(data)
                }

                def outT := makeFileResource(outputFile).openDrain()
                outT<-receive(data)
                traceln("Writing out source file")

        inT<-flowTo(tyDumper)

    def config := parseArguments(currentProcess.getArguments())

    def [inputFile, outputFile] := config.arguments()

    def fileFount := makeFileResource(inputFile).openFount()
    def utf8Fount := fileFount<-flowTo(makePumpTube(makeUTF8DecodePump()))

    compile(config, utf8Fount, inputFile, outputFile, Timer, makeFileResource,
            makeStdOut)

    return 0
