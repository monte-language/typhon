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

from rpython.rlib.rstring import UnicodeBuilder, split
from rpython.rlib.unicodedata import unicodedb_6_2_0 as unicodedb

from typhon.errors import Refused
from typhon.objects import IntObject
from typhon.objects.auditors import DeepFrozenStamp
from typhon.objects.constants import wrapBool
from typhon.objects.root import Object


class CharObject(Object):

    _immutable_fields_ = "stamps", "_c"

    stamps = [DeepFrozenStamp]

    def __init__(self, c):
        # RPython needs to be reminded that, no matter what, we are always
        # using a single character here.
        self._c = c[0]

    def repr(self):
        return "'%s'" % (self._c.encode("utf-8"))

    def recv(self, verb, args):
        if verb == u"add" and len(args) == 1:
            other = args[0]
            if isinstance(other, IntObject):
                return self.withOffset(other.getInt())

        if verb == u"asInteger" and len(args) == 0:
            return IntObject(ord(self._c))

        if verb == u"asString" and len(args) == 0:
            return StrObject(unicode(self._c))

        if verb == u"getCategory" and len(args) == 0:
            return StrObject(unicode(unicodedb.category(ord(self._c))))

        if verb == u"max" and len(args) == 1:
            other = args[0]
            if isinstance(other, CharObject):
                return self if self._c > other._c else other

        if verb == u"min" and len(args) == 1:
            other = args[0]
            if isinstance(other, CharObject):
                return self if self._c < other._c else other

        if verb == u"next" and len(args) == 0:
            return self.withOffset(1)

        if verb == u"previous" and len(args) == 0:
            return self.withOffset(-1)

        if verb == u"subtract" and len(args) == 1:
            other = args[0]
            if isinstance(other, IntObject):
                return self.withOffset(-other.getInt())

        raise Refused(verb, args)

    def withOffset(self, offset):
        return CharObject(unichr(ord(self._c) + offset))


class strIterator(Object):

    _immutable_fields_ = "s",

    _index = 0

    def __init__(self, s):
        self.s = s

    def recv(self, verb, args):
        if verb == u"next" and len(args) == 1:
            if self._index < len(self.s):
                from typhon.objects.collections import ConstList
                rv = [IntObject(self._index), CharObject(self.s[self._index])]
                self._index += 1
                return ConstList(rv)
            else:
                ej = args[0]
                ej.recv(u"run", [StrObject(u"Iterator exhausted")])

        raise Refused(verb, args)


class StrObject(Object):

    _immutable_fields_ = "stamps[*]", "_s"

    stamps = [DeepFrozenStamp]

    def __init__(self, s):
        self._s = s

    def repr(self):
        return '"%s"' % self._s.encode("utf-8")

    def recv(self, verb, args):
        if verb == u"add" and len(args) == 1:
            other = args[0]
            if isinstance(other, StrObject):
                return StrObject(self._s + other._s)
            if isinstance(other, CharObject):
                return StrObject(self._s + unicode(other._c))

        if verb == u"contains" and len(args) == 1:
            needle = args[0]
            if isinstance(needle, CharObject):
                return wrapBool(needle._c in self._s)
            if isinstance(needle, StrObject):
                return wrapBool(needle._s in self._s)

        if verb == u"get" and len(args) == 1:
            index = args[0]
            if isinstance(index, IntObject):
                return CharObject(self._s[index._i])

        if verb == u"join" and len(args) == 1:
            l = args[0]
            from typhon.objects.collections import ConstList, unwrapList
            if isinstance(l, ConstList):
                strs = []
                for s in unwrapList(l):
                    assert isinstance(s, StrObject)
                    strs.append(s._s)
                return StrObject(self._s.join(strs))

        if verb == u"multiply" and len(args) == 1:
            amount = args[0]
            if isinstance(amount, IntObject):
                return StrObject(self._s * amount._i)

        if verb == u"size" and len(args) == 0:
            return IntObject(len(self._s))

        if verb == u"slice" and len(args) == 1:
            index = args[0]
            if isinstance(index, IntObject):
                start = index._i
                if start >= 0:
                    return StrObject(self._s[start:])

        if verb == u"split" and len(args) >= 1:
            splitter = args[0]
            if isinstance(splitter, StrObject):
                from typhon.objects.collections import ConstList
                if len(args) == 2:
                    splits = args[1]
                    if isinstance(splits, IntObject):
                        strings = [StrObject(s)
                                for s in split(self._s, splitter._s,
                                    splits.getInt())]
                        return ConstList(strings)
                strings = [StrObject(s) for s in split(self._s, splitter._s)]
                return ConstList(strings)

        if verb == u"toLowerCase" and len(args) == 0:
            # Use current size as a size hint. In the best case, characters
            # are one-to-one; in the next-best case, we overestimate and end
            # up with a couple bytes of slop.
            ub = UnicodeBuilder(len(self._s))
            for char in self._s:
                ub.append(unichr(unicodedb.tolower(ord(char))))
            return StrObject(ub.build())

        if verb == u"toUpperCase" and len(args) == 0:
            ub = UnicodeBuilder(len(self._s))
            for char in self._s:
                ub.append(unichr(unicodedb.toupper(ord(char))))
            return StrObject(ub.build())

        if verb == u"_makeIterator" and len(args) == 0:
            return strIterator(self._s)

        raise Refused(verb, args)
