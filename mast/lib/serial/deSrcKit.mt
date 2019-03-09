# Copyright 2002 Combex, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

# def makeURIKit := <import:org.quasiliteral.syntax.URIKit>
import "lib/serial/DEBuilderOf" =~ [=> DEBuilderOf :DeepFrozen]
import "lib/serial/deMNodeKit" =~ [=> deMNodeKit :DeepFrozen]
exports (deSrcKit)

# /**
#  * Prints a Kernel-Monte AST (@@??with some syntactic shorthands restored).
#  * <p>
#  * This is currently used only for printing the output of uneval, so it
#  * currently handles the AST cases generated by uneval, but few if any others.
#  *
#  * @author Mark S. Miller
#  * ported to Monte by Dan Connolly
#  */
object deSrcKit as DeepFrozen {

    method makeBuilder() :Near {
        deSrcKit.makeBuilder(79, 1)
    }

    method makeBuilder(wrapColumn :Int, sugarLevel :Int) :Near {

        # The index of the next temp variable
        var nextTemp := 0

        object deSrcBuilder implements DEBuilderOf[Str, Str] {

            to getNodeType() :Near { Str }
            to getRootType() :Near { Str }

            to buildRoot(root :Str) :Str {
                def result := M.toString(::"m``".fromStr(root) :(astBuilder.getAstGuard()))
                # Remove terminal newline
                # ugh: Slice stop cannot be negative
                return if (result.endsWith("\n")) {
                    result.slice(0, result.size() - 1)
                } else {
                    result
                }
            }

            to buildLiteral(value) :Str {
                return M.toQuote(value)
            }

            method buildImport(varName :Str) :Str { varName }
            method buildIbid(tempIndex :Int)    :Str { `t_$tempIndex` }

            to buildCall(var rec :Str,
                         verb :Str,
                         args :List[Str],
                         nargs :Map[Str, Str]) :Str {
                if (rec =~ `def t_@_`) {
                    # the result would otherwise misparse.
                    rec := `($rec)`
                }
                var argList := ", ".join(args)
                if (rec.size() + argList.size() > wrapColumn - 20) {
                    argList := ",\n".rjoin(args)
                }
                if (args.size() >= 1 &&
                      rec.size() + args[0].size() > wrapColumn - 20) {

                    argList := "\n" + argList + "\n"
                }
                argList += ", ".join([for n => v in (nargs) `$n => v`])

                if (sugarLevel <= 0) {
                    return `$rec.$verb($argList)`
                }

                return switch ([rec, verb, args]) {
                    match [`_makeList`, `run`, _] {
                        `[$argList]`
                    }
                    match [_, `run`, _] {
                        `$rec($argList)`
                    }
                    match [_, `negate`, []] {
                        `-$rec`
                    }
                    match _ {
                        `$rec.$verb($argList)`
                    }
                }
            }

            method buildDefine(rValue :Str) :Pair[Str, Int] {
                def tempIndex := nextTemp
                nextTemp += 1
                [`def t_$tempIndex := $rValue`, tempIndex]
            }

            method buildPromise() :Int {
                def promIndex := nextTemp
                nextTemp += 2
                promIndex
            }

            method buildDefrec(resIndex :Int, rValue :Str) :Str {
                def promIndex := resIndex -1
                `def t_$promIndex := $rValue`
            }
        }
    }

    method recognize(src :Str, builder) :(builder.getRootType()) {
        var ast := ::"m``".fromStr(src)
        # repair circular definition form
        deMNodeKit.recognize(ast, builder)
    }
}
