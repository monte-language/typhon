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
from typhon.errors import Ejecting, Refused
from typhon.objects import (Object, BoolObject, ConstListObject,
                            EjectorObject, EqualizerObject, FalseObject,
                            NullObject, TrueObject)


class accumulateList(Object):

    def repr(self):
        return "<accumulateList>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 2:
            rv = []

            iterable = args[0]
            mapper = args[1]
            iterator = iterable.recv(u"_makeIterator", [])

            with EjectorObject() as ej:
                while True:
                    try:
                        values = iterator.recv(u"next", [ej])
                        if not isinstance(values, ConstListObject):
                            raise RuntimeError
                        rv.append(mapper.recv(u"run", values._l))
                    except Ejecting as e:
                        if e.ejector == ej:
                            break

            return ConstListObject(rv)
        raise Refused(verb, args)


class makeList(Object):

    def recv(self, verb, args):
        if verb == u"run":
            return ConstListObject(args)
        raise Refused(verb, args)


class loop(Object):

    def repr(self):
        return "<loop>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 2:
            iterable = args[0]
            consumer = args[1]
            iterator = iterable.recv(u"_makeIterator", [])

            with EjectorObject() as ej:
                while True:
                    try:
                        values = iterator.recv(u"next", [ej])
                        if not isinstance(values, ConstListObject):
                            raise RuntimeError
                        consumer.recv(u"run", values._l[:2])
                    except Ejecting as e:
                        if e.ejector == ej:
                            break

            return NullObject
        raise Refused(verb, args)


class validateFor(Object):

    def repr(self):
        return "<validateFor>"

    def recv(self, verb, args):
        if verb == u"run" and len(args) == 1:
            flag = args[0]
            if isinstance(flag, BoolObject) and flag.isTrue():
                return NullObject
            raise RuntimeError("Failed to validate for-loop!")
        raise Refused(verb, args)


def simpleScope():
    return {
        u"__accumulateList": accumulateList(),
        u"__equalizer": EqualizerObject(),
        u"__loop": loop(),
        u"__makeList": makeList(),
        u"__validateFor": validateFor(),
        u"false": FalseObject,
        u"null": NullObject,
        u"true": TrueObject,
    }
