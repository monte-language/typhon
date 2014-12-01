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

from typhon.errors import Refused, userError
from typhon.objects.auditors import DeepFrozenStamp
from typhon.objects.root import Object


class _NullObject(Object):

    _immutable_ = True

    stamps = [DeepFrozenStamp]

    def repr(self):
        return "<null>"

    def recv(self, verb, args):
        raise Refused(verb, args)


NullObject = _NullObject()


class BoolObject(Object):

    _immutable_ = True

    stamps = [DeepFrozenStamp]

    def __init__(self, b):
        self._b = b

    def repr(self):
        return "true" if self._b else "false"

    def recv(self, verb, args):

        # and/1
        if verb == u"and" and len(args) == 1:
            return wrapBool(self._b and unwrapBool(args[0]))

        # not/0
        if verb == u"not" and len(args) == 0:
            return wrapBool(not self._b)

        # or/1
        if verb == u"or" and len(args) == 1:
            return wrapBool(self._b or unwrapBool(args[0]))

        # pick/2
        if verb == u"pick" and len(args) == 2:
            return args[0] if self._b else args[1]

        # xor/1
        if verb == u"xor" and len(args) == 1:
            return wrapBool(self._b ^ unwrapBool(args[0]))

        raise Refused(verb, args)

    def isTrue(self):
        return self._b


TrueObject = BoolObject(True)
FalseObject = BoolObject(False)


def wrapBool(b):
    return TrueObject if b else FalseObject


def unwrapBool(o):
    from typhon.objects.refs import resolution
    b = resolution(o)
    if isinstance(b, BoolObject):
        return b.isTrue()
    raise userError(u"Not a boolean!")
