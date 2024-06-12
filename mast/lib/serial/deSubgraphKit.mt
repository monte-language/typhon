#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

# module "org.erights.e.elib.serial.deSubgraphKit"

# TODO: import "serial.deASTKit" =~ [=>deASTKit :DeepFrozen]
import "lib/serial/DEBuilderOf" =~ [=>DEBuilderOf :DeepFrozen]
# TODO: import "serial.deSrcKit" =~ [=>deSrcKit :DeepFrozen]
import "lib/tables/makeCycleBreaker" =~ [=>makeCycleBreaker :DeepFrozen]
import "lib/serial/makeUncaller" =~ [=>makeUncaller :DeepFrozen, =>Uncaller :DeepFrozen]
exports (makeUnevaler, deSubgraphKit)

def defaultUncallers :DeepFrozen := makeUncaller.getDefaultUncallers()

# See comment on getMinimalScope() below.
def minimalScope :DeepFrozen := [
    "null"              => null,
    "false"             => false,
    "true"              => true,
    "NaN"               => NaN,
    "Infinity"          => Infinity,
    "_makeList"        => _makeList,
#    "__identityFunc"    => __identityFunc,
    "_makeInt"         => _makeInt,
#    "import__uriGetter" => import__uriGetter
]

def defaultScope :DeepFrozen := minimalScope
def toScalpel(scope) as DeepFrozen:
    return makeCycleBreaker.byInverting(scope)


# /**
#  * Serialize by generating an expression whose evaluation would produce a
#  * reconstruction resembling the original object.
#  *
#  * @param uncallerList A list of {@link Uncaller}s used as a search path. For a
#  *                     given object, calculates what call (if any) would create
#  *                     it. Each uncaller is asked until one gives an answer or
#  *                     the list is exhausted. Should the list be exhasted,
#  *                     recognition terminates with a throw.
#  *                     <p>
#  *                     uncallerList can be any kind of list -- Flex, Const, RO
#  *                     -- since the unevaler snapshot()s it at the beginning of
#  *                     each recognize(..).
#  * @param scalpelMap The value => variable-name associations we use as an
#  *                   "unscope", the inverse of a scope. Given a value, what's
#  *                   the name of the variable (if any) that currently has that
#  *                   value? The scalpelMap should have at least the inverse of
#  *                   the bindings defined in the minimalScope.
#  *                   <p>
#  *                   Since the scalpelMap generally should be able to map from
#  *                   unresolved references (Promises) as keys, it would
#  *                   normally be a {@link makeCycleBreaker CycleBreaker}. The
#  *                   scalpelMap can be any kind of CycleBreaker -- Flex, Const,
#  *                   RO -- since the unevaler diverge()s it at the beginning of
#  *                   each recognize(..).
#  * @author Mark S. Miller
#  */
def makeUnevaler(uncallerList, scalpelMap) :Near as DeepFrozen {

    # /**
    #  *
    #  */
    return object unevaler {
        # /**
        #  *
        #  */
        to recognize(root, builder) :(def _Root := builder.getRootType()) {

            def Node := builder.getNodeType()

            def uncallers := uncallerList.snapshot()

            # We will identify temp variables by storing their index (ints)
            # rather than their name (Strings) as scalpel-values.
            def scalpel := scalpelMap.diverge()

            def generate

            # /**
            #  * traverse an uncall portrayal
            #  */
            def genCall(rec, verb :Str, args :List[Any], nargs :Map[Str, Any]) :Node {
                return builder.buildCall(
                    generate(rec), verb,
                    [for arg in (args) generate(arg)],
                    [for name => arg in (nargs) name => generate(arg)])
            }

            # /**
            #  * When we're past all the variable manipulation.
            #  */
            def genObject(obj) :Node {
                # scalars are transparent, but can't be uncalled.
                # They are instead translated to literal expressions.
                # The scalars null, true, and false should have already
                # been picked up by the scalpel -- they should be in the
                # provided scalpelMap.
                if (obj =~ i :Int)     { return builder.buildLiteral(i) }
                if (obj =~ f :Double) { return builder.buildLiteral(f) }
                if (obj =~ c :Char)    { return builder.buildLiteral(c) }
                if (obj =~ s :Str)    { return builder.buildLiteral(s) }

                # Bare strings are transparent and aren't scalars, but
                # still can't be uncalled. Instead, they are also
                # translated into literal expressions
                # TODO: when/if monte gets Twine
                # if (obj =~ twine :Twine && twine.isBare()) {
                #     return builder.buildLiteral(twine)
                # }

                for uncaller in (uncallers) {
                    if (uncaller.optUncall(obj) =~ [rec, verb, args, nargs]) {
                        return genCall(rec, verb, args, nargs)
                    }
                }
                throw(`Can't uneval ${M.toQuote(obj)}`)
            }

            # /** Build a use-occurrence of a variable. */
            def genVarUse(varID :Any[Str, Int]) :Node {
                return if (varID =~ varName :Str) {
                    builder.buildImport(varName)
                } else {
                    builder.buildIbid(varID)
                }
            }

            # /**
            #  * The internal recursive routine that will traverse the
            #  * subgraph and build a Data-E Node while manipulating the
            #  * above state.
            #  */
            bind generate(obj) :Node {
                escape notSeen {
                    return genVarUse(scalpel.fetch(obj, notSeen))
                }
                def promIndex := builder.buildPromise()
                scalpel[obj] := promIndex
                def rValue := genObject(obj)
                return builder.buildDefrec(promIndex+1, rValue)
            }

            return builder.buildRoot(generate(root))
        }

        # /**
        #  * A printFunc can be used as an argument in
        #  * <pre>    interp.setPrintFunc(..)</pre>
        #  * to be used as the 'print' part of that read-eval-print loop.
        #  * When using an unevalers printFunc for this purpose, we have instead
        #  * a read-eval-uneval loop.
        #  */
        # TODO: to makePrintFunc() :Near {
        #     def printFunc(value, out :TextWriter) :Void {
        #         def builder := deASTKit.wrap(deSrcKit.makeBuilder())
        #         out.print(unevaler.recognize(value, builder))
        #     }
        # }

        to _muteSMO() {}
    }
}


