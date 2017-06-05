import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/monte/monte_lexer" =~ [=> makeMonteLexer :DeepFrozen]
import "lib/monte/monte_parser" =~ [=> parseModule :DeepFrozen]
exports (main)

def main(args, => makeFileResource, => stdio) as DeepFrozen:
    def inputFile
    if (args !~ [bind inputFile]):
        throw("Usage: monte format inputFile")
    def printit(source):
        return parseModule(makeMonteLexer(source, "m``.fromStr/1"),
                           astBuilder, throw)

    return when (def contents := makeFileResource(inputFile) <- getContents()) ->
        stdio.stdout()(UTF8.encode(M.toString(printit(UTF8.decode(contents, throw))), throw))
        0
