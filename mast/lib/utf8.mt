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

def chr(i :Int) :Char:
    return '\x00' + i

def testChr(assert):
    assert.equal('\x00', chr(0x00))
    assert.equal('\n', chr(0x0a))
    # XXX assert.equal('▲', chr(0x25b2))
    assert.equal('\u25b2', chr(0x25b2))


def iterDecode(iterator):
    var index := 0

    return object UTF8Decoder:
        to next(ej):
            def [_, b :Int] := iterator.next(ej)
            var c := '\ufffd'

            if ((b & 0x80) == 0x00):
                # One byte.
                c := b
            else if ((b & 0xe0) == 0xc0):
                # Two bytes.
                c := (b & 0x1f) << 6
                c |= iterator.next(ej)[1] & 0x3f
            else if ((b & 0xf0) == 0xe0):
                # Three bytes.
                c := (b & 0x0f) << 12
                c |= (iterator.next(ej)[1] & 0x3f) << 6
                c |= iterator.next(ej)[1] & 0x3f
            else if ((b & 0xf7) == 0xf0):
                # Four bytes.
                c := (b & 0x07) << 18
                c |= (iterator.next(ej)[1] & 0x3f) << 12
                c |= (iterator.next(ej)[1] & 0x3f) << 6
                c |= iterator.next(ej)[1] & 0x3f

            def rv := [index, chr(c)]
            index += 1
            return rv

def wrapIterable(wrapper, iterable):
    return object wrappedIterable:
        to _makeIterator():
            return wrapper(iterable._makeIterator())

def decode(bytes):
    return "".join([c.asString() for c in wrapIterable(iterDecode, bytes)])

def testIterDecode(assert):
    # One byte.
    assert.equal("\x00", decode([0x00]))
    assert.equal("\n", decode([0x0a]))
    # Two bytes.
    # XXX é
    assert.equal("\u00e9", decode([0xc3, 0xa9]))
    # Three bytes.
    # XXX ▲
    assert.equal("\u25b2", decode([0xe2, 0x96, 0xb2]))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal("\U0001f3d4", decode([0xf0, 0x9f, 0x8f, 0x94]))


def iterEncode(iterator):
    var index := 0
    var buf := []

    return object UTF8Encoder:
        to next(ej):
            # Refill the buffer if it's empty.
            if (buf.size() == 0):
                # Take another char off the top and hack it up.
                def [_, c :Char] := iterator.next(ej)
                def i := c.asInteger()

                if (i < 0x80):
                    # One byte.
                    buf := [i]
                else if (i < 0x800):
                    # Two bytes.
                    buf := [
                        0xc0 | (i >> 6),
                        0x80 | (i & 0x3f),
                    ]
                else if (i < 0x10000):
                    # Three bytes.
                    buf := [
                        0xe0 | (i >> 12),
                        0x80 | ((i >> 6) & 0x3f),
                        0x80 | (i & 0x3f),
                    ]
                else:
                    # Four bytes.
                    buf := [
                        0xf0 | (i >> 18),
                        0x80 | ((i >> 12) & 0x3f),
                        0x80 | ((i >> 6) & 0x3f),
                        0x80 | (i & 0x3f),
                    ]

            def [head] + tail := buf
            def rv := [index, head]
            index += 1
            buf := tail
            return rv

def encode(chars):
    return [b for b in wrapIterable(iterEncode, chars)]

def testIterEncode(assert):
    # One byte.
    assert.equal([0x00], encode("\x00"))
    # Two bytes.
    # XXX é
    assert.equal([0xc3, 0xa9], encode("\u00e9"))
    # Three bytes.
    # XXX ▲
    assert.equal([0xe2, 0x96, 0xb2], encode("\u25b2"))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal([0xf0, 0x9f, 0x8f, 0x94], encode("\U0001f3d4"))


unittest([
    testChr,
    testIterDecode,
    testIterEncode,
])

[
    "UTF8Decode" => decode,
    "UTF8Encode" => encode,
    => chr,
]
