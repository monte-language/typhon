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

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import Refused
from typhon.objects.data import DoubleObject, promoteToDouble
from typhon.objects.refs import makePromise
from typhon.objects.root import Object
from typhon.vats import currentVat


FROMNOW_1 = getAtom(u"fromNow", 1)
RESOLVE_1 = getAtom(u"resolve", 1)
TRIAL_1 = getAtom(u"trial", 1)


@autohelp
class Timer(Object):
    """
    An unsafe nondeterministic clock.

    Use with caution.
    """

    def recv(self, atom, args):
        from typhon.objects.collections import EMPTY_MAP
        if atom is FROMNOW_1:
            duration = promoteToDouble(args[0])
            p, r = makePromise()
            vat = currentVat.get()
            vat._reactor.addTimer(duration, r)
            return p

        if atom is TRIAL_1:
            obj = args[0]
            then = time.time()
            obj.call(u"run", [])
            now = time.time()

            # We can't give the value up immediately, due to determinism
            # requirements. Instead, provide it as a promise which will be
            # available on subsequent turns.
            rv = DoubleObject(now - then)
            p, r = makePromise()
            vat = currentVat.get()
            vat.sendOnly(r, RESOLVE_1, [rv], EMPTY_MAP)
            return p

        raise Refused(self, atom, args)
