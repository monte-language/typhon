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

from rpython.rlib.rthread import ThreadLocalReference

from typhon.errors import UserException
from typhon.objects.refs import Promise, makePromise, resolution


class Vat(object):
    """
    Turn management and object isolation.
    """

    def __init__(self, reactor):
        self._reactor = reactor

        self._callbacks = []

        # XXX should define a lock here
        # XXX should lock all accesses of _pending
        self._pending = []

    def repr(self):
        return u"<vat (%d pending)>" % (len(self._pending),)

    def send(self, target, verb, args):
        promise, resolver = makePromise(self)
        self._pending.append((resolver, target, verb, args))
        return promise

    def sendOnly(self, target, verb, args):
        self._pending.append((None, target, verb, args))

    def hasTurns(self):
        return len(self._pending) != 0

    def takeTurn(self):
        resolver, target, verb, args = self._pending.pop(0)

        # If the target is a promise, then we should send to it instead of
        # calling. Try to resolve it as much as possible first, though.
        target = resolution(target)

        if resolver is None:
            # callOnly/sendOnly.
            if isinstance(target, Promise):
                target.sendOnly(verb, args)
            else:
                # Oh, that's right; we don't do callOnly since it's silly.
                target.call(verb, args)
        else:
            # call/send.
            if isinstance(target, Promise):
                result = target.send(verb, args)
            else:
                result = target.call(verb, args)
            resolver.resolve(result)

    def afterTurn(self, callback):
        """
        After the current turn, run this callback.

        The callback must guarantee that it will *not* take turns on the vat!
        """

        self._callbacks.append(callback)

    def runCallbacks(self):
        for callback in self._callbacks:
            callback()
        self._callbacks = []

    def takeSomeTurns(self, recorder):
        # Limit the number of continuous turns to keep network latency low.
        count = min(3, len(self._pending))
        # print "Taking", count, "turn(s) on", self.repr()
        for _ in range(count):
            try:
                recorder.record("Time spent in vats", self.takeTurn)
            except UserException as ue:
                print "Caught exception while taking turn:", ue.formatError()

        self.runCallbacks()


currentVat = ThreadLocalReference(Vat)
