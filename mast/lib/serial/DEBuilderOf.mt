#!/usr/bin/env rune

# Copyright 2002 Combex, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

# module "org.erights.e.elib.serial.DEBuilderOf"
import "lib/serial/guards" =~ [=>Guard :DeepFrozen]
exports (DEBuilderOf)

# /**
#  * Data-E is the subset of E used for serializing a subgraph by unevaling to an
#  * expression.
#  *
#  * @see <a hrep=
#  *       "http://www.erights.org/data/serial/jhu-paper/modeling.html#as-eval"
#  * >Unserialization as Expression Evaluation</a>.
#  * @author Mark S. Miller
#  */
def DEBuilderOf.get(Node :Guard, _Root :Guard) :Guard as DeepFrozen {

    interface _DEBuilder {

        # /**
        #  * What's the actual type corresponding to the Node type parameter?
        #  */
        to getNodeType() :Guard

        # /**
        #  * What's the actual type corresponding to the Root type parameter?
        #  */
        to getRootType() :Guard

        # /**
        #  * An opportunity to do some post-optimizations, writing out trailers,
        #  * and closing.
        #  * <p>
        #  * [root] => buildRoot()
        #  * <p>
        #  * This must appear exactly once at the end.
        #  */
        to buildRoot(root :Node) :Node

        # /**
        #  * For literal values -- ints, float64s, chars, or bare Strings.
        #  * <p>
        #  * [] => buildLiteral(value) => [value]
        #  */
        to buildLiteral(value :Any[Int, Double, Char, Str]) :Node

        # /**
        #  * Generates a use-occurrence of a named variable.
        #  * <p>
        #  * [] => buildImport(varName) => [value]
        #  * <p>
        #  * Load the value of the named variable from the scope.
        #  */
        to buildImport(varName :Str) :Node

        # /**
        #  * Generates a use-occurrence of an temp variable.
        #  * <p>
        #  * [] => buildIbid(tempIndex) => [value]
        #  * <p>
        #  * Load the value of the temp variable at that index.
        #  */
        to buildIbid(tempIndex :Int) :Node

        # /**
        #  * Generates a call-expression.
        #  * <p>
        #  * [rec, arg0,...] => buildCall(verb,arity) => [result]
        #  */
        to buildCall(rec :Node, verb :Str, args :List[Node]) :Node

        # /**
        #  * Allocates the next tempIndex, defines it to hold the value of
        #  * rValue, and return a pair of the generated definition and the index
        #  * of the new temp variable.
        #  * <p>
        #  * [rValue] => buildDefine() => [rValue]
        #  * <p>
        #  * If rValue needs to use the new variable, use
        #  * buildPromise/buildDefrec instead.
        #  */
        to buildDefine(rValue :Node) :Pair[Node, Int]

        # /**
        #  * Like a forward variable declaration in E (def varName).
        #  * <p>
        #  * [] => buildPromise() => []
        #  * <p>
        #  * Allocates the next two temp variables. Defines them to hold a
        #  * promise and its Resolver, respectively.
        #  */
        to buildPromise() :Int

        # /**
        #  * Resolves a promise to the value of rValue.
        #  * <p>
        #  * [rValue] => buildDefrec(resolverIndex) => [rValue]
        #  */
        to buildDefrec(resolverIndex :Int, rValue :Node) :Node
    }
}
