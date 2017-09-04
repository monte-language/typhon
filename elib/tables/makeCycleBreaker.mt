#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

import ":org.erights.e.elib.tables.TraversalKey" =~ [=>TraversalKey :DeepFrozen]
import "tables.TraversalKey" =~ [=>makeTraversalKey :DeepFrozen]

def makeFlexCycleBreaker
def makeConstCycleBreaker

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
def makeROCycleBreaker(roPMap) :Near {
    object readOnlyCycleBreaker {

        to diverge()        :Near { makeFlexCycleBreaker(roPMap.diverge()) }
        to snapshot()       :Near { makeConstCycleBreaker(roPMap.snapshot()) }
        # The following implementation technique is only possible because we're
        # using delegation rather than inheritance.
        to readOnly()       :Near { readOnlyCycleBreaker }

        to maps(key)     :Bool { roPMap.maps(makeTraversalKey(key)) }
        to get(key)          :Any { roPMap[makeTraversalKey(key)] }
        to fetch(key, instead) :Any { roPMap.fetch(makeTraversalKey(key),instead) }

        to with(key, val) :Near {
            makeConstCycleBreaker(roPMap.with(makeTraversalKey(key), val))
        }
        to without(key) :Near {
            makeConstCycleBreaker(roPMap.without(makeTraversalKey(key)))
        }

        to getPowerMap()    :Near { roPMap.readOnly() }
    }
}

# /**
#  *
#  *
#  * @author Mark S. Miller
#  */
bind makeFlexCycleBreaker(flexPMap) :Near {
    # Note that this is just delegation, not inheritance, in that we are not
    # initializing the template with flexCycleBreaker. By the same token,
    # the template makes no reference to <tt>self</tt>.
    object flexCycleBreaker extends makeROCycleBreaker(flexPMap.readOnly()) {

        to put(key, value)  :Void { flexPMap[makeTraversalKey(key)] := value }

        to getPowerMap()    :Near { flexPMap }

        to removeKey(key)   :Void { flexPMap.removeKey(makeTraversalKey(key)) }
    }
}

# /**
#  *
#  *
#  * @author Mark S. Miller
#  */
bind makeConstCycleBreaker(constPMap) :Near {
    object constCycleBreaker extends makeROCycleBreaker(constPMap.readOnly()) {

        to getPowerMap()    :Near { constPMap.snapshot() }
    }
}

def EMPTYConstCycleBreaker := makeConstCycleBreaker([].asMap())

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
object makeCycleBreaker {

    # /**
    #  *
    #  */
    to run() :Near { EMPTYConstCycleBreaker }

    # /**
    #  *
    #  */
    to byInverting(map) :Near {
        def result := EMPTYConstCycleBreaker.diverge()
        for key => value in (map) {
            result[value] := key
        }
        result.snapshot()
    }
}
