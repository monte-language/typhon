import "elib/serial/deSubgraphKit" =~ [=>deSubgraphKit :DeepFrozen]
import "elib/serial/deMNodeKit" =~ [=>deMNodeKit :DeepFrozen]
import "elib/serial/deSrcKit" =~ [=>deSrcKit :DeepFrozen]
import "deJSONKit" =~ [=>deJSONKit :DeepFrozen]
exports (main)

def test(actual, expected) as DeepFrozen:
    if (actual == expected):
        trace(".")
    else:
        traceln("")
        traceln(`want: $expected`)
        traceln(` got: $actual`)


def main(_argv) :Vow[Int] as DeepFrozen:
    def s := M.toString

    def x := [1, x, 3]
    test(s(x), "[1, <**CYCLE**>, 3]")

    test(s(deSubgraphKit.recognize(x, deSrcKit.makeBuilder())),
         "def t_0 := [def t_2 := 1, t_0, def t_4 := 3]")

    def ast := deSubgraphKit.recognize(x, deMNodeKit.makeBuilder()).canonical()
    # TODO: def makeKernelECopyVisitor := elang_uriGetter("visitors.KernelECopyVisitor")
    test(ast, m`def [t_0 :Any, t_1 :Any] := Ref.promise();$\
                t_1.resolve(_makeList.run(def t_2 :Any := 1, t_0, def t_4 :Any := 3));$\
                t_0`.canonical() :(astBuilder.getAstGuard()))

    test(deSubgraphKit.recognize(x, deJSONKit.makeBuilder()),
         ["defrec", 0,
          ["call", ["import", "_makeList"], "run",
           [["define", 2, 1], ["ibid", 0], ["define", 4, 3]], [].asMap()]])
    return 0
