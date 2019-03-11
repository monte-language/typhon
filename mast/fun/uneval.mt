import "lib/serial/deSubgraphKit" =~ [=>deSubgraphKit :DeepFrozen]
import "lib/serial/deMNodeKit" =~ [=>deMNodeKit :DeepFrozen]
import "lib/serial/deSrcKit" =~ [=>deSrcKit :DeepFrozen]
import "capn/deCapnKit" =~ [=>deCapnKit :DeepFrozen]
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

    def data := [null, true, false, 1,
                 # bigint is TODO
                 # 2.54 messageWriter lacks writeFloat64
                 # https://github.com/monte-language/typhon/issues/206
                 "abc",
                 # 'A', TODO
                 # b`hello` TODO: Problem: Can't uneval <makeBytes>
    ]
    def dataMsg := deSubgraphKit.recognize(data,
                                           deCapnKit.makeBuilder())
    def data2 := deCapnKit.recognize(dataMsg, deSubgraphKit.makeBuilder())
    test(data2, data)

    def x := [1, x, 3]
    test(s(x), "[1, <**CYCLE**>, 3]")

    test(s(deSubgraphKit.recognize(x, deSrcKit.makeBuilder())),
         "def t_0 := [def t_2 := 1, t_0, def t_4 := 3]")

    def ast := deSubgraphKit.recognize(x, deMNodeKit.makeBuilder()).canonical()
    # TODO: def makeKernelECopyVisitor := elang_uriGetter("visitors.KernelECopyVisitor")
    test(ast, m`def [t_0 :Any, t_1 :Any] := Ref.promise();$\
                t_1.resolve(_makeList.run(def t_2 :Any := 1, t_0, def t_4 :Any := 3));$\
                t_0`.canonical() :(astBuilder.getAstGuard()))

    def output := deSubgraphKit.recognize(x, deCapnKit.makeBuilder())

    def xx := deCapnKit.recognize(output, deSubgraphKit.makeBuilder())
    test(s(xx), "[1, <**CYCLE**>, 3]")

    test(output.size(), 472)
    test(output.contains(b`_makeList`), true)
    # def stdout := stdio.stdout()
    # return when (stdout(output), stdout<-complete()) -> { 0 }
    return 0
