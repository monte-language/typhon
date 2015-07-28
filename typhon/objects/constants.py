# encoding: utf-8
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

from typhon.autohelp import autohelp, method
from typhon.errors import userError
from typhon.objects.root import Object, audited
from typhon.prelude import getGlobalValue


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
class _TrueObject(Object):
    """
    The positive Boolean value.
    """

    def toString(self):
        return u"true"

    def optInterface(self):
        return getGlobalValue(u"Bool")

    @method("Bool", "Bool", _verb="and")
    def _and(self, other):
        return other

    @method("Bool", "Bool")
    def butNot(self, other):
        return not other

    @method("Bool", _verb="not")
    def _not(self):
        return False

    @method("Int", "Bool")
    def op__cmp(self, other):
        return True - other

    @method("Bool", "Bool", _verb="or")
    def _or(self, _):
        return True

    @method("Any", "Any", "Any")
    def pick(self, left, _):
        return left

    @method("Bool", "Bool")
    def xor(self, other):
        return not other

    def isTrue(self):
        return True

TrueObject = _TrueObject()


@autohelp
@audited.DF
class _FalseObject(Object):
    """
    The negative Boolean value.
    """

    def toString(self):
        return u"false"

    def optInterface(self):
        return getGlobalValue(u"Bool")

    @method("Bool", "Bool", _verb="and")
    def _and(self, _):
        return False

    @method("Bool", "Bool")
    def butNot(self, _):
        return False

    @method("Bool", _verb="not")
    def _not(self):
        return True

    @method("Int", "Bool")
    def op__cmp(self, other):
        return False - other

    @method("Bool", "Bool", _verb="or")
    def _or(self, other):
        return other

    @method("Any", "Any", "Any")
    def pick(self, _, right):
        return right

    @method("Bool", "Bool")
    def xor(self, other):
        return other

    def isTrue(self):
        return False

FalseObject = _FalseObject()


def wrapBool(b):
    return TrueObject if b else FalseObject

def unwrapBool(o):
    from typhon.objects.refs import resolution
    b = resolution(o)
    if b is TrueObject:
        return True
    if b is FalseObject:
        return False
    raise userError(u"Not a boolean!")

def isBool(obj):
    from typhon.objects.refs import resolution
    o = resolution(obj)
    return o is TrueObject or o is FalseObject
