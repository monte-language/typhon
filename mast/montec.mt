def [=> dump] := import("lib/monte/ast_dumper")
def makeMonteLexer := import("lib/monte/monte_lexer")["makeMonteLexer"]
def parseModule := import("lib/monte/monte_parser")["parseModule"]
def [=> expand] := import("lib/monte/monte_expander")
def [=> optimize] := import("lib/monte/monte_optimizer")
def [=> makeUTF8EncodePump, => makeUTF8DecodePump] | _ := import("lib/tubes/utf8")
def [=> makePumpTube] | _ := import("lib/tubes/pumpTube")

def compile(config, inT, inputFile, outputFile):
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
            def parseTime := Timer.trial(fn {
                escape e {
                    tree := parseModule(makeMonteLexer("".join(buf), inputFile),
                                        astBuilder, e)
                } catch parseErrorMsg {
                    def stdout := makePumpTube(makeUTF8EncodePump())
                    stdout.flowTo(makeStdOut())
                    stdout.receive(parseErrorMsg)
                    throw("Syntax error")
                }
            })
            when (parseTime) ->
                traceln(`Parsed source file (${parseTime}s)`)

            def expandTime := Timer.trial(fn {tree := expand(tree, astBuilder, throw)})
            when (expandTime) ->
                traceln(`Expanded source file (${expandTime}s)`)

            if (config.useMixer()) {
                def optimizeTime := Timer.trial(fn {tree := optimize(tree)})
                when (optimizeTime) -> {traceln(`Optimized source file (${optimizeTime}s)`)}
            }

            var data := [].diverge()
            def dumpTime := Timer.trial(fn {
                dump(tree, fn stuff :Bytes {data.push(stuff)})
                data := b``.join(data)
            })
            when (dumpTime) ->
                traceln(`Dumped source file (${dumpTime}s)`)

            def outT := makeFileResource(outputFile).openDrain()
            outT.receive(data)
            traceln("Wrote out source file")

    inT.flowTo(tyDumper)

def parseArguments([processName, scriptName] + argv):
    var useMixer :Bool := false
    var arguments := []

    for arg in argv:
        if (arg == "-mix"):
            useMixer := true
        else:
            arguments with= (arg)

    return object configuration:
        to useMixer():
            return useMixer

        to arguments():
            return arguments

def config := parseArguments(currentProcess.getArguments())

def [inputFile, outputFile] := config.arguments()

def fileFount := makeFileResource(inputFile).openFount()
def utf8Fount := fileFount.flowTo(makePumpTube(makeUTF8DecodePump()))

compile(config, utf8Fount, inputFile, outputFile)