# /**
#  * Unserializes/evals by building a subgraph of objects, or serializes/unevals
#  * by recognizing/traversing a subgraph of objects.
#  *
#  * @author Mark S. Miller
#  */
object deSubgraphKit as DeepFrozen {

    # /**
    #  * This is the default scope used for recognizing/serializing/unevaling and
    #  * for building/unserializing/evaling.
    #  * <p>
    #  * The minimal scope only has bindings for<ul>
    #  * <li>the scalars which can't be written literally<ul>
    #  *     <li><tt>null</tt>
    #  *     <li><tt>false</tt>
    #  *     <li><tt>true</tt>
    #  *     <li>floating point <tt>NaN</tt>. Same as 0.0/0.0
    #  *     <li>floating point <tt>Infinity</tt>. Same as 1.0/0.0.
    #  *     </ul>
    #  *     The additional scalars which can't be written literally are the
    #  *     negative numbers, including negative infinity. The can instead be
    #  *     expressed by a unary "-" or by calling ".negate()" on the magnitude.
    #  * <li><tt>__makeList</tt>. Many things are built from lists.
    #  * <li><tt>__identityFunc</tt>. Enables the equivalent of JOSS's
    #  *     <tt>{@link java.io.ObjectOutputStream#replaceObject
    #  *                replaceObject()}</tt>
    #  * <li><tt>__makeInt</tt>. So large integers (as used by crypto) can print
    #  *     in base64 by using <tt>__makeInt.fromString64("...")</tt>.
    #  * <li><tt>import__uriGetter</tt>. Used to name safe constructor / makers
    #  *     of behaviors.
    #  * </ul>
    #  */
    method getMinimalScope() :Near { minimalScope }

    # /**
    #  * XXX For now, it's the same as the minimalScope, but we expect to add
    #  * more bindings from the safeScope; possibly all of them.
    #  */
    method getDefaultScope() :Near { defaultScope }

    # /**
    #  *
    #  */
    method getMinimalScalpel() :Near { toScalpel(minimalScope) }

    # /**
    #  * XXX For now, it's the same as the minimalScalpel, but we expect to add
    #  * more bindings from the safeScope; possibly all of them.
    #  */
    method getDefaultScalpel() :Near { toScalpel(defaultScope) }

    # /**
    #  *
    #  */
    method getDefaultUncallers() :List[Uncaller] { defaultUncallers }

    # /**
    #  * Makes a builder which evaluates a Data-E tree in the default scope to a
    #  * value.
    #  *
    #  * @see #getMinimalScope
    #  */
    method makeBuilder() :Near {
        deSubgraphKit.makeBuilder(defaultScope)
    }

    # /**
    #  * Makes a builder which evaluates a Data-E tree in a scope to a value.
    #  * <p>
    #  * This <i>is</i> Data-E Unserialization. It is also a subset of E
    #  * evaluation.
    #  */
    to makeBuilder(scope) :Near {

        # The frame of temp variables
        def temps := [].diverge()

        def Node := Any
        def Root := Any

        return object deSubgraphBuilder implements DEBuilderOf[Node, Root] {
            method getNodeType() :Near { Node }
            method getRootType() :Near { Root }

            method buildRoot(root :Node)        :Root { root }
            method buildLiteral(value)          :Node { value }
            method buildImport(varName :Str) :Node { scope[varName] }
            method buildIbid(tempIndex :Int)    :Node { temps[tempIndex] }

            method buildCall(rec :Node, verb :Str, args :List[Node], nargs :Map[Str, Node]) :Node {
                M.call(rec, verb, args, nargs)
            }

            method buildDefine(rValue :Node) :Pair[Node, Int] {
                def tempIndex := temps.size()
                temps.push(rValue)
                [rValue, tempIndex]
            }

            method buildPromise() :Int {
                def promIndex := temps.size()
                def [prom,res] := Ref.promise()
                temps.push(prom)
                temps.push(res)
                promIndex
            }

            method buildDefrec(resIndex :Int, rValue :Node) :Node {
                temps[resIndex].resolve(rValue)
                rValue
            }
        }
    }

    # /**
    #  *
    #  */
    to getDefaultRecognizer() :Near {
        return makeUnevaler(defaultUncallers, toScalpel(defaultScope))
    }

    # /**
    #  *
    #  */
    method makeRecognizer(optUncallers, optScalpel) :Near {
        def uncallers := if (null == optUncallers) {
            defaultUncallers
        } else {
            optUncallers
        }
        def scalpel := if (null == optScalpel) {
            toScalpel(defaultScope)
        } else {
            optScalpel
        }
        makeUnevaler(uncallers, scalpel)
    }

    # /**
    #  * Uses the default recognizer
    #  */
    method recognize(root, builder) :(def _Root := builder.getRootType()) {
        def defaultRecognizer := deSubgraphKit.getDefaultRecognizer()
        defaultRecognizer.recognize(root, builder)
    }
}
