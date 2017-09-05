import "elib/serial/deSubgraphKit" =~ [=>deSubgraphKit :DeepFrozen]
import "deJSONKit" =~ [=>deJSONKit :DeepFrozen]
exports (main)

def main(_argv) :Vow[Int] as DeepFrozen:
    def x := [1, x, 3]
    traceln(x)
    def jb := deJSONKit.makeBuilder()
    def sr := deSubgraphKit  # .makeRecognizer(null, safeScope)
    traceln(sr.recognize(x, jb))
    return 0
