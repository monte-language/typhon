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
from typhon.objects.collections import unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.ejectors import Ejector
from typhon.objects.root import runnable
from typhon.objects.user import ScriptObject, runBlock


RUN_2 = getAtom(u"run", 2)
RUN_3 = getAtom(u"run", 3)


def getLocation(node, patterns):
    return node.repr()


loopDriver = JitDriver(greens=["node", "patterns"],
                       reds=["consumer", "ejector", "iterator", "env"],
                       virtualizables=["env"],
                       get_printable_location=getLocation)


def loopJIT(consumer, ejector, iterator):
    if isinstance(consumer, ScriptObject):
        patterns, block, frameSize = consumer._map.lookup(RUN_2)
        if patterns is not None and block is not None:
            env = consumer.env(frameSize)
            loopDriver.jit_merge_point(node=block, patterns=patterns,
                                       consumer=consumer, ejector=ejector,
                                       iterator=iterator, env=env)
            values = iterator.call(u"next", [ejector])
            # The patterns here cannot fail to unify. We guarantee it.
            runBlock(patterns, block, unwrapList(values), None, env)
            return

    # Relatively slow path here. This should be exceedingly rare, actually!
    values = iterator.call(u"next", [ejector])
    consumer.call(u"run", unwrapList(values))


@runnable(RUN_2)
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
