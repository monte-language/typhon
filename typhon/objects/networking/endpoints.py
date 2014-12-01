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
from typhon.objects.constants import NullObject
from typhon.objects.data import unwrapInt, unwrapStr
from typhon.objects.networking.sockets import Socket
from typhon.objects.root import Object


CONNECT_1 = getAtom(u"connect", 1)
RUN_2 = getAtom(u"run", 2)


class TCP4ClientEndpoint(Object):

    def __init__(self, vat, host, port):
        self.vat = vat
        self.host = host
        self.port = port

    def repr(self):
        return "<endpoint (IPv4, TCP): %s:%d>" % (self.host, self.port)

    def recv(self, atom, args):
        if atom is CONNECT_1:
            return self.connect(args[0])

        raise Refused(atom, args)

    def connect(self, handler):
        # Apologies. You're probably here to make GAI into a non-blocking
        # operation. Best of luck!
        # Hint: The following line is where GAI is called.
        addr = INETAddress(self.host, self.port)
        socket = Socket(self.vat, RSocket())
        # XXX demeter violation?
        self.vat._reactor.addSocket(socket)
        # XXX this shouldn't block, but not guaranteed
        socket.connect(addr, handler)

        # XXX should a promise be returned here?
        return NullObject


class MakeTCP4ClientEndpoint(Object):

    def __init__(self, vat):
        self.vat = vat

    def repr(self):
        return "<makeTCP4Endpoint>"

    def recv(self, atom, args):
        if atom is RUN_2:
            host = unwrapStr(args[0])
            port = unwrapInt(args[1])
            # XXX this should be IDNA, not UTF-8.
            return TCP4ClientEndpoint(self.vat, host.encode("utf-8"), port)

        raise Refused(atom, args)
