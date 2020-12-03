import "unittest" =~ [=> unittest :Any]
exports (makeBrandPair)

# Copyright (C) 2015 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

def makeBrand(nickname :NullOk[Str]) as DeepFrozen:
    return object brand as DeepFrozen:
        "A cosmetic label."

        to _printOn(out) :Void:
            out.print(`<brand $nickname>`)

        to getNickName() :NullOk[Str]:
            return nickname

def makeBrandPair(nickname :NullOk[Str]) as DeepFrozen:
    "
    Make a `[sealer, unsealer]` pair.

    The pair have the property that, for all objects `obj`, it is true that
    `unsealer.unseal(sealer.seal(obj)) == obj`. The intermediate sealed
    values, called boxes, cannot be accessed without the unsealer.
    "

    object sentinel:
        pass
    var scratchpad := sentinel

    def brand := makeBrand(nickname)

    def makeBox(contents):
        return object box:
            "A box.

             The boat's a boat, but inside the box there could be anything!
             There could even be a boat!"

            to _printOn(out) :Void:
                out.print(`<box sealed by $brand>`)

            to getBrand():
                return brand

            to shareContent() :Void:
                scratchpad := contents

    object sealer:
        "A sealer."

        to _printOn(out) :Void:
            out.print(`<sealer $brand>`)

        to getBrand():
            return brand

        to seal(specimen):
            "Seal an object into a box.

             The box can only be opened by this object's corresponding
             unsealer."
            return makeBox(specimen)

    object unsealer:
        "An unsealer."

        to _printOn(out) :Void:
            out.print(`<unsealer $brand>`)

        to getBrand():
            return brand

        to unseal(box):
            "
            Unseal a box and retrieve its contents, or throw on failure.

            This object can only unseal boxes created by this object's
            corresponding sealer.
            "

            return unsealer.unsealing(box, null)

        to unsealing(box, ej):
            "
            Unseal a box and retrieve its contents, or eject on failure.

            This object can only unseal boxes created by this object's
            corresponding sealer.
            "

            scratchpad := sentinel
            # XXX should we use an interface instead? Can we use an interface
            # at this point in the prelude?
            try:
                box.shareContent()
            catch _:
                throw.eject(ej, `$unsealer caught exception trying to open $box`)
            if (scratchpad == sentinel):
                throw.eject(ej, `$unsealer cannot unseal $box`)
            def contents := scratchpad
            scratchpad := sentinel
            return contents

    return [sealer, unsealer]


def testBrandCorrect(assert):
    def [ana, cata] := makeBrandPair("correct")
    assert.equal(cata.unseal(ana.seal(42)), 42)

    object singleton {}

    assert.equal(cata.unseal(ana.seal(singleton)), singleton)

def testBrandMismatch(assert):
    def [ana, cata] := makeBrandPair("aliased")
    def [up, down] := makeBrandPair("aliased")
    assert.throws(fn { cata.unseal(up.seal(42)) })
    assert.throws(fn { down.unseal(ana.seal(42)) })

def testBrandUnsealing(assert):
    def [ana, cata] := makeBrandPair("unsealing")

    object singleton {}

    assert.equal(cata.unsealing(ana.seal(singleton), null), singleton)

unittest([
    testBrandCorrect,
    testBrandMismatch,
    testBrandUnsealing,
])

[=> makeBrandPair]
