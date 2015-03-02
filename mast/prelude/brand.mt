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


def makeBrand(nickname :NullOk[Str]):
    return object brand:
        to _printOn(out) :Void:
            out.print(`$nickname`)

        to getNickName() :NullOk[Str]:
            return nickname


def makeBrandPair(nickname :NullOk[Str]):
    object sentinel:
        pass
    var scratchpad := sentinel

    def brand := makeBrand(nickname)

    def makeBox(contents):
        return object box:
            to _printOn(out) :Void:
                out.print(`<box sealed by $brand>`)

            to getBrand():
                return brand
                
            to shareContent() :Void:
                scratchpad := contents

    object sealer:
        to _printOn(out) :Void:
            out.print(`<sealer $brand>`)

        to getBrand():
            return brand

        to seal(specimen):
            return makeBox(specimen)

    object unsealer:
        to _printOn(out) :Void:
            out.print(`<sealer $brand>`)

        to getBrand():
            return brand

        to unseal(box):
            scratchpad := sentinel
            box.shareContent()
            if (scratchpad == sentinel):
                throw(`$unsealer cannot unseal $box`)
            def contents := scratchpad
            scratchpad := sentinel
            return contents

    return [sealer, unsealer]


def testBrandCorrect(assert):
    def [ana, cata] := makeBrandPair("correct")
    assert.equal(cata.unseal(ana.seal(42)), 42)

    object singleton:
        pass

    assert.equal(cata.unseal(ana.seal(singleton)), singleton)

def testBrandMismatch(assert):
    def [ana, cata] := makeBrandPair("aliased")
    def [up, down] := makeBrandPair("aliased")
    assert.throws(fn { cata.unseal(up.seal(42)) })
    assert.throws(fn { down.unseal(ana.seal(42)) })

unittest([
    testBrandCorrect,
    testBrandMismatch,
])

[=> makeBrandPair]
