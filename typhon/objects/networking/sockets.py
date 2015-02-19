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

from errno import EADDRINUSE, EBADF, EPIPE

from rpython.rlib.jit import dont_look_inside
from rpython.rlib.rsocket import CSocketError, INETAddress, RSocket, _c

from typhon.atoms import getAtom
from typhon.errors import Refused, userError
from typhon.objects.collections import ConstList, unwrapList
from typhon.objects.constants import NullObject
from typhon.objects.data import IntObject, unwrapInt
from typhon.objects.root import Object
from typhon.vats import currentVat


FLOWINGFROM_1 = getAtom(u"flowingFrom", 1)
FLOWSTOPPED_0 = getAtom(u"flowStopped", 0)
FLOWTO_1 = getAtom(u"flowTo", 1)
PAUSEFLOW_0 = getAtom(u"pauseFlow", 0)
RECEIVE_1 = getAtom(u"receive", 1)
RUN_2 = getAtom(u"run", 2)
STOPFLOW_0 = getAtom(u"stopFlow", 0)
UNPAUSE_0 = getAtom(u"unpause", 0)


# The number of connections that can be backlogged. Tune as needed.
# XXX this should be tunable at runtime!
BACKLOG =1024

# The maximum amount of data to receive from a single packet.
# XXX this should be a runtime tunable too, probably.
MAX_RECV = 8192


class Socket(object):
    """
    An encapsulation for RSockets.
    """

    _connector = None
    _listener = None

    def __init__(self, rsocket):
        self.rsock = rsocket
        self.fd = self.rsock.fd

        self._founts = []
        self._outbound = []

    def repr(self):
        return u"<Socket(%d)>" % self.rsock.fd

    def wantsWrite(self):
        return bool(self._outbound) or self._connector is not None

    def createFount(self):
        fount = SocketFount()
        self._founts.append(fount)
        return fount

    @dont_look_inside
    def connect(self, addr, handler):
        self._connector = handler

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

    @dont_look_inside
    def listen(self, port, handler):
        self._listener = handler

        self.rsock.setblocking(False)
        addr = INETAddress("0.0.0.0", port)

        try:
            self.rsock.bind(addr)
        except CSocketError as cse:
            if cse.errno == EADDRINUSE:
                self.terminate(u"Address is already in use")
            else:
                raise
        else:
            self.rsock.listen(BACKLOG)

    @dont_look_inside
    def read(self):
        """
        Get some data and send it to interested founts.

        We should have been assured that we will not block.
        """

        # If we are a listening socket, let's not actually try to read, but
        # instead accept and spin off a new connection.
        if self._listener is not None:
            fd, _ = self.rsock.accept()
            sock = Socket(RSocket(fd=fd))
            # XXX demeter!
            vat = currentVat.get()
            vat._reactor.addSocket(sock)
            self._listener.call(u"run", [sock.createFount(),
                                         SocketDrain(sock)])
            return

        # Perform the actual recv call.
        try:
            buf = self.rsock.recv(MAX_RECV)
        except CSocketError as cse:
            if cse.errno == EBADF:
                self.terminate(u"Can't write to invalidated socket")
                return
            else:
                raise

        if not buf:
            # Looks like we've died. Let's disconnect, right?
            self.terminate(u"End of stream")
            return

        for fount in self._founts:
            fount.receive(buf)

    @dont_look_inside
    def write(self):
        """
        Send buffered data.

        We should have been assured that we will not block.
        """

        if self._connector is not None:
            # Did we have an error connecting?
            err = self.rsock.getsockopt_int(_c.SOL_SOCKET, _c.SO_ERROR)
            if err:
                message = CSocketError(err).get_msg().decode("utf-8")
                self._connector.failSocket(message)
                self.terminate(message)
            else:
                # We just finished connecting.
                self._connector.fulfillSocket()

            self._connector = None
            return

        for i, item in enumerate(self._outbound):
            try:
                size = self.rsock.send(item)
            except CSocketError as cse:
                if cse.errno == EPIPE:
                    # Broken pipe. The local end of the socket was already
                    # closed; it will be impossible to send this data through.
                    self.terminate(u"Can't write to already-closed socket")
                    return
                elif cse.errno == EBADF:
                    # Bad file descriptor. The FD of the socket went bad
                    # somehow.
                    self.terminate(u"Can't write to invalidated socket")
                    return
                else:
                    raise

            if size < len(item):
                # Short write; trim the outgoing chunk and the entire outbound
                # list, and then give up on writing for now.
                item = item[:size]
                self._outbound = [item] + self._outbound[i + 1:]
                return
        self._outbound = []

    @dont_look_inside
    def close(self):
        """
        Stop writing.
        """

        # XXX yet more demeter
        vat = currentVat.get()
        vat._reactor.dropSocket(self)
        self.rsock.close()

    def terminate(self, reason):
        """
        Recover from errors by gracefully cleaning up.
        """

        for fount in self._founts:
            fount.terminate(reason)

        self._founts = []

        self.close()


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

    def toString(self):
        return u"<SocketFount>"

    def recv(self, atom, args):
        if atom is FLOWTO_1:
            self._drain = drain = args[0]
            rv = drain.call(u"flowingFrom", [self])
            return rv

        if atom is PAUSEFLOW_0:
            return self.pause()

        if atom is STOPFLOW_0:
            self.terminate(u"Flow stopped")
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
            vat = currentVat.get()
            vat.sendOnly(self._drain, u"receive", [ConstList(rv)])
            self.buf = ""

    def terminate(self, reason):
        if self._drain is not None:
            # XXX should flowStopped take a reason as arg?
            self._drain.call(u"flowStopped", [])
            # Release the drain. They should have released us as well.
            self._drain = None


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

    def recv(self, atom, args):
        if atom is FLOWINGFROM_1:
            return self

        if atom is RECEIVE_1:
            if self._closed:
                raise userError(u"Can't send data to a closed socket!")

            data = unwrapList(args[0])
            s = "".join([chr(unwrapInt(byte)) for byte in data])
            self.sock._outbound.append(s)
            return NullObject

        if atom is FLOWSTOPPED_0:
            self._closed = True
            # self.sock.close()
            return NullObject

        raise Refused(self, atom, args)
