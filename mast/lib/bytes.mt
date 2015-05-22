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

def Bytes := List[0..!256]


def _makeBytes(chunks):
    return object bytes:
        to substitute(values) :Bytes:
            var rv := []
            for chunk in chunks:
                switch (chunk):
                    match [=="valueHole", index]:
                        switch (values[index]):
                            match s :Str:
                                rv += [for c in (s) c.asInteger()]
                            match bs :Bytes:
                                rv += bs
                    match bs :Bytes:
                        rv += bs
            return rv


object b__quasiParser:
    to patternHole(index):
        return ["patternHole", index]

    to valueHole(index):
        return ["valueHole", index]

    to matchMaker(pieces):
        return object byteMatcher:
            to matchBind(values, specimen, ej):
                # The strategy: Lay down "railroad" segments one at a time,
                # matching against the specimen.
                # XXX var position :(0..!specimen.size()) exit ej := 0
                var position :Int := 0
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
                    else:
                        piece := [for c in (piece) c.asInteger()]

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
        def rv := [].diverge()
        for piece in pieces:
            if (piece =~ _ :Str):
                rv.push([for c in (piece) c.asInteger()])
            else:
                rv.push(piece)
        return _makeBytes(rv.snapshot())


def testQuasiValues(assert):
    def v := b`value`
    assert.equal(b`such value`, b`such $v`)

def testQuasiPatterns(assert):
    def v := b`123`

    def b`@{head}23` := v
    assert.equal(head, b`1`)

    def b`1@{middle}3` := v
    assert.equal(middle, b`2`)

    def b`12@{tail}` := v
    assert.equal(tail, b`3`)

    def sep := b`\r\n`
    def b`@car$sep@cdr` := b`first\r\nsecond\r\nthird`
    assert.equal(car, b`first`)
    assert.equal(cdr, b`second\r\nthird`)

def testBytesGuard(assert):
    assert.ejects(fn ej {def bs :Bytes exit ej := [0, 256, 4242]})
    assert.doesNotEject(fn ej {def bs :Bytes exit ej := [42, 5, 0, 255]})

unittest([
    testQuasiValues,
    testQuasiPatterns,
    testBytesGuard,
])

[=> Bytes, => b__quasiParser]
