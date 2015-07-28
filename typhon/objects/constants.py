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

from typhon.autohelp import autohelp
from typhon.errors import WrongType
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.root import Object, method
from typhon.specs import Any, Bool, Int


@autohelp
class _NullObject(Object):
    """
    The null object.
    """

    _immutable_ = True

    stamps = [deepFrozenStamp]

    def toString(self):
        return u"null"


NullObject = _NullObject()


@autohelp
class BoolObject(Object):
    """
    A Boolean value.
    """

    _immutable_ = True

    stamps = [deepFrozenStamp]

    def __init__(self, b):
        self._b = b

    def toString(self):
        return u"true" if self._b else u"false"

    @method([Bool], Bool, verb=u"and")
    def and_(self, b):
        """
        Logical conjunction; p ∧ q.
        """

        assert isinstance(self, BoolObject)
        return self._b and b

    @method([Bool], Bool)
    def butNot(self, b):
        """
        Material nonimplication; p ↛ q.
        """

        assert isinstance(self, BoolObject)
        return self._b and not b

    @method([], Bool, verb=u"not")
    def not_(self):
        """
        Negation; ¬p.
        """

        assert isinstance(self, BoolObject)
        return not self._b

    @method([Bool], Int)
    def op__cmp(self, other):
        """
        Logical bicondition; p ↔ q.
        """

        assert isinstance(self, BoolObject)
        return self._b - other

    @method([Bool], Bool, verb=u"or")
    def or_(self, b):
        """
        Logical disjunction; p ∨ q.
        """

        assert isinstance(self, BoolObject)
        return self._b or b

    @method([Any, Any], Any)
    def pick(self, first, second):
        """
        Choose between two options based on this object's truth value.
        """

        assert isinstance(self, BoolObject)
        return first if self._b else second

    @method([Bool], Bool)
    def xor(self, b):
        """
        Exclusive disjunction; p ↮ q.
        """

        assert isinstance(self, BoolObject)
        return self._b ^ b

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
    raise WrongType(u"Not a boolean!")
