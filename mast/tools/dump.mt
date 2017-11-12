import "lib/codec/utf8" =~  [=> UTF8 :DeepFrozen]
exports (main)

def main(argv, => makeFileResource, => stdio) as DeepFrozen:
    def filename := argv.last()
    def handle := makeFileResource(argv.last())
    def stdout := stdio<-stdout()
    def print(s :Str) :Vow[Void]:
        return stdout<-(UTF8.encode(s + "\n", null))
    return when (def bs := handle<-getContents()) ->
        escape ej:
            def ast := readMAST(bs, => filename, "FAIL" => ej)
            when (print(M.toString(ast))) -> { 0 }
        catch problem:
            when (print(`Problem decoding MAST: $problem`)) -> { 1 }
