#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

def EExpr := <type:org.erights.e.elang.evm.EExpr>
def FinalPattern := <type:org.erights.e.elang.evm.FinalPattern>

def makeCallExpr := <elang:evm.CallExpr>
def makeDefineExpr := <elang:evm.DefineExpr>
def makeFinalPattern := <elang:evm.FinalPattern>
def makeListPattern := <elang:evm.ListPattern>
def makeLiteralExpr := <elang:evm.LiteralExpr>
def makeSeqExpr := <elang:evm.SeqExpr>
def makeSimpleNounExpr := <elang:evm.SimpleNounExpr>

def makeKernelECopyVisitor := <elang:visitors.KernelECopyVisitor>

def ANY := makeSimpleNounExpr(null, "any")

def DEBuilderOf := <elib:serial.DEBuilderOf>

/**
 * Data-E ENodes are the subset of possible Kernel-E ENode ASTs which could
 * result from applying the conventional E-to-Kernel-E expansion to the Data-E
 * subset of E.
 *
 * @author Mark S. Miller
 */
def deENodeKit {

    /**
     * Makes a shrunk Kernel-E AST as the Data-E representation.
     * <p>
     * By "shrunk", we mean that some optimization occur at build time, so that
     * the result of recognizing what's built may be smaller and simpler than
     * the original. In particular, unused temp variables are removed, and
     * Defrec expressions where there isn't actually a cyclic use are turned
     * into Define expressions.
     * <p>
     * Builds a tree by argument passing, rather than using a stack. But still
     * relies on post-order in order to notice variable usage.
     */
    to makeBuilder() :near {

        # The index of the next temp variable
        var nextTemp := 0

        # Which temp variables have been reused?
        def varReused := [].diverge(boolean)

        def deASTBuilder implements DEBuilderOf(EExpr, EExpr) {

            to getNodeType() :near { EExpr }
            to getRootType() :near { EExpr }

            /**
             * Return the result after some optimizing transformations.
             * <p>
             * As we've been building the argument root, we kept track of
             * which variables are actually used. For those that were defined
             * by buildDef but not actually used, remove the definition
             * leaving the rValue.
             */
            to buildRoot(root :EExpr) :EExpr {
                # which variables haven't been reused?
                var badNames := [].asSet().diverge()
                for tempIndex => wasReused in varReused {
                    if (! wasReused) {
                        badNames.addElement(`t_$tempIndex`)
                    }
                }
                badNames := badNames.snapshot()

                # remove definitions of non-reused variables
                def simplify extends makeKernelECopyVisitor(simplify) {
                    to visitDefineExpr(optOriginal, patt, rValue) :any {
                        if (patt =~ fp :FinalPattern) {
                            def name := fp.optName()
                            if (badNames.contains(name)) {
                                return simplify(rValue)
                            }
                        }
                        super.visitDefineExpr(optOriginal, patt, rValue)
                    }
                }

                simplify(root)
            }

            to buildLiteral(value) :EExpr {
                makeLiteralExpr(null, value)
            }

            to buildImport(varName :String) :EExpr {
                makeSimpleNounExpr(null, varName)
            }

            to buildIbid(tempIndex :int) :EExpr {
                require(tempIndex < nextTemp, thunk {
                    `internal: $tempIndex must be < $nextTemp`
                })
                varReused[tempIndex] := true
                makeSimpleNounExpr(null, `t_$tempIndex`)
            }

            to buildCall(rec :EExpr, verb :String, args :EExpr[]) :EExpr {
                makeCallExpr(null, rec, verb, args)
            }

            to buildDefine(rValue :EExpr) :[EExpr, int] {
                def tempIndex := nextTemp
                nextTemp += 1
                varReused[tempIndex] := false
                def tempPatt := makeFinalPattern(null, `t_$tempIndex`, ANY)
                def defExpr := makeDefineExpr(null, tempPatt, rValue)
                [defExpr, tempIndex]
            }

            to buildPromise() :int {
                def promIndex := nextTemp
                nextTemp += 2
                varReused[promIndex] := false
                varReused[promIndex+1] := false
                promIndex
            }

            /**
             * If the temp variable wasn't actually used, build a define
             * instead.
             */
            to buildDefrec(resIndex :int, rValue :EExpr) :EExpr {
                def promIndex := resIndex-1
                def promPatt := makeFinalPattern(null, `t_$promIndex`, ANY)

                if (varReused[promIndex]) {
                    # We have a cycle
                    def promNoun := makeSimpleNounExpr(null, `t_$promIndex`)
                    def resPatt  := makeFinalPattern (null, `t_$resIndex`, ANY)
                    def resNoun  := makeSimpleNounExpr(null, `t_$resIndex`)

                    # XXX Should we instead generate the same expansion
                    # generarated by the E parser? This would remove a
                    # recognizion case below.
                    e`def [$promPatt, $resPatt] := Ref.promise()
                      $resNoun.resolve($rValue)
                      $promNoun`

                } else {
                    # No cycle
                    makeDefineExpr(null, promPatt, rValue)
                }
            }
        }
    }


    to recognize(ast :EExpr, builder) :(def Root := builder.getRootType()) {

        def Node := builder.getNodeType()

        def isTempName(varName :String) :boolean {
            if (varName =~ `t_@digits` && digits.size() >= 1) {
                for digit in digits {
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

        def visitor {

            to visitLiteralExpr(_, value) :Node {
                builder.buildLiteral(value)
            }

            to visitNounExpr(_, varName :String) :Node {
                if (isTempName(varName)) {
                    builder.buildIbid(tempIndices[varName])
                } else {
                    builder.buildImport(varName)
                }
            }

            to visitCallExpr(_,
                             rec :EExpr, verb :String, args :EExpr[]) :Node {
                def recNode := rec.welcome(visitor)
                var argNodes := []
                for arg in args {
                    argNodes with= arg.welcome(visitor)
                }
                builder.buildCall(recNode, verb, argNodes)
            }

            /**
             * Kernel-E guarantees that rValue does not use the variables
             * defined by patt.
             */
            to visitDefineExpr(_, patt :FinalPattern, rValue :EExpr) :Node {
                def varName :String := patt.optName()
                require(isTempName(varName))

                def rValueNode := rValue.welcome(visitor)
                def [resultNode, tempIndex] := builder.buildDefine(rValueNode)
                tempIndices.put(varName, tempIndex, true)
                resultNode
            }

            /**
             * The only use Data-E makes of this is for a defrec, so that's the
             * only case we need to recognize.
             */
            to visitSeqExpr(_, subs) :Node {
                if (subs =~ [sub0, sub1, sub2]) {
                    # Recognize the cycle code we generate

                    def e`def [@varPatt, @resPatt] := Ref.promise()` := sub0
                    def e`@resNoun.resolve(@rightExpr)`              := sub1
                    def e`@varNoun`                                  := sub2
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

                    def e`def [@varPatt, @resPatt] := Ref.promise()` := sub0
                    def e`def @rPatt := def @oPatt := @rightExpr`    := sub1
                    def e`@resNoun.resolve(@oNoun)`                  := sub2
                    def e`@rNoun`                                    := sub3
                    def varName := varPatt.optName()
                    def resName := resNoun.name()
                    def rName := rNoun.name()
                    def oName := oNoun.name()
                    require(resPatt.optName() == resName)
                    require(rPatt.optName() == rName)
                    require(oPatt.optName() == oName)
                    require(isTempName(oName), thunk{`unrecognized: $oName`})

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
