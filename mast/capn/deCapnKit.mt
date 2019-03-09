import "lib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
import "capn/montevalue" =~ [=> reader, => makeWriter]
exports (deCapnKit)


def Node :DeepFrozen := Any  # writer?
def Root :DeepFrozen := Any  # Bytes?

object deCapnKit as DeepFrozen:
    to makeBuilder():

        def Literal := Any[Int, Double, Str, Char]

        var nextTemp :Int := 0
        var varReused := [].asMap().diverge()
        def w := makeWriter()

        def expr(nargs :Map):
            traceln("@@expr", nargs)
            return M.call(w, "makeDataExpr", [], nargs)

        return object deCapnBuilder implements DEBuilderOf[Node, Root]:
            method getNodeType() :Near:
                Node
            method getRootType() :Near:
                Root

            to buildRoot(root :Node) :Node:
                traceln("buildRoot@@", root)
                return expr(root)

            to buildLiteral(it :Literal) :Node:
                traceln("buildLiteral@@", it)
                return switch (it):
                    match i :Int:
                        def ii := if (-(2 ** 31) <= i && i < 2 ** 31) {
                            w.makeInteger("int32" => i)
                        } else {
                            w.makeInteger("bigint" => b`${i}@@`)
                        }
                        traceln("Integer@@", ii)
                        ["literal" => ["int" => ii]]
                    match x :Double:
                        ["literal" => ["double" => x]]
                    match s :Str:
                        ["literal" => ["str" => s]]
                    match ch: Char:
                        ["literal" => ["char" => ch]]
                    match bs: Bytes:
                        ["literal" => ["bytes" => bs]]

            to buildImport(varName :Str) :Node:
                traceln("buildImport@@", ["varName" => varName])
                return ["import" => varName]

            to buildIbid(tempIndex :Int) :Node:
                traceln("buildIbid@@", ["tempIndex" => tempIndex])
                if (! (tempIndex < nextTemp)):
                    throw(`assertion failure: $tempIndex < $nextTemp`)
                varReused[tempIndex] := true
                # traceln(`buildIbid: $tempIndex marked reused.`)
                return ["ibid" => tempIndex]

            to buildCall(rec :Node, verb :Str, args :List[Node], nargs :Map[Str, Node]) :Node:
                traceln("buildCall@@", ["rec" => rec, "verb" => verb, "args" => args, "nargs" => nargs])
                def message := ["verb" => verb,
                                "args" => args,
                                "namedArgs" => [for k => v in (nargs) ["key" => k, "value" => v]]
                ]
                return ["call" => ["receiver" => expr(rec), "message" => message]]

            to buildDefine(rValue :Node) :Pair[Node, Int]:
                traceln("buildDefine@@", ["rValue" => rValue])
                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def defNode := ["defExpr" => ["index" => tempIndex, "rValue" => expr(rValue)]]
                return [defNode, tempIndex]

            to buildPromise() :Int:
                traceln("buildPromise@@")
                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex + 1] := false
                return promIndex

            to buildDefrec(resIndex :Int, rValue :Node) :Node:
                traceln("buildDefrec@@", ["resIndex" => resIndex, "rValue" => rValue])
                def promIndex := resIndex - 1
                # traceln(`buildDefrec: $promIndex reused? ${varReused[promIndex]}.`)
                return if (varReused[promIndex]):
                    # We have a cycle
                    ["defRec" => ["promIndex" => promIndex, "rValue" => expr(rValue)]]
                else:
                    # No cycle
                    ["defExpr" => ["index" => promIndex, "rValue" => expr(rValue)]]

    to recognize():
        throw("@@not implemented")
        #@@Char
