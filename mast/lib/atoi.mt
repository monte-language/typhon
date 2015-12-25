# Copyright (C) 2014 Google Inc. All rights reserved.
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

def strToInt(var cs :Str, ej) :Int as DeepFrozen:
    def neg :Bool := cs[0] == '-'
    if (neg):
        cs := cs.slice(1)

    def ns :List[0..!10] exit ej := [for c in (cs) c.asInteger() - 48]
    var rv :Int := 0
    for n in ns:
        rv := rv * 10 + n
    if (neg):
        rv *= -1
    return rv

def testStrToInt(assert):
    assert.equal(strToInt("42", null), 42)

def testStrToIntNegative(assert):
    assert.equal(strToInt("-42", null), -42)

def testStrToIntFail(assert):
    assert.ejects(fn ej { def via (strToInt) x exit ej := "asdf" })

unittest([
    testStrToInt,
    testStrToIntNegative,
    testStrToIntFail,
])


def bytesToInt(bs :Bytes, ej) :Int as DeepFrozen:
    var rv :Int := 0
    for b in bs:
        def i :(0..!10) exit ej := b - 48
        rv := rv * 10 + i
    return rv

def testBytesToInt(assert):
    assert.equal(bytesToInt(b`200`, null), 200)

def testBytesToIntFailure(assert):
    assert.ejects(fn ej {def via (bytesToInt) x exit ej := b`20xx`})

unittest([
    testBytesToInt,
    testBytesToIntFailure,
])


[=> strToInt, => bytesToInt]
