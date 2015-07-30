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

def [=> bytesToInt] | _ := import("lib/atoi")

def toNetstring(cs :Bytes) :Bytes:
    def header := `${cs.size()}`
    return b`$header:$cs,`

def findNetstring(cs :Bytes):
    escape ej:
        def b`@{via (bytesToInt) size}:@tail` exit ej := cs
        if (tail.size() < size):
            return null

        return [tail.slice(0, size), tail.slice(size + 1)]
    catch _:
        return null

def testToNetstringEmpty(assert):
    assert.equal(b`0:,`, toNetstring(b``))

def testToNetstring(assert):
    assert.equal(b`3:123,`, toNetstring(b`123`))

def testFindNetstringEmpty(assert):
    assert.equal([b``, b``], findNetstring(b`0:,`))

def testFindNetstring(assert):
    assert.equal([b`hello world!`, b``], findNetstring(b`12:hello world!,`))

unittest([
    testToNetstringEmpty,
    testToNetstring,
    testFindNetstringEmpty,
    testFindNetstring,
])
