#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

# module "org.erights.e.elib.serial.deSubgraphKit"

def Uncaller := <type:org.erights.e.elib.serial.Uncaller>

def deASTKit := <elib:serial.deASTKit>
def DEBuilderOf := <elib:serial.DEBuilderOf>
def deSrcKit := <elib:serial.deSrcKit>
def makeCycleBreaker := <elib:tables.makeCycleBreaker>
def makeUncaller := <elib:serial.makeUncaller>

def defaultUncallers := makeUncaller.getDefaultUncallers()

# See comment on getMinimalScope() below.
def minimalScope := [
    "null"              => null,
    "false"             => false,
    "true"              => true,
    "NaN"               => NaN,
    "Infinity"          => Infinity,
    "__makeList"        => __makeList,
    "__identityFunc"    => __identityFunc,
    "__makeInt"         => __makeInt,
    "import__uriGetter" => import__uriGetter
]

def defaultScope := minimalScope

def minimalScalpel := makeCycleBreaker.byInverting(minimalScope)

def defaultScalpel := minimalScalpel

/**
 * Serialize by generating an expression whose evaluation would produce a
 * reconstruction resembling the original object.
 *
 * @param uncallerList A list of {@link Uncaller}s used as a search path. For a
 *                     given object, calculates what call (if any) would create
 *                     it. Each uncaller is asked until one gives an answer or
 *                     the list is exhausted. Should the list be exhasted,
 *                     recognition terminates with a throw.
 *                     <p>
 *                     uncallerList can be any kind of list -- Flex, Const, RO
 *                     -- since the unevaler snapshot()s it at the beginning of
 *                     each recognize(..).
 * @param scalpelMap The value => variable-name associations we use as an
 *                   "unscope", the inverse of a scope. Given a value, what's
 *                   the name of the variable (if any) that currently has that
 *                   value? The scalpelMap should have at least the inverse of
 *                   the bindings defined in the minimalScope.
 *                   <p>
 *                   Since the scalpelMap generally should be able to map from
 *                   unresolved references (Promises) as keys, it would
 *                   normally be a {@link makeCycleBreaker CycleBreaker}. The
 *                   scalpelMap can be any kind of CycleBreaker -- Flex, Const,
 *                   RO -- since the unevaler diverge()s it at the beginning of
 *                   each recognize(..).
 * @author Mark S. Miller
 */
def makeUnevaler(uncallerList, scalpelMap) :near {

    /**
     *
     */
    def unevaler {
        /**
         *
         */
        to recognize(root, builder) :(def Root := builder.getRootType()) {

            def Node := builder.getNodeType()

            def uncallers := uncallerList.snapshot()

            # We will identify temp variables by storing their index (ints)
            # rather than their name (Strings) as scalpel-values.
            def scalpel := scalpelMap.diverge()

            def generate

            /**
             * traverse an uncall portrayal
             */
            def genCall(rec, verb :String, args :any[]) :Node {
                def recExpr := generate(rec)
                var argExprs := []
                for arg in args {
                    argExprs with= generate(arg)
                }
                builder.buildCall(recExpr, verb, argExprs)
            }

            /**
             * When we're past all the variable manipulation.
             */
            def genObject(obj) :Node {
                # scalars are transparent, but can't be uncalled.
                # They are instead translated to literal expressions.
                # The scalars null, true, and false should have already
                # been picked up by the scalpel -- they should be in the
                # provided scalpelMap.
                if (obj =~ i :int)     { return builder.buildLiteral(i) }
                if (obj =~ f :float64) { return builder.buildLiteral(f) }
                if (obj =~ c :char)    { return builder.buildLiteral(c) }

                # Bare strings are transparent and aren't scalars, but
                # still can't be uncalled. Instead, they are also
                # translated into literal expressions
                if (obj =~ twine :Twine && twine.isBare()) {
                    return builder.buildLiteral(twine)
                }

                for uncaller in uncallers {
                    if (uncaller.optUncall(obj) =~ [rec, verb, args]) {
                        return genCall(rec, verb, args)
                    }
                }
                throw(`Can't uneval ${E.toQuote(obj)}`)
            }

            /** Build a use-occurrence of a variable. */
            def genVarUse(varID :(String | int)) :Node {
                if (varID =~ varName :String) {
                    builder.buildImport(varName)
                } else {
                    builder.buildIbid(varID)
                }
            }

            /**
             * The internal recursive routine that will traverse the
             * subgraph and build a Data-E Node while manipulating the
             * above state.
             */
            bind generate(obj) :Node {
                if (scalpel.get(obj, null) =~ varID :notNull) {
                    return genVarUse(varID)
                }
                def promIndex := builder.buildPromise()
                scalpel[obj] := promIndex
                def rValue := genObject(obj)
                builder.buildDefrec(promIndex+1, rValue)
            }

            builder.buildRoot(generate(root))
        }

        /**
         * A printFunc can be used as an argument in
         * <pre>    interp.setPrintFunc(..)</pre>
         * to be used as the 'print' part of that read-eval-print loop.
         * When using an unevalers printFunc for this purpose, we have instead
         * a read-eval-uneval loop.
         */
        to makePrintFunc() :near {
            def printFunc(value, out :TextWriter) :void {
                def builder := deASTKit.wrap(deSrcKit.makeBuilder())
                out.print(unevaler.recognize(value, builder))
            }
        }
    }
}

