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
import "unittest" =~ [=> unittest]
exports (makeLFU)
# An object which is greater than all integers.
object INF as DeepFrozen:
    to op__cmp(other :Int):
        return 1

def testINF(assert):
    assert.equal(INF > 0, true)
    assert.equal(INF >= 42, true)
    assert.equal(INF <=> 7, false)
    assert.equal(INF < 5, false)

unittest([testINF])


def makeLFU(size :Int) as DeepFrozen:
    def storage := [].asMap().diverge()

    return object LFU:
        to get(key):
            if (storage.contains(key)):
                def [value, frequency] := storage[key]
                storage[key] := [value, frequency + 1]
                return value
            return null

        to put(key, value):
            if (!storage.contains(key) && storage.size() >= size):
                # We need to evict first.
                LFU.evict()
            storage[key] := [value, 0]

        to evict():
            # This shouldn't happen, but guard against it anyway.
            if (storage.size() == 0):
                return

            var minKey := null
            var minFrequency := INF
            for key => [value, frequency] in storage:
                # Important ordering here. Since INF has custom comparison, it
                # must be on the LHS of the comparison.
                if (minFrequency > frequency):
                    minKey := key
                    minFrequency := minFrequency
            storage.removeKey(minKey)

def testLFU(assert):
    def lfu := makeLFU(2)
    assert.equal(lfu.get("key"), null)
    lfu.put("key", 42)
    assert.equal(lfu.get("key"), 42)
    lfu.put("evicted", 5)
    lfu.evict()
    assert.equal(lfu.get("evicted"), null)

unittest([testLFU])

