
def [=> astBuilder, => dump] := import("lib/monte/monte_ast")
def makeMonteLexer := import("lib/monte/monte_lexer")["makeMonteLexer"]
def parseModule := import("lib/monte/monte_parser")["parseModule"]
def [=> expand] := import("lib/monte/monte_expander")
def [=> UTF8] | _ := import("lib/codec/utf8")

def compile(inT, outputFile):
    var bytebuf := []
    def buf := [].diverge()
    object tyDumper:
        to flowingFrom(upstream):
            null

        to receive(bytes):
            bytebuf += bytes
            def [s, leftovers] := UTF8.decodeExtras(bytebuf, null)
            bytebuf := leftovers
            buf.push(s)

        to flowStopped(reason):
            traceln(`flowed!`)
            def tree := parseModule(makeMonteLexer("".join(buf)), astBuilder, throw)
            traceln(`parsed!`)
            def expandedTree := expand(tree, astBuilder, throw)
            traceln(`expanded!`)
            # Opening file here so that it doesn't get overwritten when parsing fails.
            def outT := makeFileResource(outputFile).openDrain()
            dump(expandedTree, outT.receive)
            traceln(`dumped!`)
    inT.flowTo(tyDumper)

def argv := currentProcess.getArguments().diverge()

# YOLO
def [outputFile, inputFile] := [argv.pop(), argv.pop()]

compile(makeFileResource(inputFile).openFount(), outputFile)
