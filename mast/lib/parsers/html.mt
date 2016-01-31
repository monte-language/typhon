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
exports (parseFragment)
def lowercase :Set[Char] := "abcdefghijklmnopqrstuvwxyz".asSet()
def uppercase :Set[Char] := "ABCDEFGHIJKLMNOPQRSTUVWXYZ".asSet()
def digits :Set[Char] := "0123456789".asSet()

def identifierSet :Set[Char] := lowercase | uppercase | digits

def whitespace :Set[Char] := " \t\n".asSet()

def makeCharStream(input :Str, ej) as DeepFrozen:
    var pos :Int := 0
    return object charStream:
        to eof() :Bool:
            return pos >= input.size()

        to exactly(x :Char):
            if (input[pos] == x):
                pos += 1
            else:
                throw.eject(ej, `Expected $x`)

        to exactlySlice(x :Str):
            def size :Int := x.size()
            if (input.slice(pos, pos + size) == x):
                pos += size
            else:
                throw.eject(ej, `Expected $x`)

        to choose(x :Char) :Bool:
            if (input[pos] == x):
                pos += 1
                return true
            else:
                return false

        to chooseSlice(x :Str) :Bool:
            def size :Int := x.size()
            if (input.slice(pos, pos + size) == x):
                pos += size
                return true
            else:
                return false

        to until(x :Char) :Str:
            def oldPos :Int := pos
            while (pos < input.size() && input[pos] != x):
                pos += 1
            return input.slice(oldPos, pos)

        to whitespace():
            while (pos < input.size() && whitespace.contains(input[pos])):
                pos += 1

        to identifier() :Str:
            def oldPos :Int := pos
            while (pos < input.size() && identifierSet.contains(input[pos])):
                pos += 1
            return input.slice(oldPos, pos)

def testCharStreamIdentifier(assert):
    def cs := makeCharStream("word 7up", null)
    assert.equal(cs.identifier(), "word")
    cs.whitespace()
    assert.equal(cs.identifier(), "7up")

unittest([
    testCharStreamIdentifier,
])

def makeTag(name :Str, fragments :List) as DeepFrozen:
    return object tag:
        to _printOn(out):
            if (fragments.size() != 0):
                out.print(`<$name>`)
                for fragment in fragments:
                    out.print(`$fragment`)
                out.print(`</$name>`)
            else:
                out.print(`<$name/>`)

def parseFragment(cs) as DeepFrozen:
    if (cs.choose('<')):
        # Tag.
        cs.whitespace()
        def name := cs.identifier()
        cs.whitespace()
        if (cs.choose('/')):
            # No body.
            cs.exactly('>')
            return makeTag(name, [])
        else:
            # Must be a body.
            cs.exactly('>')
            var fragments := []
            while (!cs.chooseSlice("</")):
                fragments with= (parseFragment(cs))
            cs.whitespace()
            # Look for an ending tag which matches.
            cs.exactlySlice(name)
            cs.whitespace()
            cs.exactly('>')
            return makeTag(name, fragments)
    else:
        # Not a tag, but a plain text fragment.
        cs.whitespace()
        return cs.until('<')
