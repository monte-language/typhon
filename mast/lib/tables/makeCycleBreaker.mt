#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................
exports (makeCycleBreaker)

def makeTraversalKey :DeepFrozen := _equalizer.makeTraversalKey

def readOnly(m) as DeepFrozen:
    return if (m =~ _:Map):
        m
    else:
        object ro extends m:
            to put(_k, _v):
                throw("read only")


object it as DeepFrozen {

# /**
#  * Provides CycleBeaker equivalents to any of the operations defined by
#  * {@link EMap}.
#  * <p>
#  * This used as the super-object for wrapping an EMap independent of
#  * whether the original is a ConstMap or a FlexMap. Because these are exactly
#  * the read-only operations, this is also used directly as the object that
#  * corresponds to an {@link ROMap} (a Read-Only EMap).
#  *
#  * @param roPMap Should either be a {@link ROMap} or a {@link ConstMap}, ie, a
#  *               valid response from {@link EMap#readOnly()}. This should be a
#  *               <i>PowerMap</i>, ie, all the keys in this map should be
#  *               {@link TraversalKey}s.
#  * @author Mark S. Miller
#  */
method makeROCycleBreaker(roPMap) :Near {
    object readOnlyCycleBreaker {

        method diverge()        :Near { it.makeFlexCycleBreaker(roPMap.diverge()) }
        method snapshot()       :Near { it.makeConstCycleBreaker(roPMap.snapshot()) }
        # The following implementation technique is only possible because we're
        # using delegation rather than inheritance.
        method readOnly()       :Near { readOnlyCycleBreaker }

        method maps(key)     :Bool { roPMap.maps(makeTraversalKey(key)) }
        method get(key)          :Any { roPMap[makeTraversalKey(key)] }
        method fetch(key, instead) :Any { roPMap.fetch(makeTraversalKey(key),instead) }

        method with(key, val) :Near {
            it.makeConstCycleBreaker(roPMap.with(makeTraversalKey(key), val))
        }
        method without(key) :Near {
            it.makeConstCycleBreaker(roPMap.without(makeTraversalKey(key)))
        }

        method getPowerMap()    :Near { readOnly(roPMap) }
    }
}

# /**
#  *
#  *
#  * @author Mark S. Miller
#  */
method makeFlexCycleBreaker(flexPMap) :Near {
    # Note that this is just delegation, not inheritance, in that we are not
    # initializing the template with flexCycleBreaker. By the same token,
    # the template makes no reference to <tt>self</tt>.
    object flexCycleBreaker extends it.makeROCycleBreaker(readOnly(flexPMap)) {

        to put(key, value)  :Void { flexPMap[makeTraversalKey(key)] := value }

        method getPowerMap()    :Near { flexPMap }

        method removeKey(key)   :Void { flexPMap.removeKey(makeTraversalKey(key)) }
    }
}

# /**
#  *
#  *
#  * @author Mark S. Miller
#  */
method makeConstCycleBreaker(constPMap) :Near {
    object constCycleBreaker extends it.makeROCycleBreaker(readOnly(constPMap)) {

        method getPowerMap()    :Near { constPMap.snapshot() }
    }
}

method EMPTYConstCycleBreaker() { it.makeConstCycleBreaker([].asMap()) }

}

# /**
#  * A CycleBreaker is like an EMap except that it accepts unsettled
#  * references as keys.
#  * <p>
#  * This has somewhat counter-intuitive results, as is to be documented at
#  * <a href="http://www.erights.org/elib/equality/same-ref.html"
#  * >Reference Sameness</a>.
#  * <p>
#  * With a CycleBreaker, one can write alorithms to finitely walk infinite
#  * partial structures like
#  * <pre>    def x := [x, p]</pre>
#  * even when <tt>p</tt> is an unresolved Promise. Without CycleBreaker (or
#  * rather, without the primitive it uses, {@link TraversalKey}) this does not
#  * otherwise seem possible.
#  *
#  * @author Mark S. Miller
#  */
object makeCycleBreaker as DeepFrozen {

    # /**
    #  *
    #  */
    method run() :Near { it.EMPTYConstCycleBreaker() }

    # /**
    #  *
    #  */
    to byInverting(map) :Near {
        def result := it.EMPTYConstCycleBreaker().diverge()
        for key => value in (map) {
            result[value] := key
        }
        return result.snapshot()
    }
}
