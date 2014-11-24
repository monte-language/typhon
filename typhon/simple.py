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

from typhon.errors import Ejecting, Refused, UserException
from typhon.objects.equality import Equalizer
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject, wrapBool
from typhon.objects.ejectors import Ejector, throw
from typhon.objects.root import Object


class accumulateList(Object):

    def repr(self):
        return "<accumulateList>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 2:
            rv = []

            iterable = args[0]
            mapper = args[1]
            iterator = iterable.recv(u"_makeIterator", [])

            with Ejector() as ej:
                while True:
                    try:
                        values = iterator.recv(u"next", [ej])
                        rv.append(mapper.recv(u"run", unwrapList(values)))
                    except Ejecting as e:
                        if e.ejector == ej:
                            break

            return ConstList(rv)
        raise Refused(verb, args)


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstList(args)
        raise Refused(verb, args)


class loop(Object):

    def repr(self):
        return "<loop>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 2:
            iterable = args[0]
            consumer = args[1]
            iterator = iterable.recv(u"_makeIterator", [])

            with Ejector() as ej:
                while True:
                    try:
                        values = iterator.recv(u"next", [ej])
                        consumer.recv(u"run", unwrapList(values)[:2])
                    except Ejecting as e:
                        if e.ejector == ej:
                            break

            return NullObject
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
        u"__accumulateList": accumulateList(),
        u"__equalizer": Equalizer(),
        u"__loop": loop(),
        u"__makeList": makeList(),
        u"false": wrapBool(False),
        u"null": NullObject,
        u"throw": Throw(),
        u"true": wrapBool(True),
    }
