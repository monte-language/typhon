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


def chr(i :Int) :Char as DeepFrozen:
    return '\x00' + i

def testChr(assert):
    assert.equal('\x00', chr(0x00))
    assert.equal('\n', chr(0x0a))
    # XXX assert.equal('▲', chr(0x25b2))
    assert.equal('\u25b2', chr(0x25b2))

unittest([testChr])


def decodeCore(var bs :Bytes, ej) as DeepFrozen:
    def iterator := bs._makeIterator()
    var offset :Int := 0
    var rv :Str := ""
    while (true):
        if (offset >= bs.size()):
            # End of input.
            break

        def b := bs[offset]
        if ((b & 0x80) == 0x00):
            # One byte.
            rv with= (chr(b))
            offset += 1
        else if ((b & 0xe0) == 0xc0):
            # Two bytes.
            if (bs.size() - offset < 2):
                break

            var c := (b & 0x1f) << 6
            c |= bs[offset + 1] & 0x3f
            rv with= (chr(c))
            offset += 2
        else if ((b & 0xf0) == 0xe0):
            # Three bytes.
            if (bs.size() - offset < 3):
                break

            var c := (b & 0x0f) << 12
            c |= (bs[offset + 1] & 0x3f) << 6
            c |= bs[offset + 2] & 0x3f
            rv with= (chr(c))
            offset += 3
        else if ((b & 0xf7) == 0xf0):
            # Four bytes.
            if (bs.size() - offset < 4):
                break

            var c := (b & 0x07) << 18
            c |= (bs[offset + 1] & 0x3f) << 12
            c |= (bs[offset + 2] & 0x3f) << 6
            c |= bs[offset + 3] & 0x3f
            rv with= (chr(c))
            offset += 4
        else:
            # Invalid sequence. Move forward and try again.
            rv with= ('\ufffd')
            offset += 1
    return [rv, bs.slice(offset)]

def testDecodeCore(assert):
    # One byte.
    assert.equal(["\x00", b``], decodeCore(b`$\x00`, null))
    assert.equal(["\n", b``], decodeCore(b`$\x0a`, null))
    # One byte as leftover.
    assert.equal(["", b`$\xc3`], decodeCore(b`$\xc3`, null))
    # Two bytes.
    # XXX é
    assert.equal(["\u00e9", b``], decodeCore(b`$\xc3$\xa9`, null))
    # Three bytes.
    # XXX ▲
    assert.equal(["\u25b2", b``], decodeCore(b`$\xe2$\x96$\xb2`, null))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal(["\U0001f3d4", b``],
                 decodeCore(b`$\xf0$\x9f$\x8f$\x94`, null))

unittest([testDecodeCore])


def encodeCore(c :Char) :Bytes as DeepFrozen:
    return _makeBytes.fromInts(switch (c.asInteger()) {
        # One byte.
        match i ? (i < 0x80) {[i]}
        # Two bytes.
        match i ? (i < 0x800) {[0xc0 | (i >> 6), 0x80 | (i & 0x3f)]}
        # Three bytes.
        match i ? (i < 0x10000) {
            [0xe0 | (i >> 12), 0x80 | ((i >> 6) & 0x3f), 0x80 | (i & 0x3f)]
        }
        # Four bytes.
        match i {
            [
                0xf0 | (i >> 18),
                0x80 | ((i >> 12) & 0x3f),
                0x80 | ((i >> 6) & 0x3f),
                0x80 | (i & 0x3f), ]
        }
    })

def testEncodeCore(assert):
    # One byte.
    assert.equal(b`$\x00`, encodeCore('\x00'))
    # Two bytes.
    # XXX é
    assert.equal(b`$\xc3$\xa9`, encodeCore('\u00e9'))
    # Three bytes.
    # XXX ▲
    assert.equal(b`$\xe2$\x96$\xb2`, encodeCore('\u25b2'))
    # Four bytes.
    # XXX this codepoint is generally not in any font
    assert.equal(b`$\xf0$\x9f$\x8f$\x94`, encodeCore('\U0001f3d4'))

unittest([testEncodeCore])


# The codec itself.

object UTF8 as DeepFrozen:
    to decode(specimen, ej) :Str:
        def bs :Bytes exit ej := specimen
        def [s, remainder] exit ej := decodeCore(bs, ej)
        if (remainder.size() != 0):
            throw.eject(ej, [remainder, "was not empty"])
        return s

    to decodeExtras(specimen, ej):
        def bs :Bytes exit ej := specimen
        return decodeCore(bs, ej)

    to encode(specimen, ej) :Bytes:
        def s :Str exit ej := specimen
        var rv :Bytes := b``
        for c in s:
            rv += encodeCore(c)
        return rv

def testUTF8Decode(assert):
    assert.ejects(fn ej {def via (UTF8.decode) x exit ej := b`$\xc3`})
    assert.doesNotEject(
        fn ej {def via (UTF8.decode) x exit ej := b`$\xc3$\xa9`})

def testUTF8Encode(assert):
    assert.ejects(fn ej {def via (UTF8.encode) x exit ej := 42})
    assert.doesNotEject(fn ej {def via (UTF8.encode) x exit ej := "yes"})

unittest([
    testUTF8Decode,
    testUTF8Encode,
])

# def encodeBench():
#     def via (UTF8.encode) xs := "This is a test of the UTF-8 encoder… "
#     def via (UTF8.encode) ys := "¥ · £ · € · $ · ¢ · ₡ · ₢ · ₣ · ₤ · ₥ · ₦ · ₧ · ₨ · ₩ · ₪ · ₫ · ₭ · ₮ · ₯ · ₹"
#     return xs + ys

# bench(encodeBench, "UTF-8 encoding")


# def decodeBench():
#     def via (UTF8.decode) xs := b`This is a test of the UTF-8 encoder$\xe2$\x80$\xa6 `
#     def via (UTF8.decode) ys := _makeBytes.fromInts([194, 165, 32, 194, 183,
#                                                      32, 194, 163, 32, 194,
#                                                      183, 32, 226, 130, 172,
#                                                      32, 194, 183, 32, 36, 32,
#                                                      194, 183, 32, 194, 162,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 161, 32, 194, 183,
#                                                      32, 226, 130, 162, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      163, 32, 194, 183, 32,
#                                                      226, 130, 164, 32, 194,
#                                                      183, 32, 226, 130, 165,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 166, 32, 194, 183,
#                                                      32, 226, 130, 167, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      168, 32, 194, 183, 32,
#                                                      226, 130, 169, 32, 194,
#                                                      183, 32, 226, 130, 170,
#                                                      32, 194, 183, 32, 226,
#                                                      130, 171, 32, 194, 183,
#                                                      32, 226, 130, 173, 32,
#                                                      194, 183, 32, 226, 130,
#                                                      174, 32, 194, 183, 32,
#                                                      226, 130, 175, 32, 194,
#                                                      183, 32, 226, 130, 185])
#     return xs + ys

# bench(decodeBench, "UTF-8 decoding")


[
    => UTF8,
]
