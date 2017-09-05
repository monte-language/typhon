# import "guards" =~ [=>Tuple :DeepFrozen]
import "./elib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
exports (deJSONKit)

object deJSONKit as DeepFrozen {
    to makeBuilder() {
        # Fundamental Data-E Constructs
        # as JSON-happy data structures
        # http://wiki.erights.org/wiki/Data-E_in_JSON
        def Expr
        def Literal := Any[Int, Double, Str, Pair[Same["char"], Str]]  #@@Char, Bool, null
        def Noun := Pair[Same["import"], Str]
        def Ibid := Pair[Same["ibid"], Int]
        def Call := List  # Tuple[Same["call"], Expr, Str, List[Expr], Map[Str, Expr]]
        def DefExpr := List # Tuple[Same["define"], Int, Expr]
        def DefRec := List  # Tuple[Same["defrec"], Int, Expr]
        bind Expr := Any[Literal, Noun, Ibid, Call, DefExpr, DefRec]

        var nextTemp :Int := 0
        var varReused := [].asMap().diverge()

        return object deJSONBuilder implements DEBuilderOf[Expr, Expr] {
            method getNodeType() :Near { Expr }
            method getRootType() :Near { Expr }

            to buildRoot(root :Expr) :Expr { return root }
            to buildLiteral(it :Literal) :Expr { return it }
            to buildImport(varName :Str) :Expr { return ["import", varName] }
            to buildIbid(tempIndex :Int) :Expr {
                if (! (tempIndex < nextTemp)) { throw(`assertion failure: $tempIndex < $nextTemp`) }
                varReused[tempIndex] := true
                traceln(`buildIbid: $tempIndex marked reused.`)  #@@
                return ["ibid", tempIndex]
            }
            to buildCall(rec :Expr, verb :Str, args :List[Expr], nargs :Map[Str, Expr]) :Expr {
                return ["call", rec, verb, args, nargs]
            }
            to buildDefine(rValue :Expr) :Pair[Expr, Int] {
                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def tempName := ["ibid", tempIndex]
                # hmm... can we make this optimization locally?
                def defExpr := if (rValue =~ Literal) { rValue } else { ["define", tempIndex, rValue] }
                return [defExpr, tempIndex]
            }
            to buildPromise() :Int {
                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex + 1] := false
                return promIndex
            }
            to buildDefrec(resIndex :Int, rValue :Expr) :Expr {
                def promIndex := resIndex - 1
                traceln(`buildDefrec: $promIndex reused? ${varReused[promIndex]}.`)  #@@
                return if (varReused[promIndex]) {
                    # We have a cycle
                    ["defrec", promIndex, rValue]
                } else {
                    # No cycle
                    ["define", promIndex, rValue]
                }
            }
        }
    }

    to recognize() {
        throw("@@not implemented")
    }
}
