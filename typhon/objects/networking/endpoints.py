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

from rpython.rlib.jit import dont_look_inside
from rpython.rlib.rsocket import INETAddress, RSocket

from typhon.atoms import getAtom
from typhon.autohelp import autohelp
from typhon.objects.data import unwrapInt, unwrapStr
from typhon.objects.networking.sockets import SocketDrain
from typhon.objects.refs import makePromise
from typhon.objects.root import Object, method, runnable
from typhon.selectables import Socket
from typhon.specs import Any, List, Void
from typhon.vats import Callable, currentVat


RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


class TCP4ClientPending(Callable):

    socket = None

    def __init__(self, host, port):
        self.host = host
        self.port = port

        self.fount, self.fountResolver = makePromise()
        self.drain, self.drainResolver = makePromise()

    def call(self):
        # Hint: The following line is where GAI is called.
        # XXX this should be IDNA, not UTF-8.
        addr = INETAddress(self.host.encode("utf-8"), self.port)
        vat = currentVat.get()
        self.socket = Socket(RSocket(), vat)
        self.socket.connect(addr, self)

    def failSocket(self, reason):
        self.fountResolver.smash(reason)
        self.drainResolver.smash(reason)

    def fulfillSocket(self):
        """
        Fulfill the sockets.
        """

        socket = self.socket
        assert socket is not None, "Bad socket"

        self.fountResolver.resolve(socket.createFount())
        self.drainResolver.resolve(SocketDrain(socket))


@autohelp
class TCP4ClientEndpoint(Object):
    """
    A TCPv4 client endpoint.
    """

    def __init__(self, host, port):
        self.host = host
        self.port = port

    def toString(self):
        return u"<endpoint (IPv4, TCP): %s:%d>" % (self.host, self.port)

    @method([], List)
    def connect(self):
        assert isinstance(self, TCP4ClientEndpoint)
        pending = TCP4ClientPending(self.host, self.port)
        vat = currentVat.get()
        vat.afterTurn(pending)
        return [pending.fount, pending.drain]


@runnable(RUN_2)
def makeTCP4ClientEndpoint(args):
    """
    Make a TCPv4 client endpoint.
    """

    host = unwrapStr(args[0])
    port = unwrapInt(args[1])
    return TCP4ClientEndpoint(host, port)


@autohelp
class TCP4ServerEndpoint(Object):
    """
    A TCPv4 server endpoint.
    """

    def __init__(self, port):
        self.port = port

    def toString(self):
        return u"<endpoint (IPv4, TCP): %d>" % (self.port,)

    @dont_look_inside
    @method([Any], Void)
    def listen(self, handler):
        assert isinstance(self, TCP4ServerEndpoint)
        vat = currentVat.get()
        socket = Socket(RSocket(), vat)
        # XXX this shouldn't block, but not guaranteed
        socket.listen(self.port, handler)
        # XXX should a promise be returned here?


@runnable(RUN_1)
def makeTCP4ServerEndpoint(args):
    """
    Make a TCPv4 server endpoint.
    """

    port = unwrapInt(args[0])
    return TCP4ServerEndpoint(port)
