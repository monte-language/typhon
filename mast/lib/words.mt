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
import "unittest" =~ [=> unittest :Any]
exports (Word)

def Word.get(width :Int) as DeepFrozen:
    # Precomputed.
    def mask :Int := (1 << width) - 1

    return object WordGuard:
        to _printOn(out):
            out.print(`Word[$width]`)

        to coerce(specimen, ej):
            def int :Int exit ej := specimen
            return int & mask

def testWord(assert):
    assert.ejects(fn ej {def x :Word[32] exit ej := "asdf"})
    var x :Word[8] := 300
    assert.equal(x, 44)
    x *= 7
    assert.equal(x, 52)
    x -= 53
    assert.equal(x, 255)

unittest([testWord])
