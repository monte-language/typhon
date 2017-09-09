import "elib/serial/deSubgraphKit" =~ [=>deSubgraphKit :DeepFrozen]
import "elib/serial/deSrcKit" =~ [=>deSrcKit :DeepFrozen]
import "deJSONKit" =~ [=>deJSONKit :DeepFrozen]
exports (main)

def test(actual, expected) as DeepFrozen:
    def actualPrinted := M.toString(actual)
    if (actualPrinted == expected):
        trace(".")
    else:
        traceln("")
        traceln(`want: $expected;\n got: $actualPrinted`)


def main(_argv) :Vow[Int] as DeepFrozen:

    def x := [1, x, 3]
    test(x, "[1, ***CYCLE***, 3]")

    test(deSubgraphKit.recognize(x, deSrcKit.makeBuilder()),
         "def t_0 := [def t_2 := 1, t_0, def t_4 := 3]")

    traceln(deSubgraphKit.recognize(x, deJSONKit.makeBuilder()))
    return 0
