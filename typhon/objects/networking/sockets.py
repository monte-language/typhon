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

from rpython.rlib.nonconst import NonConstant
from rpython.rlib.rsocket import CSocketError, INETAddress, RSocket, _c

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, unwrapInt
from typhon.objects.root import Object


CLOSE_0 = getAtom(u"close", 0)
FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWTO_1 = getAtom(u"flowTo", 1)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


# The number of connections that can be backlogged. Tune as needed.
# XXX this should be tunable at runtime!
BACKLOG =1024


class Socket(object):
    """
    An encapsulation for RSockets.
    """

    _connectHandler = None
    _listener = None

    def __init__(self, vat, rsocket):
        self._vat = vat
        self.rsock = rsocket
        self.fd = self.rsock.fd

        self._founts = []
        self._outbound = []

    def repr(self):
        return "<Socket(%d)>" % self.rsock.fd

    def wantsWrite(self):
        return bool(self._outbound) or self._connectHandler is not None

    def createFount(self):
        fount = SocketFount(self._vat)
        self._founts.append(fount)
        return fount

    def connect(self, addr, handler):
        self._connectHandler = handler

        self.rsock.setblocking(False)

        try:
            self.rsock.connect(addr)
        except CSocketError as cse:
            if cse.errno == _c.EINPROGRESS:
                # Expected; the system is telling us that the socket is
                # non-blocking and will complete the connection later.
                pass
            else:
                raise

    def listen(self, port, handler):
        self._listener = handler

        self.rsock.setblocking(False)
        addr = INETAddress("0.0.0.0", port)
        self.rsock.bind(addr)
        self.rsock.listen(BACKLOG)

    def read(self):
        """
        Get some data and send it to interested founts.

        We should have been assured that we will not block.
        """

        # If we are a listening socket, let's not actually try to read, but
        # instead accept and spin off a new connection.
        if self._listener is not None:
            fd, _ = self.rsock.accept()
            sock = Socket(self._vat, RSocket(fd=fd))
            # XXX demeter
            self._vat._reactor.addSocket(sock)
            self._listener.call(u"run", [sock.createFount(),
                                         SocketDrain(sock)])
            return

        # XXX RPython bug requires NC here
        buf = self.rsock.recv(NonConstant(8192))

        if not buf:
            # Looks like we've died. Let's disconnect, right?
            self.rsock.close()
        for fount in self._founts:
            fount.receive(buf)

    def write(self):
        """
        Send buffered data.

        We should have been assured that we will not block.
        """

        if self._connectHandler is not None:
            # Did we have an error connecting?
            err = self.rsock.getsockopt_int(_c.SOL_SOCKET, _c.SO_ERROR)
            if err:
                self._connectHandler.failSocket(CSocketError(err).get_msg())
                self.terminate()
            else:
                # We just finished connecting.
                self._connectHandler.fulfillSocket()

            self._connectHandler = None
            return

        for i, item in enumerate(self._outbound):
            try:
                size = self.rsock.send(item)
            except CSocketError as cse:
                if cse.errno == _c.EPIPE:
                    # Broken pipe. The local end of the socket was already
                    # closed; it will be impossible to send this data through.
                    raise userError(u"Can't write to already-closed socket")
                else:
                    raise

            if size < len(item):
                # Short write; trim the outgoing chunk and the entire outbound
                # list, and then give up on writing for now.
                item = item[:size]
                self._outbound = self._outbound[:i]
                self._outbound[i] = item
                return
        self._outbound = []

    def close(self):
        """
        Stop writing.
        """

    def terminate(self):
        """
        Recover from errors by gracefully cleaning up.
        """

        for fount in self._founts:
            fount.terminate()

        self._founts = []

        self.rsock.close()


class SocketUnpauser(Object):
    """
    A pause on a socket fount.
    """

    def __init__(self, fount):
        self.fount = fount

    def recv(self, atom, args):
        if atom is UNPAUSE_0:
            if self.fount is not None:
                self.fount.unpause()
                self.fount = None
            return NullObject
        raise Refused(self, atom, args)


class SocketFount(Object):
    """
    A fount which flows data out from a socket.
    """

    pauses = 0
    buf = ""

    _drain = None

    def __init__(self, vat):
        self._vat = vat

    def repr(self):
        return "<SocketFount>"

    def recv(self, atom, args):
        if atom is FLOWTO_1:
            self._drain = drain = args[0]
            rv = drain.call(u"flowingFrom", [self])
            return rv

        if atom is PAUSEFLOW_0:
            return self.pause()

        if atom is STOPFLOW_0:
            self.terminate()
            return NullObject

        raise Refused(self, atom, args)

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
        if not self.pauses and self._drain is not None:
            rv = [IntObject(ord(byte)) for byte in self.buf]
            self._vat.sendOnly(self._drain, u"receive", [ConstList(rv)])
            self.buf = ""

    def terminate(self):
        if self._drain is not None:
            self._drain.call(u"flowStopped", [])
            # Release the drain. They should have released us as well.
            self._drain = None


class SocketDrain(Object):
    """
    A drain which sends received data out on a socket.
    """

    def __init__(self, socket):
        self.sock = socket
        self._buf = []

    def repr(self):
        return "<SocketDrain(%s)>" % self.sock.repr()

    def recv(self, atom, args):
        if atom is FLOWINGFROM_1:
            # XXX flowingFrom
            return self

        if atom is RECEIVE_1:
            data = unwrapList(args[0])
            s = "".join([chr(unwrapInt(byte)) for byte in data])
            self.sock._outbound.append(s)
            return NullObject

        if atom is CLOSE_0:
            self.sock.close()
            return NullObject

        raise Refused(self, atom, args)
