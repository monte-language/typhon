def [=> dump] := import("lib/monte/ast_dumper")
def makeMonteLexer := import("lib/monte/monte_lexer")["makeMonteLexer"]
def parseModule := import("lib/monte/monte_parser")["parseModule"]
def [=> expand] := import("lib/monte/monte_expander")
def [=> optimize] := import("lib/monte/monte_optimizer")
def [=> makeUTF8EncodePump, => makeUTF8DecodePump] | _ := import("lib/tubes/utf8")
def [=> makePumpTube] | _ := import("lib/tubes/pumpTube")

def compile(config, inT, inputFile, outputFile):
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
            traceln(`flowed!`)
            # Our strategy here is to slurp the entire file into memory, and
            # complete all of our transformative steps (each of which can
            # fail) before we emit a file. This prevents trashing existing
            # files with garbage or incomplete data.
            escape e:
                def tree := parseModule(makeMonteLexer("".join(buf), inputFile), astBuilder, e)
            catch parseErrorMsg:
                def stdout := makePumpTube(makeUTF8EncodePump())
                stdout.flowTo(makeStdOut())
                stdout.receive(parseErrorMsg)
                throw("Syntax error")

            traceln(`parsed!`)
            def expandedTree := expand(tree, astBuilder, throw)
            traceln(`expanded!`)

            def finalTree := if (config.useMixer()) {
                def optimizedTree := optimize(expandedTree)
                traceln("Optimized with mixer!")
                optimizedTree
            } else {expandedTree}

            var data := b``
            dump(finalTree, fn stuff {data += stuff})
            traceln(`dumped!`)

            def outT := makeFileResource(outputFile).openDrain()
            outT.receive(data)
            traceln("Wrote new file!")

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
