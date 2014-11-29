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

from typhon.errors import Refused, UserException
from typhon.objects.equality import Equalizer
from typhon.objects.collections import ConstList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.ejectors import throw
from typhon.objects.iteration import accumulateList, loop
from typhon.objects.root import Object


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstList(args)
        raise Refused(verb, args)


class Throw(Object):

    def repr(self):
        return "<throw>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 1:
            raise UserException(args[0])
        if verb == u"eject" and len(args) == 2:
            return throw(args[0], args[1])
        raise Refused(verb, args)


def simpleScope():
    return {
        u"null": NullObject,

        u"false": wrapBool(False),
        u"true": wrapBool(True),

        u"__accumulateList": accumulateList(),
        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": makeList(),
        u"throw": Throw(),
    }
