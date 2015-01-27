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

from rpython.rlib.rsocket import INETAddress, RSocket

from typhon.atoms import getAtom
from typhon.errors import Refused
from typhon.objects.collections import ConstList
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapInt, unwrapStr
from typhon.objects.networking.sockets import Socket, SocketDrain
from typhon.objects.refs import makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


CONNECT_0 = getAtom(u"connect", 0)
LISTEN_1 = getAtom(u"listen", 1)
RUN_1 = getAtom(u"run", 1)
RUN_2 = getAtom(u"run", 2)


class TCP4ClientPending(object):

    socket = None

    def __init__(self, host, port):
        self.host = host
        self.port = port

        self.fount, self.fountResolver = makePromise()
        self.drain, self.drainResolver = makePromise()

    def createSocket(self):
        # Hint: The following line is where GAI is called.
        # XXX this should be IDNA, not UTF-8.
        addr = INETAddress(self.host.encode("utf-8"), self.port)
        self.socket = Socket(RSocket())
        # XXX demeter violation! Definitely.
        vat = currentVat.get()
        vat._reactor.addSocket(self.socket)
        self.socket.connect(addr, self)

    def failSocket(self, reason):
        u = reason.decode("utf-8")
        self.fountResolver.smash(u)
        self.drainResolver.smash(u)

    def fulfillSocket(self):
        self.fountResolver.resolve(self.socket.createFount())
        self.drainResolver.resolve(SocketDrain(self.socket))


class TCP4ClientEndpoint(Object):

    def __init__(self, host, port):
        self.host = host
        self.port = port

    def toString(self):
        return u"<endpoint (IPv4, TCP): %s:%d>" % (self.host, self.port)

    def recv(self, atom, args):
        if atom is CONNECT_0:
            return self.connect()

        raise Refused(self, atom, args)

    def connect(self):
        pending = TCP4ClientPending(self.host, self.port)
        vat = currentVat.get()
        vat.afterTurn(pending.createSocket)
        return ConstList([pending.fount, pending.drain])


@runnable(RUN_2)
def makeTCP4ClientEndpoint(args):
    host = unwrapStr(args[0])
    port = unwrapInt(args[1])
    return TCP4ClientEndpoint(host, port)


class TCP4ServerEndpoint(Object):

    def __init__(self, port):
        self.port = port

    def toString(self):
        return u"<endpoint (IPv4, TCP): %d>" % (self.port,)

    def recv(self, atom, args):
        if atom is LISTEN_1:
            return self.listen(args[0])

        raise Refused(self, atom, args)

    def listen(self, handler):
        socket = Socket(RSocket())
        # XXX demeter violation!
        vat = currentVat.get()
        vat._reactor.addSocket(socket)
        # XXX this shouldn't block, but not guaranteed
        socket.listen(self.port, handler)

        # XXX should a promise be returned here?
        return NullObject


@runnable(RUN_1)
def makeTCP4ServerEndpoint(args):
    port = unwrapInt(args[0])
    return TCP4ServerEndpoint(port)
