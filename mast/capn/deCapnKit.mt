import "lib/capn" =~ [=> makeMessageReader :DeepFrozen]
import "lib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
import "capn/montevalue" =~ [=> reader, => makeWriter]

exports (deCapnKit)


def Node :DeepFrozen := Map[Str, Any]  # Named arguments to makeDataExpr
def Root :DeepFrozen := Bytes          # capn message


object deCapnKit as DeepFrozen:
    to makeBuilder():

        def Literal := Any[Int, Double, Str, Char]

        var nextTemp :Int := 0
        var varReused := [].asMap().diverge()
        def w := makeWriter()

        def expr(nargs :Map):
            return M.call(w, "makeDataExpr", [], nargs)

        return object deCapnBuilder implements DEBuilderOf[Node, Root]:
            method getNodeType() :Near:
                Node
            method getRootType() :Near:
                Root

            to buildRoot(root :Node) :Bytes:
                return w.dump(expr(root))

            to buildLiteral(it :Literal) :Node:
                return switch (it):
                    match i :Int:
                        def ii := if (-(2 ** 31) <= i && i < 2 ** 31) {
                            w.makeInteger("int32" => i)
                        } else {
                            w.makeInteger("bigint" => b`${i}@@`)
                        }
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
                return ["noun" => varName]

            to buildIbid(tempIndex :Int) :Node:
                if (! (tempIndex < nextTemp)):
                    throw(`assertion failure: $tempIndex < $nextTemp`)
                varReused[tempIndex] := true
                # traceln(`buildIbid: $tempIndex marked reused.`)
                return ["ibid" => tempIndex]

            to buildCall(rec :Node, verb :Str, args :List[Node], nargs :Map[Str, Node]) :Node:
                def message := ["verb" => verb,
                                "args" => args,
                                "namedArgs" => [for k => v in (nargs) ["key" => k, "value" => v]]
                ]
                return ["call" => ["receiver" => expr(rec), "message" => message]]

            to buildDefine(rValue :Node) :Pair[Node, Int]:
                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def defNode := ["defExpr" => ["index" => tempIndex, "rValue" => expr(rValue)]]
                return [defNode, tempIndex]

            to buildPromise() :Int:
                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex + 1] := false
                return promIndex

            to buildDefrec(resIndex :Int, rValue :Node) :Node:
                def promIndex := resIndex - 1
                # traceln(`buildDefrec: $promIndex reused? ${varReused[promIndex]}.`)
                return if (varReused[promIndex]):
                    # We have a cycle
                    ["defRec" => ["promIndex" => promIndex, "rValue" => expr(rValue)]]
                else:
                    # No cycle
                    ["defExpr" => ["index" => promIndex, "rValue" => expr(rValue)]]

    to recognize(msg :Root, builder) :(def _Root := builder.getRootType()):
        def Node := builder.getNodeType()

        def build(expr):
            return switch (expr._which()) {
                match ==0 { # literal
                    def lit := expr.literal()
                    switch (lit._which()) {
                        match ==0 {
                            def litInt := lit.int()
                            switch (litInt._which()) {
                                match ==0 { litInt.int32() }
                                match ==1 { throw("not implemented: bigint") }
                            }
                        }
                        match ==1 { lit.double() }
                        match ==2 { lit.str() }
                        match ==3 { lit.char()[0] } #@@@@hmm... use int instead?
                        match ==4 { lit.bytes() }
                    }
                }
                match ==1 {
                    builder.buildImport(expr.noun())
                }
                match ==2 {
                    builder.buildIbid(expr.ibid())
                }
                match ==3 {
                    def call := expr.call()
                    def msg := call.message()
                    def args := [for arg in (msg.args()) build(arg)]
                    def nargs := [for n => arg in (msg.namedArgs()) n => build(arg)]
                    builder.buildCall(build(call.receiver()), msg.verb(), args, nargs)
                }
                match ==4 {  # defExpr
                    # ISSUE: we're not using the de.index() field. Is it needed?
                    def de := expr.defExpr()
                    def [val, _tempIndex] := builder.buildDefine(build(de.rValue()))
                    val
                }
                match ==5 {  # defRec
                    # ISSUE: we're not using the dr.promIndex() field. Is it needed?
                    def dr := expr.defRec()
                    def promIndex := builder.buildPromise()
                    return builder.buildDefrec(promIndex + 1, build(dr.rValue()))
                }
                match other { throw(`not implemented: ${other}`) }
            }

        def expr := reader.DataExpr(makeMessageReader(msg).getRoot())

        return builder.buildRoot(build(expr))
