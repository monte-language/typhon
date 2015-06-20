def [=> astBuilder] := import("lib/monte/monte_ast")
def [=> dump] := import("lib/monte/ast_dumper")
def makeMonteLexer := import("lib/monte/monte_lexer")["makeMonteLexer"]
def parseModule := import("lib/monte/monte_parser")["parseModule"]
def [=> expand] := import("lib/monte/monte_expander")
def [=> optimize] := import("lib/monte/monte_optimizer")
def [=> makeUTF8DecodePump] | _ := import("lib/tubes/utf8")
def [=> makePumpTube] | _ := import("lib/tubes/pumpTube")

def compile(inT, outputFile):
    var bytebuf := []
    def buf := [].diverge()

    object tyDumper:
        to flowingFrom(upstream):
            null

        to receive(s):
            buf.push(s)

        to flowStopped(reason):
            traceln(`flowed!`)
            # Our strategy here is to slurp the entire file into memory, and
            # complete all of our transformative steps (each of which can
            # fail) before we emit a file. This prevents trashing existing
            # files with garbage or incomplete data.
            def tree := parseModule(makeMonteLexer("".join(buf)), astBuilder, throw)
            traceln(`parsed!`)
            def expandedTree := expand(tree, astBuilder, throw)
            traceln(`expanded!`)
            def optimizedTree := optimize(expandedTree)
            traceln("Optimized!")

            def data := [].diverge()
            dump(optimizedTree, fn stuff {data.extend(stuff)})
            traceln(`dumped!`)

            def outT := makeFileResource(outputFile).openDrain()
            outT.receive(data.snapshot())
            traceln("Wrote new file!")

    inT.flowTo(tyDumper)

def argv := currentProcess.getArguments().diverge()

# YOLO
def [outputFile, inputFile] := [argv.pop(), argv.pop()]

def fileFount := makeFileResource(inputFile).openFount()
def utf8Fount := fileFount.flowTo(makePumpTube(makeUTF8DecodePump()))

compile(utf8Fount, outputFile)
