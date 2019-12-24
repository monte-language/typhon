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

from typhon.atoms import getAtom
from typhon.errors import Ejecting
from typhon.nano.interp import InterpObject
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections.lists import unwrapList
from typhon.objects.collections.maps import EMPTY_MAP
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import runnable


RUN_2 = getAtom(u"run", 2)


def getLocation(method, displayName):
    return displayName


loopDriver = JitDriver(greens=["method", "displayName"],
                       reds=["consumer", "ejector", "iterator"],
                       get_printable_location=getLocation)


def slowLoop(iterable, consumer):
    iterator = iterable.call(u"_makeIterator", [])

    with Ejector(u"slowLoop") as ej:
        while True:
            try:
                values = iterator.call(u"next", [ej])
                consumer.call(u"run", unwrapList(values))
            except Ejecting as e:
                if e.ejector is ej:
                    break
                else:
                    raise

    return NullObject


@runnable(RUN_2, [deepFrozenStamp])
def loop(iterable, consumer):
    """
    Perform an iterative loop.
    """

    # If the consumer is *not* an InterpObject, then damn them to the slow
    # path. In order for the consumer to not be InterpObject, though, the
    # compiler and optimizer must have decided that an object could be
    # directly passed to _loop(), which is currently impossible to do without
    # manual effort. It's really not a common pathway at all.
    if not isinstance(consumer, InterpObject):
        return slowLoop(iterable, consumer)
    displayName = consumer.getDisplayName().encode("utf-8")

    # Rarer path: If the consumer doesn't actually have a method for run/2,
    # then they're not going to be JIT'd. Again, the compiler and optimizer
    # won't ever do this to us; it has to be intentional.
    method = consumer.getMethod(RUN_2)
    if method is None:
        return slowLoop(iterable, consumer)

    iterator = iterable.call(u"_makeIterator", [])

    # XXX We want to use a with-statement here, but we cannot because of
    # something weird about the merge point.
    ej = Ejector(u"loop")
    try:
        while True:
            # JIT merge point.
            loopDriver.jit_merge_point(method=method, displayName=displayName,
                    consumer=consumer, ejector=ej, iterator=iterator)
            values = unwrapList(iterator.call(u"next", [ej]))
            consumer.runMethod(method, values, EMPTY_MAP)
    except Ejecting as e:
        if e.ejector is not ej:
            raise
    finally:
        ej.disable()

    return NullObject
