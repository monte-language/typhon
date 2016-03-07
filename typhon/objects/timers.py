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

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.constants import NullObject
from typhon.objects.data import DoubleObject, promoteToDouble
from typhon.objects.refs import LocalResolver, makePromise
from typhon.objects.root import Object
from typhon.vats import currentVat


FROMNOW_1 = getAtom(u"fromNow", 1)
RESOLVE_1 = getAtom(u"resolve", 1)
RUN_1 = getAtom(u"run", 1)
SENDTIMESTAMP_1 = getAtom(u"sendTimestamp", 1)
UNSAFENOW_0 = getAtom(u"unsafeNow", 0)


def resolveTimer(uv_timer):
    vat, resolver = ruv.unstashTimer(uv_timer)
    assert isinstance(resolver, LocalResolver)
    resolver.resolve(NullObject)


@autohelp
class Timer(Object):
    """
    An unsafe nondeterministic clock.

    This object provides a useful collection of time-related methods:
     * `fromNow(delay :Double)`: Produce a promise which will fully resolve
       after at least `delay` seconds have elapsed in the runtime.
     * `sendTimestamp(callable)`: Send a `Double` representing the runtime's
       clock to `callable`.

    There is extremely unsafe functionality as well:
     * `unsafeNow()`: The current system time.

    Use with caution.
    """

    def recv(self, atom, args):
        from typhon.objects.collections.maps import EMPTY_MAP
        if atom is UNSAFENOW_0:
            return DoubleObject(time.time())

        if atom is FROMNOW_1:
            duration = promoteToDouble(args[0])
            p, r = makePromise()
            vat = currentVat.get()
            uv_timer = ruv.alloc_timer(vat.uv_loop)
            # Stash the resolver.
            ruv.stashTimer(uv_timer, (vat, r))
            # repeat of 0 means "don't repeat"
            ruv.timerStart(uv_timer, resolveTimer, int(duration * 1000), 0)
            assert ruv.isActive(uv_timer), "Timer isn't active!?"
            return p

        if atom is SENDTIMESTAMP_1:
            now = time.time()
            vat = currentVat.get()
            return vat.send(args[0], RUN_1, [DoubleObject(now)], EMPTY_MAP)

        raise Refused(self, atom, args)
