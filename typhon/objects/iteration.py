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
from typhon.objects.auditors import deepFrozenStamp
from typhon.objects.collections import unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import runnable
from typhon.objects.user import ScriptObject
from typhon.smallcaps.machine import SmallCaps


RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)


def getLocation(code):
    return code.disassemble()


loopDriver = JitDriver(greens=["code"],
                       reds=["consumer", "ejector", "iterator", "machine",
                             "env"],
                       virtualizables=["env"],
                       get_printable_location=getLocation)


def loopJIT(consumer, ejector, iterator):
    if isinstance(consumer, ScriptObject):
        # Just copy and inline here.
        code = consumer.codeScript.methods.get(RUN_2, None)
        if code is not None:
            machine = SmallCaps(code, consumer.closure, consumer.globals)
            # JIT merge point.
            loopDriver.jit_merge_point(code=code, consumer=consumer,
                                       ejector=ejector, iterator=iterator,
                                       machine=machine, env=machine.env)
            values = unwrapList(iterator.call(u"next", [ejector]))
            # Push the arguments onto the stack, backwards.
            values.reverse()
            for arg in values:
                machine.push(arg)
                machine.push(NullObject)
            # print "--- Entering JIT loop", RUN_2
            machine.run()
            return

    # Relatively slow path here. This should be exceedingly rare, actually!
    values = iterator.call(u"next", [ejector])
    consumer.call(u"run", unwrapList(values))


@runnable(RUN_2, [deepFrozenStamp])
def loop(args):
    iterable = args[0]
    consumer = args[1]
    iterator = iterable.call(u"_makeIterator", [])

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
