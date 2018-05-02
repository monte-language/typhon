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

import time

from rpython.rlib.rarithmetic import intmask

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.futures import IOEvent
from typhon.objects.data import DoubleObject
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object
from typhon.vats import currentVat


FROMNOW_1 = getAtom(u"fromNow", 1)
RESOLVE_1 = getAtom(u"resolve", 1)
RUN_0 = getAtom(u"run", 0)
RUN_1 = getAtom(u"run", 1)
SENDTIMESTAMP_1 = getAtom(u"sendTimestamp", 1)
UNSAFENOW_0 = getAtom(u"unsafeNow", 0)


def resolveTimer(uv_timer):
    vat, (resolver, then) = ruv.unstashTimer(uv_timer)
    now = ruv.now(vat.uv_loop)
    assert isinstance(resolver, LocalResolver)
    # Convert from ms to s.
    d = intmask(now - then) / 1000.0
    resolver.resolve(DoubleObject(d))


@autohelp
class TimeMeasurer(Object):
    """
    This is the End of Time.
    """

    def __init__(self, f):
        self.f = f

    @method("List")
    def run(self):
        before = time.time()
        result = self.f.call(u"run", [])
        after = time.time()
        elapsed = max(after - before, 0.0)
        return [result, DoubleObject(elapsed)]


@autohelp
class Timer(Object):
    """
    An unsafe nondeterministic clock.

    This object provides a useful collection of time-related methods:
     * `fromNow(delay :Double)`: Produce a promise which will fully resolve
       after at least `delay` seconds have elapsed in the runtime. The promise
       will resolve to a `Double` representing the precise amount of time
       elapsed, in seconds.
     * `sendTimestamp(callable)`: Send a `Double` representing the runtime's
       clock to `callable`.

    There is extremely unsafe functionality as well:
     * `unsafeNow()`: The current system time.

    Use with caution.
    """

    @method("Any", "Any")
    def measureTimeTaken(self, f):
        """
        Like m`f<-()`, but returns a promise for a pair
        `[result, timeTaken :Double]` in seconds.
        """

        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        return vat.send(TimeMeasurer(f), RUN_0, [], EMPTY_MAP)

    @method("Double")
    def unsafeNow(self):
        return time.time()

    @method("Any", "Double")
    def fromNow(self, duration):
        p, r = makePromise()
        vat = currentVat.get()
        vat.enqueueEvent(TimerIOEvent(vat, r, duration))
        return p

    @method("Any", "Any")
    def sendTimestamp(self, obj):
        from typhon.objects.collections.maps import EMPTY_MAP
        vat = currentVat.get()
        now = intmask(ruv.now(vat.uv_loop)) / 1000.0
        return vat.send(obj, RUN_1, [DoubleObject(now)], EMPTY_MAP)


class TimerIOEvent(IOEvent):
    def __init__(self, vat, r, duration):
        self.vat = vat
        self.r = r
        self.duration = duration
        self.uv_timer = ruv.alloc_timer(vat.uv_loop)
        self.now = ruv.now(vat.uv_loop)
        # Stash the resolver.
        ruv.stashTimer(self.uv_timer, (vat, (r, self.now)))

    def run(self):
        delay = ruv.now(self.vat.uv_loop) - self.now
        # repeat of 0 means "don't repeat"
        ruv.timerStart(self.uv_timer, resolveTimer,
                       max(0, int(self.duration * 1000) - delay), 0)