def defaultRecognizer := makeUnevaler(defaultUncallers, defaultScalpel)


/**
 * Unserializes/evals by building a subgraph of objects, or serializes/unevals
 * by recognizing/traversing a subgraph of objects.
 *
 * @author Mark S. Miller
 */
def deSubgraphKit {

    /**
     * This is the default scope used for recognizing/serializing/unevaling and
     * for building/unserializing/evaling.
     * <p>
     * The minimal scope only has bindings for<ul>
     * <li>the scalars which can't be written literally<ul>
     *     <li><tt>null</tt>
     *     <li><tt>false</tt>
     *     <li><tt>true</tt>
     *     <li>floating point <tt>NaN</tt>. Same as 0.0/0.0
     *     <li>floating point <tt>Infinity</tt>. Same as 1.0/0.0.
     *     </ul>
     *     The additional scalars which can't be written literally are the
     *     negative numbers, including negative infinity. The can instead be
     *     expressed by a unary "-" or by calling ".negate()" on the magnitude.
     * <li><tt>__makeList</tt>. Many things are built from lists.
     * <li><tt>__identityFunc</tt>. Enables the equivalent of JOSS's
     *     <tt>{@link java.io.ObjectOutputStream#replaceObject
     *                replaceObject()}</tt>
     * <li><tt>__makeInt</tt>. So large integers (as used by crypto) can print
     *     in base64 by using <tt>__makeInt.fromString64("...")</tt>.
     * <li><tt>import__uriGetter</tt>. Used to name safe constructor / makers
     *     of behaviors.
     * </ul>
     */
    to getMinimalScope() :near { minimalScope }

    /**
     * XXX For now, it's the same as the minimalScope, but we expect to add
     * more bindings from the safeScope; possibly all of them.
     */
    to getDefaultScope() :near { defaultScope }

    /**
     *
     */
    to getMinimalScalpel() :near { minimalScalpel }

    /**
     * XXX For now, it's the same as the minimalScalpel, but we expect to add
     * more bindings from the safeScope; possibly all of them.
     */
    to getDefaultScalpel() :near { defaultScalpel }

    /**
     *
     */
    to getDefaultUncallers() :Uncaller[] { defaultUncallers }

    /**
     * Makes a builder which evaluates a Data-E tree in the default scope to a
     * value.
     *
     * @see #getMinimalScope
     */
    to makeBuilder() :near {
        deSubgraphKit.makeBuilder(defaultScope)
    }

    /**
     * Makes a builder which evaluates a Data-E tree in a scope to a value.
     * <p>
     * This <i>is</i> Data-E Unserialization. It is also a subset of E
     * evaluation.
     */
    to makeBuilder(scope) :near {

        # The index of the next temp variable
        var nextTemp := 0

        # The frame of temp variables
        def temps := [].diverge()

        def Node := any
        def Root := any

        def deSubgraphBuilder implements DEBuilderOf(Node, Root) {
            to getNodeType() :near { Node }
            to getRootType() :near { Root }

            to buildRoot(root :Node)        :Root { root }
            to buildLiteral(value)          :Node { value }
            to buildImport(varName :String) :Node { scope[varName] }
            to buildIbid(tempIndex :int)    :Node { temps[tempIndex] }

            to buildCall(rec :Node, verb :String, args :Node[]) :Node {
                E.call(rec, verb, args)
            }

            to buildDefine(rValue :Node) :[Node, int] {
                def tempIndex := nextTemp
                nextTemp += 1
                temps[tempIndex] := rValue
                [rValue, tempIndex]
            }

            to buildPromise() :int {
                def promIndex := nextTemp
                nextTemp += 2
                def [prom,res] := Ref.promise()
                temps[promIndex] := prom
                temps[promIndex+1] := res
                promIndex
            }

            to buildDefrec(resIndex :int, rValue :Node) :Node {
                temps[resIndex].resolve(rValue)
                rValue
            }
        }
    }

    /**
     *
     */
    to getDefaultRecognizer() :near { defaultRecognizer }

    /**
     *
     */
    to makeRecognizer(optUncallers, optScalpel) :near {
        def uncallers := if (null == optUncallers) {
            defaultUncallers
        } else {
            optUncallers
        }
        def scalpel := if (null == optScalpel) {
            defaultScalpel
        } else {
            optScalpel
        }
        makeUnevaler(uncallers, scalpel)
    }

    /**
     * Uses the default recognizer
     */
    to recognize(root, builder) :(def Root := builder.getRootType()) {
        defaultRecognizer.recognize(root, builder)
    }
}
