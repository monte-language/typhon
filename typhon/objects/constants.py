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

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused, userError
from typhon.objects.root import Object, audited
from typhon.prelude import getGlobalValue


AND_1 = getAtom(u"and", 1)
BUTNOT_1 = getAtom(u"butNot", 1)
NOT_0 = getAtom(u"not", 0)
OP__CMP_1 = getAtom(u"op__cmp", 1)
OR_1 = getAtom(u"or", 1)
PICK_2 = getAtom(u"pick", 2)
XOR_1 = getAtom(u"xor", 1)


@autohelp
@audited.DF
class _NullObject(Object):
    """
    The null object.
    """

    def toString(self):
        return u"null"

    def optInterface(self):
        return getGlobalValue(u"Void")


NullObject = _NullObject()


@autohelp
@audited.DF
class BoolObject(Object):
    """
    A Boolean value.
    """

    _immutable_fields_ = "_b",

    def __init__(self, b):
        self._b = b

    def toString(self):
        return u"true" if self._b else u"false"

    def optInterface(self):
        return getGlobalValue(u"Bool")

    def recv(self, atom, args):
        # and/1
        if atom is AND_1:
            return wrapBool(self._b and unwrapBool(args[0]))

        # butNot/1
        if atom is BUTNOT_1:
            return wrapBool(self._b and not unwrapBool(args[0]))

        # not/0
        if atom is NOT_0:
            return wrapBool(not self._b)

        # op__cmp/1
        if atom is OP__CMP_1:
            from typhon.objects.data import IntObject
            return IntObject(self._b - unwrapBool(args[0]))

        # or/1
        if atom is OR_1:
            return wrapBool(self._b or unwrapBool(args[0]))

        # pick/2
        if atom is PICK_2:
            return args[0] if self._b else args[1]

        # xor/1
        if atom is XOR_1:
            return wrapBool(self._b ^ unwrapBool(args[0]))

        raise Refused(self, atom, args)

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
