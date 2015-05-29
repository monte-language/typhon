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

def [=> makeLoopingCall] := import("lib/loopingCall")

def makeTokenBucket(maximumSize :Int, refillRate :Double):
    var currentSize :Int := maximumSize
    var resolvers := []
    var loopingCall := null

    return object tokenBucket:
        to getBurstSize() :Int:
            return maximumSize

        to deduct(count :Int) :Bool:
            if (count < currentSize):
                currentSize -= count
                return true
            return false

        to replenish(count :Int) :Void:
            if (currentSize < maximumSize):
                currentSize += count

            for r in resolvers:
                r.resolve(null)
            resolvers := []

        to start(timer) :Void:
            loopingCall := makeLoopingCall(timer,
                fn {tokenBucket.replenish(1)})
            loopingCall.start(refillRate)

        to stop() :Void:
            loopingCall.stop()

        to ready():
            def [p, r] := Ref.promise()
            resolvers with= (r)
            return p

[=> makeTokenBucket]
