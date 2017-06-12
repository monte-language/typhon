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
import "unittest" =~ [=> unittest]
exports (::"``")

object LITERAL as DeepFrozen {}
object PATTERN_HOLE as DeepFrozen {}
object VALUE_HOLE as DeepFrozen {}

def makeString(chunks :DeepFrozen) as DeepFrozen:
    return def stringMaker.substitute(values) :Str as DeepFrozen:
        def rv := [].diverge()
        for chunk in (chunks):
            switch (chunk):
                match [==VALUE_HOLE, index]:
                    rv.push(M.toString(values[index]))
                match [==PATTERN_HOLE, _]:
                    throw("valueMaker/1: Pattern in expression context")
                match _:
                    rv.push(M.toString(chunk))
        return "".join(rv.snapshot())


object ::"``" as DeepFrozen:
    "A quasiparser of Unicode strings.

     This object is the default quasiparser. It can interpolate any object
     into a string by pretty-printing it; in fact, that is one of this
     object's primary uses.

     When used as a pattern, this object performs basic text matching.
     Patterns always succeed, grabbing zero or more characters non-greedily
     until the next segment. When patterns are concatenated in the
     quasiliteral, only the rightmost pattern can match any characters; the
     other patterns to the left will all match the empty string."

    to patternHole(index):
        return [PATTERN_HOLE, index]

    to valueHole(index):
        return [VALUE_HOLE, index]

    to matchMaker(segments):
        def pieces :DeepFrozen := {
            def l := [].diverge()
            for p in (segments) {
                escape ej {
                    def s :Str exit ej := p
                    if (s.size() > 0) { l.push([LITERAL, s]) }
                } catch _ { l.push(p) }
            }
            l.snapshot()
        }

        return def simpleMatcher.matchBind(values, rawSpecimen, ej) as DeepFrozen:
            def specimen :Str exit ej := rawSpecimen
            var i := 0
            var j := 0
            def bindings := [].diverge()
            for n => piece in (pieces):
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
                        # Double pattern. Whoa. What does it mean?
                        bindings.push("")
                        continue

                    # Start the search at i, so that we don't accidentally
                    # go backwards in the string. (I cursed for a good two
                    # days over this.) ~ C.
                    j := specimen.indexOf(nextVal, i)
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
        return makeString(pieces)


def testQuasiValues(assert):
    def v := `value`
    assert.equal(`such value`, `such $v`)

def testQuasiPatternHead(assert):
    def `@{head}23` := `123`
    assert.equal(head, `1`)

def testQuasiPatternHeadFail(assert):
    assert.ejects(fn j {def `@{_head}23` exit j  := `1234`})

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

def testSampleIRCLine(assert):
    def nick := "nick"
    def `:@_ 353 $nick @_ @channel :@users` := ":host 353 nick = #channel :first second"
    assert.equal(channel, "#channel")
    assert.equal(users, "first second")

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
    testSampleIRCLine,
])
