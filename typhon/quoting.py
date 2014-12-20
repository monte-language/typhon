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

from rpython.rlib.jit import elidable, unroll_safe
from rpython.rlib.rstring import UnicodeBuilder
from rpython.rlib.unicodedata import unicodedb_6_2_0 as unicodedb


escapes = {
    # Not technically an escape, but special-cased.
    u' ': u" ",
    u'\\': u"\\\\",
    u'\b': u"\\b",
    u'\f': u"\\f",
    u'\n': u"\\n",
    u'\r': u"\\r",
    u'\t': u"\\t",
}


@elidable
def ljust(s, width, fill):
    if len(s) < width:
        return fill * (width - len(s)) + s
    return s


@elidable
def hex(i, width):
    s = u"%x" % i
    return ljust(s, width, u'0')


@elidable
def quoteCommon(c):
    """
    Apply common quotations to an element of a character or string.
    """

    if c in escapes:
        return escapes[c]

    x = ord(c)
    category = unicodedb.category(x)
    if category[0] in "CZ":
        # Calculate an escape code.
        if x < 0x100:
            return u"\\x%s" % hex(x, 2)
        elif x < 0x10000:
            return u"\\u%s" % hex(x, 4)
        else:
            return u"\\U%s" % hex(x, 8)

    return c


@elidable
def quoteChar(c):
    """
    Quote a single character.
    """

    if c == u"'":
        return u"'\\''"
    return u"'%s'" % quoteCommon(c)


@elidable
@unroll_safe
def quoteStr(s):
    """
    Quote an entire string.
    """

    # The length hint is the length of the incoming string, plus two for the
    # quote marks. This will never overshoot, and in the common case, will not
    # undershoot either.
    ub = UnicodeBuilder(len(s) + 2)

    ub.append(u'"')
    for c in s:
        if c == u'"':
            ub.append(u'\\"')
        else:
            ub.append(quoteCommon(c))
    ub.append(u'"')
    return ub.build()
