import "capn/bootstrap" =~ [=> CodeGeneratorRequest :DeepFrozen]
import "lib/streams" =~ [=> collectBytes :DeepFrozen]
exports (main)

def bootstrap(bs :Bytes) as DeepFrozen:
    def cgr := CodeGeneratorRequest.unpack(bs)
    traceln(`made it $cgr`)
    for node in (cgr.nodes()):
        traceln(node.id(), node.displayName())
    def body := m`null`
    def module := m`object _ as DeepFrozen {
        to dependencies() :List[Str] { return ["lib/codec/utf8", "lib/capn"] }
        to run(package) :Map[Str, DeepFrozen] { $body }
    }`
    return module

def compile(bs :Bytes) :Bytes as DeepFrozen:
    def expr := bootstrap(bs)
    def mast := makeMASTContext()
    mast(expr.expand())
    return mast.bytes()

def main(_argv, => stdio) :Vow[Int] as DeepFrozen:
    traceln(1)
    return when (def input := collectBytes(stdio.stdin())) ->
        traceln(2)
        def stdout := stdio.stdout()
        def output :Bytes := compile(input)
        traceln(3)
        when (stdout(output), stdout<-complete()) -> { 0 }
    catch problem:
        traceln(4)
        traceln.exception(problem)
        1
