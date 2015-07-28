# Copyright (C) 2014 Google Inc. All rights reserved.  #
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

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.errors import userError
from typhon.objects.collections import ConstList
from typhon.objects.data import IntObject, StrObject, unwrapInt
from typhon.objects.root import Object, method
from typhon.specs import Any, List, Str, Void


ABORTFLOW_0 = getAtom(u"abortFlow", 0)
FLOWABORTED_1 = getAtom(u"flowAborted", 1)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWSTOPPED_1 = getAtom(u"flowStopped", 1)
FLOWTO_1 = getAtom(u"flowTo", 1)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


@autohelp
class SocketUnpauser(Object):
    """
    A pause on a socket fount.
    """

    def __init__(self, fount):
        self.fount = fount

    @method([], Void)
    def unpause(self):
        assert isinstance(self, SocketUnpauser)
        if self.fount is not None:
            self.fount.unpause()
            self.fount = None


@autohelp
class SocketFount(Object):
    """
    A fount which flows data out from a socket.
    """

    pauses = 0
    buf = ""

    _drain = None

    def __init__(self, sock):
        self.sock = sock

    def toString(self):
        return u"<SocketFount(%s)>" % self.sock.repr()

    @method([Any], Any)
    def flowTo(self, drain):
        assert isinstance(self, SocketFount)
        self._drain = drain
        # We can't actually call receive/1 on the drain until
        # flowingFrom/1 has been called, *but* flush() should be using
        # sends to incant receive/1, so they'll all be done in subsequent
        # turns to the one we're queueing. ~ C.
        rv = self.sock.vat.send(drain, FLOWINGFROM_1, [self])
        self.flush()
        return rv

    @method([], Any)
    def pauseFlow(self):
        assert isinstance(self, SocketFount)
        return self.pause()

    @method([], Void)
    def abortFlow(self):
        assert isinstance(self, SocketFount)
        self.sock.vat.sendOnly(self._drain, FLOWABORTED_1,
                               [StrObject(u"Flow aborted")])
        # Release the drain. They should have released us as well.
        self._drain = None

    @method([], Void)
    def stopFlow(self):
        assert isinstance(self, SocketFount)
        self.terminate(u"Flow stopped")

    def pause(self):
        self.pauses += 1
        return SocketUnpauser(self)

    def unpause(self):
        self.pauses -= 1
        self.flush()

    def receive(self, buf):
        self.buf += buf
        self.flush()

    def flush(self):
        # print "SocketFount flush", self.pauses, self._drain
        if not self.pauses and self._drain is not None:
            rv = [IntObject(ord(byte)) for byte in self.buf]
            self.sock.vat.sendOnly(self._drain, RECEIVE_1, [ConstList(rv)])
            self.buf = ""

    def terminate(self, reason):
        if self._drain is not None:
            self.sock.vat.sendOnly(self._drain, FLOWSTOPPED_1,
                                   [StrObject(reason)])
            # Release the drain. They should have released us as well.
            self._drain = None


@autohelp
class SocketDrain(Object):
    """
    A drain which sends received data out on a socket.
    """

    _closed = False

    def __init__(self, socket):
        self.sock = socket
        self._buf = []

    def toString(self):
        return u"<SocketDrain(%s)>" % self.sock.repr()

    @method([Any], Any)
    def flowingFrom(self, fount):
        return self

    @method([List], Void)
    def receive(self, data):
        assert isinstance(self, SocketDrain)
        if self._closed:
            raise userError(u"Can't send data to a closed socket!")

        s = "".join([chr(unwrapInt(byte)) for byte in data])
        self.sock._outbound.append(s)

    @method([Str], Void)
    def flowAborted(self, reason):
        assert isinstance(self, SocketDrain)
        self._closed = True
        self.sock.error(self.sock.vat._reactor, reason)

    @method([Str], Void)
    def flowStopped(self, reason):
        assert isinstance(self, SocketDrain)
        self._closed = True
        self.sock.error(self.sock.vat._reactor, reason)
