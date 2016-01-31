import "unittest" =~ [=> unittest]
exports (makeEntropy)

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

import "lib/entropy/pool" =~  [=> makePool :DeepFrozen]
exports (makeEntropy)

def makeEntropy(generator) as DeepFrozen:
    def pool := makePool(generator)

    return object entropy:
        to availableEntropy() :Int:
            return pool.availableEntropy()

        to getAlgorithm() :Str:
            return generator.getAlgorithm()

        to nextBool() :Bool:
            return pool.getSomeBits(1) == 0

        to nextInt(n :(Int > 0)) :Int:
            # Unbiased selection: If a sample doesn't fit within the bound,
            # then discard it and take another one.
            def k := n.bitLength()
            var rv := pool.getSomeBits(k)
            # traceln(`nextInt($n) k=$k -> $rv`)
            while (rv >= n):
                # traceln(`Was too big!`)
                rv := pool.getSomeBits(k)
                # traceln(`nextInt($n) k=$k -> $rv`)
            return rv

        to nextDouble() :Double:
            return pool.getSomeBits(53) / (1 << 53)

        to nextExponential(lambda :Double):
            "The exponential distribution with half-life λ."

            # This kind of inversion lets us avoid a conditional check for 0.0
            # before taking a logarithm.
            def d := 1.0 - entropy.nextDouble()
            return -(d.log()) / lambda
