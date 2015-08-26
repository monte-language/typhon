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

def makePath(segments :List[Str]):
    return object path:
        to _uncall():
            return [makePath, segments, [].asMap()]

        to _printOn(out):
            out.print("path`")
            out.print("/".join(segments))
            out.print("`")

        to segments() :List[Str]:
            return segments

        to parent():
            return makePath(segments.slice(0, segments.size() - 1))

        to sibling(name :Str):
            return makePath(segments.with(segments.size() - 1, name))

        to child(name :Str):
            return makePath(segments.with(name))


def testPathParent(assert):
    def path := makePath(["first"])
    assert.equal(path.parent(), makePath([]))

def testPathSibling(assert):
    def path := makePath(["first", "second"])
    assert.equal(path.sibling("other"), makePath(["first", "other"]))

def testPathChild(assert):
    def path := makePath(["first"])
    assert.equal(path.child("second"), makePath(["first", "second"]))

unittest([
    testPathParent,
    testPathSibling,
    testPathChild,
])


object pathPattern:
    pass

object pathValue:
    pass

object path__quasiParser:
    to patternHole(index):
        return [pathPattern, index]

    to valueHole(index):
        return [pathValue, index]

    to valueMaker(pieces):
        return object pathMaker:
            to substitute(values):
                def segments := [].diverge()
                for piece in pieces:
                    switch (piece):
                        match [==pathValue, index]:
                            switch (values[index]):
                                match s :Str:
                                    segments.push(s)
                                match path:
                                    # XXX hopefully a path
                                    for segment in path.segments():
                                        segments.push(segment)
                        match s :Str:
                            for pathPiece in s.split("/"):
                                if (pathPiece != ""):
                                    segments.push(pathPiece)
                        match _:
                            # XXX assume it's a path
                            for segment in piece.segments():
                                segments.push(segment)
                return makePath(segments.snapshot())


def testPathQL(assert):
    def p := path`first/second`
    assert.equal(p, makePath(["first", "second"]))

    def leadingSlash := path`/first/second`
    assert.equal(leadingSlash, makePath(["first", "second"]))

def testPathQLValue(assert):
    def inner := path`second`
    def p := path`first/$inner/third`
    assert.equal(p, path`first/second/third`)

unittest([
    testPathQL,
    testPathQLValue,
])
