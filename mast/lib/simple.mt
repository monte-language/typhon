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

def _makeString(chunks):
    return object stringMaker:
        to substitute(values) :String:
            def rv := [].diverge()
            for chunk in chunks:
                switch (chunk):
                    match [=="valueHole", index]:
                        rv.push(M.toString(values[index]))
                    match _:
                        rv.push(M.toString(chunk))
            return "".join(rv.snapshot())


object simple__quasiParser:
    to patternHole(index):
        return ["patternHole", index]

    to valueHole(index):
        return ["valueHole", index]

    to matchMaker(pieces):
        return object simpleMatcher:
            to matchBind(values, specimen, ej):
                # The strategy: Lay down "railroad" segments one at a time,
                # matching against the specimen.
                # XXX var position :(0..!specimen.size()) exit ej := 0
                var position := 0
                var inPattern :Bool := false
                def patterns := [].diverge()
                var patternMarker := 0

                for var piece in pieces:
                    if (piece =~ [=="patternHole", index]):
                        if (inPattern):
                            throw.eject(ej,
                                "Can't catenate patterns with patterns!")
                        inPattern := true
                        patternMarker := position

                        continue

                    if (piece =~ [=="valueHole", index]):
                        # XXX should be index, bindings/slots busted
                        piece := values[piece[1]]

                    # Convert to string.
                    piece := M.toString(piece)

                    def len := piece.size()
                    if (inPattern):
                        # Let's go find a match, and then slice off a pattern.
                        while (specimen.slice(position, position + len) != piece):
                            position += 1
                            if (position >= specimen.size()):
                                throw.eject(ej, "Length mismatch")

                        # Found a match! Mark the pattern, then jump ahead.
                        patterns.push(specimen.slice(patternMarker, position))
                        position += len
                        inPattern := false

                    else:
                        if (specimen.slice(position, position + len) == piece):
                            position += len
                        else:
                            throw.eject(ej, "Couldn't match literal/value")

                if (inPattern):
                    # The final piece was a pattern.
                    patterns.push(specimen.slice(patternMarker,
                                                 specimen.size()))

                return patterns.snapshot()

    to valueMaker(pieces):
        return _makeString(pieces)


def testQuasiValues(assert):
    def v := `value`
    assert.equal(`such value`, `such $v`)

def testQuasiPatternHead(assert):
    def `@{head}23` := `123`
    assert.equal(head, `1`)

def testQuasiPatternMid(assert):
    def `1@{middle}3` := `123`
    assert.equal(middle, `2`)

def testQuasiPatternTail(assert):
    def `12@{tail}` := `123`
    assert.equal(tail, `3`)

def testQuasiPatternSep(assert):
    def sep := `\r\n`
    def `@car$sep@cdr` := `first\r\nsecond\r\nthird`
    assert.equal(car, `first`)
    assert.equal(cdr, `second\r\nthird`)

unittest([
    testQuasiValues,
    testQuasiPatternHead,
    testQuasiPatternMid,
    testQuasiPatternTail,
    testQuasiPatternSep,
])

[=> simple__quasiParser]
