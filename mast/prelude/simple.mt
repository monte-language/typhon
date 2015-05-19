# Copyright (C) 2015 the Monte authors. All rights reserved.
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

object LITERAL {}
object PATTERN_HOLE {}
object VALUE_HOLE {}

def _makeString(chunks):
    return object stringMaker:
        to substitute(values) :Str:
            def rv := [].diverge()
            for chunk in chunks:
                switch (chunk):
                    match [==VALUE_HOLE, index]:
                        rv.push(M.toString(values[index]))
                    match _:
                        rv.push(M.toString(chunk))
            return "".join(rv.snapshot())


object simple__quasiParser:
    to patternHole(index):
        return [PATTERN_HOLE, index]

    to valueHole(index):
        return [VALUE_HOLE, index]

    to matchMaker(segments):
        def pieces := [].diverge()
        for p in segments:
            escape e:
                def _ :Str exit e := p
                pieces.push([LITERAL, p])
            catch _:
                pieces.push(p)
        return object simpleMatcher:
            to matchBind(values, specimen :Str, ej):
                var i := 0
                var j := 0
                def bindings := [].diverge()
                for n => piece in pieces:
                    def [typ, val] := piece
                    if (typ == LITERAL):
                        j := i + val.size()
                        if (specimen.slice(i, j) != val):
                            throw.eject(ej,
                                 "expected " +  M.toQuote(val) +
                                 "..., found " +
                                 M.toQuote(specimen.slice(i, j)))

                    else if (typ == VALUE_HOLE):
                        def s := M.toString(values[val])
                        j := i + s.size()
                        if (specimen.slice(i, j) != s):
                            throw.eject(ej,
                                 "expected " + M.toQuote(s) + "... ($-hole " +
                                  M.toQuote(val) + ", found " +
                                  M.toQuote(specimen.slice(i, j)))
                    else if (typ == PATTERN_HOLE):
                        if (n == pieces.size() - 1):
                            bindings.push(specimen.slice(i, specimen.size()))
                            i := specimen.size()
                            continue
                        def [nextType, var nextVal] := pieces[n + 1]
                        if (nextType == VALUE_HOLE):
                            nextVal := values[nextVal]
                        else if (nextType == PATTERN_HOLE):
                            bindings.push("")
                            continue

                        j := specimen.indexOf(nextVal)
                        if (j == -1):
                            throw.eject(ej,
                                 "expected " + M.toQuote(nextVal) +
                                  "..., found " + M.toQuote(specimen.slice(i,
                                                            specimen.size())))
                        bindings.push(specimen.slice(i, j))
                    i := j

                if (i == specimen.size()):
                    return bindings.snapshot()
                throw.eject(ej, "Excess unmatched: " + M.toQuote(specimen.slice(i, j)))


    to valueMaker(pieces):
        return _makeString(pieces)


def testQuasiValues(assert):
    def v := `value`
    assert.equal(`such value`, `such $v`)

def testQuasiPatternHead(assert):
    def `@{head}23` := `123`
    assert.equal(head, `1`)

def testQuasiPatternHeadFail(assert):
    assert.ejects(fn j {def `@{head}23` exit j  := `1234`})

def testQuasiPatternMid(assert):
    def `1@{middle}3` := `123`
    assert.equal(middle, `2`)

def testQuasiPatternTail(assert):
    def `12@{tail}` := `123`
    assert.equal(tail, `3`)

def testQuasiPatternDoubleTail(assert):
    def `12@x@y` := `1234`
    assert.equal(x, "")
    assert.equal(y, "34")

def testQuasiPatternSep(assert):
    def sep := `\r\n`
    def `@car$sep@cdr` := `first\r\nsecond\r\nthird`
    assert.equal(car, `first`)
    assert.equal(cdr, `second\r\nthird`)

def testQuasiPatternEmptySep(assert):
    def a := "baz"
    def `foo @x$a` := "foo baz"
    assert.equal(x, "")

def testQuasiPatternEmptyTail(assert):
    def `1234@tail` := "1234"
    assert.equal(tail, "")

unittest([
    testQuasiValues,
    testQuasiPatternHead,
    testQuasiPatternHeadFail,
    testQuasiPatternMid,
    testQuasiPatternTail,
    testQuasiPatternDoubleTail,
    testQuasiPatternSep,
    testQuasiPatternEmptySep,
    testQuasiPatternEmptyTail,
])

[=> simple__quasiParser]
