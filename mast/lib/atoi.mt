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

def strToInt(var cs :Str, ej) :Int:
    def neg :Bool := cs[0] == '-'
    if (neg):
        cs := cs.slice(1)

    # XXX this sequence would be much easier with range guards
    def ns :List[Int] := [c.asInteger() - 48 for c in cs]
    var rv :Int := 0
    for n in ns:
        if (n < 0 || n >= 10):
            throw.eject(ej, "Digit out of range")
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

[=> strToInt]
