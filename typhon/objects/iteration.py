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

from rpython.rlib.jit import JitDriver

from typhon.errors import Ejecting, Refused
from typhon.objects.collections import ConstList, ConstMap, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import runnable
from typhon.objects.user import ScriptObject


def getLocation(map):
    return map.repr()


accumDriver = JitDriver(greens=["mapperMap"],
                        reds=["mapper", "ejector", "iterator", "accumulator",
                              "skipper"],
                        get_printable_location=getLocation)


def accumJIT(mapper, ejector, iterator, accumulator, skipper):
    if isinstance(mapper, ScriptObject):
        accumDriver.jit_merge_point(mapperMap=mapper._map, mapper=mapper,
                                    ejector=ejector, iterator=iterator,
                                    accumulator=accumulator, skipper=skipper)
    values = iterator.recv(u"next", [ejector])
    args = unwrapList(values)
    args.append(skipper)
    accumulator.append(mapper.recv(u"run", args))


@runnable
def accumulateList(args):
    if len(args) == 2:
        rv = []

        iterable = args[0]
        mapper = args[1]
        iterator = iterable.recv(u"_makeIterator", [])

        with Ejector() as ej:
            while True:
                with Ejector() as skip:
                    try:
                        accumJIT(mapper, ej, iterator, rv, skip)
                    except Ejecting as e:
                        if e.ejector is ej:
                            break
                        if e.ejector is skip:
                            continue
                        raise

        return ConstList(rv)
    raise Refused(u"run", args)


@runnable
def accumulateMap(args):
    rv = accumulateList().recv(u"run", args)
    return ConstMap.fromPairs(rv)


loopDriver = JitDriver(greens=["consumerMap"],
                       reds=["consumer", "ejector", "iterator"],
                       get_printable_location=getLocation)


def loopJIT(consumer, ejector, iterator):
    if isinstance(consumer, ScriptObject):
        loopDriver.jit_merge_point(consumerMap=consumer._map,
                                   consumer=consumer, ejector=ejector,
                                   iterator=iterator)
    values = iterator.recv(u"next", [ejector])
    # XXX wait, what's this slice do again?
    consumer.recv(u"run", unwrapList(values))


@runnable
def loop(args):
    if len(args) == 2:
        iterable = args[0]
        consumer = args[1]
        iterator = iterable.recv(u"_makeIterator", [])

        with Ejector() as ej:
            while True:
                try:
                    loopJIT(consumer, ej, iterator)
                except Ejecting as e:
                    if e.ejector is ej:
                        break
                    else:
                        raise

        return NullObject
    raise Refused(u"run", args)
