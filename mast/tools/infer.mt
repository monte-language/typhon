imports
exports (main)
"Type inference for Monte."

def bench(_, _) as DeepFrozen:
    null

def [=> makePureDrain :DeepFrozen] | _ := import("lib/tubes/pureDrain")
def [=> makeUTF8EncodePump :DeepFrozen,
     => makeUTF8DecodePump :DeepFrozen] | _ := import.script("lib/tubes/utf8")
def [=> makePumpTube :DeepFrozen] | _ := import.script("lib/tubes/pumpTube")
def [=> parseModule :DeepFrozen] | _ := import.script("lib/monte/monte_parser")
def [=> makeMonteLexer :DeepFrozen] | _ := import.script("lib/monte/monte_lexer")

def inferType(expr) as DeepFrozen:
    "Infer the type of an expression."

    return Any

def spongeFile(resource) as DeepFrozen:
    def fileFount := resource.openFount()
    def utf8Fount := fileFount<-flowTo(makePumpTube(makeUTF8DecodePump()))
    def pureDrain := makePureDrain()
    utf8Fount<-flowTo(pureDrain)
    return pureDrain.promisedItems()

def main(=> currentProcess, => makeFileResource, => makeStdOut) as DeepFrozen:
    def path := currentProcess.getArguments().last()

    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout.flowTo(makeStdOut())
    def p := spongeFile(makeFileResource(path))
    return when (p) ->
        def tree := escape ej {
            parseModule(makeMonteLexer("".join(p), path), astBuilder, ej)
        } catch parseErrorMsg {
            stdout.receive(`Syntax error in $path:$\n`)
            stdout.receive(parseErrorMsg)
            1
        }
        def type := inferType(tree)
        stdout.receive(`Inferred type: $type$\n`)
        0
