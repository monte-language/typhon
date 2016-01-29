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

# This is Montgomery's ladder, a well-known exponentation algorithm. It should
# take around log2(e) steps regardless of the actual bits in e. Note that the
# non-modular version leaks exponent information via the overall magnitude of
# the intermediate results, which can be measured in the time taken to perform
# each multiplication.
import "unittest" =~ [=> unittest]
import "bench" =~ [=> bench]
exports (slowPow, slowModPow)

def slowPow(x :Int, e :Int) :Int as DeepFrozen:
    var r0 := 1
    var r1 := x
    for i in (0..!(e.bitLength())).descending():
        if (((e >> i) & 1) == 0):
            r1 *= r0
            r0 *= r0
        else:
            r0 *= r1
            r1 *= r1
    return r0


def slowModPow(x :Int, e :Int, m :Int) :Int as DeepFrozen:
    var r0 := 1
    var r1 := x
    for i in (0..!(e.bitLength())).descending():
        if (((e >> i) & 1) == 0):
            r1 := (r0 * r1) % m
            r0 := (r0 * r0) % m
        else:
            r0 := (r0 * r1) % m
            r1 := (r1 * r1) % m
    return r0


def testSlowPow(assert):
    assert.equal(slowPow(17, 42), 17 ** 42)
    assert.equal(slowPow(17, 0x7000), 17 ** 0x7000)
    assert.equal(slowPow(17, 0xffff), 17 ** 0xffff)

unittest([testSlowPow])


def testSlowModPow(assert):
    assert.equal(slowModPow(13, 42, 65537), 13 ** 42 % 65537)
    assert.equal(slowModPow(13, 0x7000000, 65537), 13 ** 0x7000000 % 65537)
    assert.equal(slowModPow(13, 0xfffffff, 65537), 13 ** 0xfffffff % 65537)

unittest([testSlowModPow])

bench(fn {13 ** 0x7000000 % 65537},
      "modPow(e=0x7000000, m=65537)")
bench(fn {13 ** 0xfffffff % 65537},
      "modPow(e=0xfffffff, m=65537)")
bench(fn {slowModPow(13, 0x7000000, 65537)},
      "slowModPow(e=0x7000000, m=65537)")
bench(fn {slowModPow(13, 0xfffffff, 65537)},
      "slowModPow(e=0xfffffff, m=65537)")

