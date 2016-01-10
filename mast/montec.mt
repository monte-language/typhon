exports (main)


def parseArguments([processName, scriptName] + var argv) as DeepFrozen:
    var useMixer :Bool := false
    var useNewFormat :Bool := true
    var arguments :List[Str] := []

    while (argv.size() > 0):
        switch (argv):
            match [=="-mix"] + tail:
                useMixer := true
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

        to arguments() :List[Str]:
            return arguments

def main(=> Timer, => currentProcess, => makeFileResource, => makeStdOut,
         => unsealException, => bench, => unittest) as DeepFrozen:
    def scope := safeScope | [=> &&bench]
    def [=> dump :DeepFrozen] := ::"import".script("lib/monte/ast_dumper", scope)
    def [=> UTF8 :DeepFrozen] := ::"import".script("lib/codec/utf8", scope)
    def [=> makeMASTContext :DeepFrozen] := ::"import"("lib/monte/mast", [=> UTF8])
    def makeMonteLexer :DeepFrozen := ::"import".script("lib/monte/monte_lexer", scope)["makeMonteLexer"]
    def parseModule :DeepFrozen := ::"import".script("lib/monte/monte_parser", scope)["parseModule"]
    def [=> expand :DeepFrozen] := ::"import".script("lib/monte/monte_expander", scope)
    def [=> optimize :DeepFrozen] := ::"import".script("lib/monte/monte_optimizer", scope)
    def [=> makeUTF8EncodePump :DeepFrozen,
         => makePumpTube :DeepFrozen,
    ] | _ := ::"import"("lib/tubes", [=> unittest])
    def [=> findUndefinedNames :DeepFrozen] | _ := ::"import"("lib/monte/monte_verifier")

    def config := parseArguments(currentProcess.getArguments())

    def [inputFile, outputFile] := config.arguments()

    def compile(data :Str) :Bytes:
        "Compile a module and serialize it to a bytestring."

        var tree := null
        def lex := makeMonteLexer(data, inputFile)
        def parseTime := Timer.trial(fn {
            escape e {
                tree := parseModule(lex, astBuilder, e)
            } catch parseErrorMsg {
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                stdout.receive(parseErrorMsg)
                throw("Syntax error")
            }
        })
        def undefineds := findUndefinedNames(tree, safeScope)
        if (undefineds.size() > 0):
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                for n in undefineds:
                    escape x:
                        lex.formatError(
                            [`Undefined name ${n.getName()}`, n.getSpan()], x)
                    catch msg:
                        stdout.receive(msg)
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
