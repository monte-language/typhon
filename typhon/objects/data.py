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

from typhon.errors import Refused
from typhon.objects import IntObject, StrObject
from typhon.objects.auditors import DeepFrozenStamp
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
