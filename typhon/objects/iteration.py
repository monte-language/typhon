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

from rpython.rlib.jit import JitDriver, promote

from typhon.atoms import getAtom
from typhon.errors import Ejecting
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections import EMPTY_MAP, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import runnable
from typhon.objects.user import BusyObject, ScriptObject
from typhon.smallcaps.machine import SmallCaps


RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)


def getLocation(code):
    return code.disassemble()


loopDriver = JitDriver(greens=["code"],
                       reds=["consumer", "ejector", "iterator"],
                       get_printable_location=getLocation)


def slowLoop(iterable, consumer):
    iterator = iterable.call(u"_makeIterator", [])

    with Ejector() as ej:
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
def loop(args):
    """
    Perform an iterative loop.
    """

    iterable = args[0]
    consumer = args[1]

    # If the consumer is *not* a ScriptObject, then damn them to the slow
    # path. In order for the consumer to not be ScriptObject, though, the
    # compiler and optimizer must have decided that an object could be
    # directly passed to __loop(), which is currently impossible to do without
    # manual effort. It's really not a common pathway at all.
    if not isinstance(consumer, ScriptObject):
        return slowLoop(iterable, consumer)

    # Rarer path: If the consumer doesn't actually have RUN_2, then they're
    # not going to be JIT'd. Again, the compiler and optimizer won't ever do
    # this to us; it has to be intentional.
    code = consumer.codeScript.methods.get(RUN_2, None)
    if code is None:
        return slowLoop(iterable, consumer)

    iterator = iterable.call(u"_makeIterator", [])

    ej = Ejector()
    try:
        while True:
            # JIT merge point.
            loopDriver.jit_merge_point(code=code, consumer=consumer,
                                       ejector=ej, iterator=iterator)
            globals = promote(consumer.globals)
            if isinstance(consumer, BusyObject):
                machine = SmallCaps(code, consumer.closure, globals)
            else:
                machine = SmallCaps(code, None, globals)
            values = unwrapList(iterator.call(u"next", [ej]))
            # Push the arguments onto the stack, backwards.
            values.reverse()
            for arg in values:
                machine.push(arg)
                machine.push(NullObject)
            machine.push(EMPTY_MAP)
            machine.run()
    except Ejecting as e:
        if e.ejector is not ej:
            raise
    finally:
        ej.disable()

    return NullObject
