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

def makeSingleUse(thunk) as DeepFrozen:
    var called :Bool := false
    def singleUse() :Void:
        if (!called):
            called := true
            thunk()
    return singleUse

def testSingleUse(assert):
    var cell := 5
    def thunk():
        cell := 42

    def singleUse := makeSingleUse(thunk)
    singleUse()
    assert.equal(cell, 42)

    cell := 31
    singleUse()
    assert.equal(cell, 31)

unittest([testSingleUse])

[=> makeSingleUse]
