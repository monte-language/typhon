#!/usr/bin/env rune

# Copyright 2003 Hewlett Packard, Inc. under the terms of the MIT X license
# found at http://www.opensource.org/licenses/mit-license.html ................

# import "serial.RemoteCall" =~ [=>makeRemoteCall :DeepFrozen]
import "./guards" =~ [=>NotNull :DeepFrozen]  # =>DFTuple :DeepFrozen
exports (makeUncaller, Uncaller)

def Portrayal :DeepFrozen := List  # Tuple[Any, Str, List, Map[Str, Any]]

interface Uncaller :DeepFrozen:
    to optUncall(obj) :NullOk[Portrayal]

object minimalUncaller as DeepFrozen implements Uncaller {
    method optUncall(obj) :NullOk[Portrayal] {
        if (Ref.isNear(obj)) {
            obj._uncall()
        } else if (Ref.isBroken(obj)) {
            [Ref, "broken", [Ref.optProblem(obj)], [].asMap()]
        } else {
            throw("TODO: makeRemoteCall.optUncall(obj)")
        }
    }
    to _muteSMO() {}
}

def minimalUncallers :DeepFrozen := [minimalUncaller]  # TODO: , import__uriGetter

def defaultUncallers :DeepFrozen := minimalUncallers

# /**
#  * Makes an uncall function that, when applied to a transparent-enough object,
#  * will return the ingredients of a call expression that, when performed, will
#  * reconstruct a new object adequately similar to the original.
#  * <p>
#  * An uncall function is used as a component in making a subgraph recognizer,
#  * ie, an uneval function.
#  *
#  * @author Mark S. Miller
#  */
object makeUncaller as DeepFrozen {

    # /**
    #  *
    #  */
    method getMinimalUncallers() :List[Uncaller] { minimalUncallers }

    # /**
    #  * XXX For now it's the same as minimalUncallers, but we expect to add
    #  * the other uriGetters from the safeScope.
    #  */
    method getDefaultUncallers() :List[Uncaller] { defaultUncallers }

    # /**
    #  * Makes an amplifyingUncall to implement selective transparency.
    #  * <p>
    #  * A object that isn't objectively transparent is transparent to the
    #  * ampliedUncall if it responds to
    #  * <tt>__optSealedDispatch(unsealer.getBrand())</tt> with a sealed
    #  * box, sealed by the corresponding sealer, containing the kind of three
    #  * element list an uncall function needs to return. This list should
    #  * is the elements of a call that, if performed, should create an
    #  * object that resembles the original object.
    #  *
    #  * @param baseUncall This is tried first, and if it succeeds, we're done.
    #  * @param unsealer If baseUncall fails, we use this unsealer to try to
    #  *                 access the object's private state by rights
    #  *                 amplification.
    #  *                 Currently, this can only be an individual Unsealer,
    #  *                 but we should create something like the KeyKOS
    #  *                 CanOpener composed of a searchpath of Unsealers.
    #  * @return null, or the kind of three
    #  * element list an uncall function needs to return, consisting of:<ul>
    #  * <li>The receiver
    #  * <li>The "verb", ie, the message name to call with
    #  * <li>The list of arguments
    #  * </ul>
    #  */
    method makeAmplifier(unsealer) :Uncaller {
        object amplifier {
            to optUncall(obj) :NullOk[Portrayal] {

                if (unsealer.amplify(obj) =~ [result]) {
                    result
                } else {
                    null
                }
            }
            to _muteSMO() {}
        }
    }

    # /**
    #  * Make an onlySelflessUncaller by wrapping baseUncallers with a
    #  * pre-condition that accepts only Selfless objects.
    #  * <p>
    #  * uncall on a Selfless object has all the guarantees explained at
    #  * {@link org.erights.e.elib.prim.MirandaMethods#__optUncall}.
    #  * An onlySelflessUncaller is for the purpose of restricting uncall to
    #  * those cases where these strong guarantees apply.
    #  */
    to onlySelfless(baseUncallers) :Uncaller {

        object onlySelflessUncaller {
            method optUncall(obj) :NullOk[Portrayal] {
                if (Ref.isSelfless(obj)) {
                    for baseUncaller in (baseUncallers) {
                        if (baseUncaller.optUncall(obj) =~
                              result :NotNull) {

                            return result
                        }
                    }
                }
                null
            }
            to _muteSMO() {}
        }
    }
}

