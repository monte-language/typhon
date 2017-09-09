# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

import "elib/serial/DEBuilderOf" =~ [=>DEBuilderOf :DeepFrozen]
exports (deMNodeKit)

def EExpr :DeepFrozen := astBuilder.getExprGuard()
def FinalPattern :DeepFrozen := astBuilder.getPatternGuard()

# TODO: def makeKernelECopyVisitor := elang_uriGetter("visitors.KernelECopyVisitor")

def ANY :DeepFrozen := m`Any`

object require as DeepFrozen {
    to run (cond :Bool) { return require.run(cond, fn { null }) }
    to run (cond :Bool, lose) {
        if (! cond) {
            throw(lose())
        }
    }
}

# /**
#  * Data-E ENodes are the subset of possible Kernel-E ENode ASTs which could
#  * result from applying the conventional E-to-Kernel-E expansion to the Data-E
#  * subset of E.
#  *
#  * @author Mark S. Miller
#  */
object deMNodeKit as DeepFrozen {

    # /**
    #  * Makes a shrunk Kernel-E AST as the Data-E representation.
    #  * <p>
    #  * By "shrunk", we mean that some optimization occur at build time, so that
    #  * the result of recognizing what's built may be smaller and simpler than
    #  * the original. In particular, unused temp variables are removed, and
    #  * Defrec expressions where there isn't actually a cyclic use are turned
    #  * into Define expressions.
    #  * <p>
    #  * Builds a tree by argument passing, rather than using a stack. But still
    #  * relies on post-order in order to notice variable usage.
    #  */
    method makeBuilder() :Near {

        # The index of the next temp variable
        var nextTemp := 0

        # Which temp variables have been reused?
        def varReused := [].diverge()  # [].diverge(Bool)

        object deASTBuilder implements DEBuilderOf[EExpr, EExpr] {

            method getNodeType() :Near { EExpr }
            method getRootType() :Near { EExpr }

            # /**
            #  * Return the result after some optimizing transformations.
            #  * <p>
            #  * As we've been building the argument root, we kept track of
            #  * which variables are actually used. For those that were defined
            #  * by buildDef but not actually used, remove the definition
            #  * leaving the rValue.
            #  */
            method buildRoot(root :EExpr) :EExpr {
                # which variables haven't been reused?
                var badNames := [].asSet().diverge()
                for tempIndex => wasReused in (varReused) {
                    if (! wasReused) {
                        badNames.addElement(`t_$tempIndex`)
                    }
                }
                badNames := badNames.snapshot()

                # remove definitions of non-reused variables
                # TODO: when we have makeKernelECopyVisitor
                # object simplify extends makeKernelECopyVisitor(simplify) {
                #     method visitDefineExpr(optOriginal, patt, rValue) :Any {
                #         if (patt =~ fp :FinalPattern) {
                #             def name := fp.optName()
                #             if (badNames.contains(name)) {
                #                 return simplify(rValue)
                #             }
                #         }
                #         super.visitDefineExpr(optOriginal, patt, rValue)
                #     }
                # }

                # simplify(root)
                root
            }

            method buildLiteral(value) :EExpr {
                astBuilder.LiteralExpr(value, null)
            }

            method buildImport(varName :Str) :EExpr {
                astBuilder.NounExpr(varName, null)
            }

            method buildIbid(tempIndex :Int) :EExpr {
                require(tempIndex < nextTemp, fn {
                    `internal: $tempIndex must be < $nextTemp`
                })
                varReused[tempIndex] := true
                astBuilder.NounExpr(`t_$tempIndex`, null)
            }

            method buildCall(rec :EExpr, verb :Str, args :List[EExpr], nargs :Map[Str, EExpr]) :EExpr {
                astBuilder.CallExpr(rec, verb, args, nargs, null)
            }

            method buildDefine(rValue :EExpr) :Pair[EExpr, Int] {
                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def tempPatt := astBuilder.FinalPattern(::"m``".fromStr(`t_$tempIndex`), ANY)
                def defExpr := astBuilder.DefExpr(tempPatt, null, rValue, null)
                [defExpr, tempIndex]
            }

            method buildPromise() :Int {
                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex+1] := false
                promIndex
            }

            # /**
            #  * If the temp variable wasn't actually used, build a define
            #  * instead.
            #  */
            method buildDefrec(resIndex :Int, rValue :EExpr) :EExpr {
                def promIndex := resIndex-1
                def promPatt := astBuilder.FinalPattern(`t_$promIndex`, ANY, null)

                if (varReused[promIndex]) {
                    # We have a cycle
                    def promNoun := astBuilder.NounExpr(`t_$promIndex`, null)
                    def resPatt  := astBuilder.FinalPattern (`t_$resIndex`, ANY, null)
                    def resNoun  := astBuilder.NounExpr(`t_$resIndex`, null)

                    # XXX Should we instead generate the same expansion
                    # generarated by the E parser? This would remove a
                    # recognizion case below.
                    m`def [$promPatt, $resPatt] := Ref.promise()
                      $resNoun.resolve($rValue)
                      $promNoun`

                } else {
                    # No cycle
                    astBuilder.DefExpr(promPatt, null, rValue, null)
                }
            }
        }
    }


    method recognize(ast :EExpr, builder) :(def _Root := builder.getRootType()) {

        def Node := builder.getNodeType()

        def isTempName(varName :Str) :Bool {
            if (varName =~ `t_@digits` && digits.size() >= 1) {
                for digit in (digits) {
                    if (digit < '0' || digit > '9') {
                        return false
                    }
                }
                true
            } else {
                false
            }
        }

        def tempIndices := [].asMap().diverge()

        object visitor {

            method visitLiteralExpr(_, value) :Node {
                builder.buildLiteral(value)
            }

            method visitNounExpr(_, varName :Str) :Node {
                if (isTempName(varName)) {
                    builder.buildIbid(tempIndices[varName])
                } else {
                    builder.buildImport(varName)
                }
            }

            method visitCallExpr(_,
                             rec :EExpr, verb :Str, args :EExpr[]) :Node {
                def recNode := rec.welcome(visitor)
                var argNodes := []
                for arg in (args) {
                    argNodes with= (arg.welcome(visitor))
                }
                builder.buildCall(recNode, verb, argNodes)
            }

            # /**
            #  * Kernel-E guarantees that rValue does not use the variables
            #  * defined by patt.
            #  */
            method visitDefineExpr(_, patt :FinalPattern, rValue :EExpr) :Node {
                def varName :Str := patt.optName()
                require(isTempName(varName))

                def rValueNode := rValue.welcome(visitor)
                def [resultNode, tempIndex] := builder.buildDefine(rValueNode)
                tempIndices.put(varName, tempIndex, true)
                resultNode
            }

            # /**
            #  * The only use Data-E makes of this is for a defrec, so that's the
            #  * only case we need to recognize.
            #  */
            method visitSeqExpr(_, subs) :Node {
                if (subs =~ [sub0, sub1, sub2]) {
                    # Recognize the cycle code we generate

                    def m`def [@varPatt, @resPatt] := Ref.promise()` := sub0
                    def m`@resNoun.resolve(@rightExpr)`              := sub1
                    def m`@varNoun`                                  := sub2
                    def varName := varNoun.name()
                    def resName := resNoun.name()
                    require(varPatt.optName() == varName)
                    require(resPatt.optName() == resName)
                    require(isTempName(varName))
                    require(isTempName(resName))

                    def varIndex := builder.buildPromise()
                    def resIndex := varIndex +1
                    tempIndices.put(varName, varIndex, true)

                    def rValueNode := rightExpr.welcome(visitor)
                    builder.buildDefrec(resIndex, rValueNode)

                } else if (subs =~ [sub0, sub1, sub2, sub3]) {
                    # Recognize the cycle code generated by the E parser

                    def m`def [@varPatt, @resPatt] := Ref.promise()` := sub0
                    def m`def @rPatt := def @oPatt := @rightExpr`    := sub1
                    def m`@resNoun.resolve(@oNoun)`                  := sub2
                    def m`@rNoun`                                    := sub3
                    def varName := varPatt.optName()
                    def resName := resNoun.name()
                    def rName := rNoun.name()
                    def oName := oNoun.name()
                    require(resPatt.optName() == resName)
                    require(rPatt.optName() == rName)
                    require(oPatt.optName() == oName)
                    require(isTempName(oName), fn{`unrecognized: $oName`})

                    def varIndex := builder.buildPromise()
                    def resIndex := varIndex +1
                    tempIndices.put(varName, varIndex, true)

                    def rValueNode := rightExpr.welcome(visitor)
                    builder.buildDefrec(resIndex, rValueNode)
                } else {
                    throw(`unrecognized: $subs`)
                }
            }
        }
        builder.buildRoot(ast.welcome(visitor))
    }
}
