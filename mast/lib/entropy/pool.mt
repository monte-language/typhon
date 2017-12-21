import "unittest" =~ [=> unittest :Any]
exports (makePool)

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

def makePool(entropy) as DeepFrozen:
    # Convention: Fill on the left, slice on the right.
    var pool :Int := 0
    var bits :(Int >= 0) := 0

    def fill():
        def [size, data] := entropy.getEntropy()
        # traceln(`fill pool=$pool bits=$bits data=$data size=$size`)
        pool |= data << bits
        bits += size

    return object entropyPool:
        # Pools are entropic sources that present an infinite reservoir of
        # bits which can be taken k bits at a time for any k.
        to getSomeBits(k :(Int >= 0)) :Int:
            while (bits < k):
                fill()
            # traceln(`k=$k; 1 << k=${1 << k}`)
            def rv := pool & ((1 << k) - 1)
            pool >>= k
            bits -= k
            # traceln(`getSomeBits($k) pool=$pool bits=$bits -> $rv`)
            return rv

        to availableEntropy() :Int:
            # Not total available entropy, just current entropy that can be
            # grabbed right at this moment.
            return bits

def testPool(assert):
    def entropy.getEntropy():
        return [5, 0xf]

    def pool := makePool(entropy)
    assert.equal(pool.getSomeBits(0), 0x0)
    assert.equal(pool.getSomeBits(1), 0x1)
    assert.equal(pool.getSomeBits(2), 0x3)
    assert.equal(pool.getSomeBits(3), 0x5)

unittest([testPool])
