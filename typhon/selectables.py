# Copyright (C) 2015 Google Inc. All rights reserved.
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

import os

from errno import EADDRINUSE, EBADF, ECONNRESET, EPIPE

from rpython.rlib.jit import dont_look_inside
from rpython.rlib.rsignal import pypysig_poll, pypysig_set_wakeup_fd
from rpython.rlib.rsocket import CSocketError, INETAddress, RSocket, _c

from typhon.atoms import getAtom
from typhon.errors import userError
from typhon.objects.networking.sockets import SocketDrain, SocketFount
from typhon.objects.networking.stdio import InputFount
from typhon.vats import currentVat


RUN_2 = getAtom(u"run", 2)


# The maximum amount of data to receive from a single packet.
# XXX this should be a runtime tunable too, probably.
MAX_RECV = 8192


class Selectable(object):
    """
    An object that can be added to or removed from a reactor.

    Named after a similar concept in Twisted, but with slightly different
    behavior and encapsulation due to RPython constraints.
    """


class Wakeup(Selectable):
    """
    An object that exists only to indicate that signals have occurred.
    """

    def __init__(self):
        self.readFD, self.writeFD = os.pipe()

    def addToReactor(self, reactor):
        pypysig_set_wakeup_fd(self.writeFD)
        reactor.addFD(self.readFD, self)

    def removeFromReactor(self, reactor):
        reactor.dropFD(self.readFD)

    def wantsWrite(self):
        return False

    def read(self, reactor):
        # Read to clear the FD. If we don't do this, then the FD will ping on
        # every iteration of the reactor.
        os.read(self.readFD, 42)
        # For each signal, deliver it to the reactor.
        signal = pypysig_poll()
        while signal != -1:
            reactor.handleSignal(signal)
            signal = pypysig_poll()

    def error(self, reactor, reason):
        pass


class StandardInput(Selectable):
    """
    Standard input.
    """

    def __init__(self):
        self._founts = []

    def addToReactor(self, reactor):
        reactor.addFD(0, self)

    def removeFromReactor(self, reactor):
        reactor.dropFD(0)

    def wantsWrite(self):
        return False

    def read(self, reactor):
        buf = os.read(0, MAX_RECV)
        if not buf:
            self.error(reactor, u"End of stream")
            for f in self._founts:
                f.terminate(u"End of stream")
            return

        for fount in self._founts:
            fount.receive(buf)

    def error(self, reactor, reason):
        # We don't terminate the founts immediately; they need to drain.
        self.removeFromReactor(reactor)

    def createFount(self):
        vat = currentVat.get()
        fount = InputFount(vat)
        self._founts.append(fount)
        return fount


class StandardOutput(Selectable):
    """
    Standard output. Also standard error.
    """

    def __init__(self, reactor, fd):
        self.reactor = reactor
        self.fd = fd

        self._outbound = []

    def addToReactor(self, reactor):
        reactor.addFD(self.fd, self)

    def removeFromReactor(self, reactor):
        reactor.dropFD(self.fd)

    def wantsWrite(self):
        return bool(self._outbound)

    def write(self, reactor):
        for buf in self._outbound:
            written = os.write(self.fd, buf)
            assert written == len(buf), "Can't deal with short writes to stdout yet!"

        self._outbound = []
        self.removeFromReactor(reactor)

    def read(self, reactor):
        pass

    def error(self, reactor, reason):
        # print "stdout error", reason
        self.removeFromReactor(reactor)

    def enqueue(self, buf):
        self._outbound.append(buf)
        self.addToReactor(self.reactor)



# The number of connections that can be backlogged. Tune as needed.
# XXX this should be tunable at runtime!
BACKLOG =1024


class Socket(Selectable):
    """
    An encapsulation for RSockets.
    """

    _connector = None
    _listener = None

    closed = False

    def __init__(self, rsocket, vat):
        self.vat = vat
        self.rsock = rsocket
        self.fd = self.rsock.fd

        self._founts = []
        self._outbound = []

        self.addToReactor(vat._reactor)

    def repr(self):
        return u"<Socket(%d, %s)>" % (self.rsock.fd, self.vat.toString())

    def addToReactor(self, reactor):
        reactor.addFD(self.fd, self)

    def removeFromReactor(self, reactor):
        reactor.dropFD(self.fd)

    def wantsWrite(self):
        # print "wantsWrite", bool(self._outbound)
        return bool(self._outbound) or self._connector is not None

    @dont_look_inside
    def read(self, reactor):
        """
        Get some data and send it to interested founts.

        We should have been assured that we will not block.
        """

        from typhon.objects.collections import EMPTY_MAP
        # If we are a listening socket, let's not actually try to read, but
        # instead accept and spin off a new connection.
        if self._listener is not None:
            fd, _ = self.rsock.accept()
            sock = Socket(RSocket(fd=fd), self.vat)
            self.vat.sendOnly(self._listener, RUN_2, [sock.createFount(),
                                                      SocketDrain(sock)],
                              EMPTY_MAP)
            return

        # Perform the actual recv call.
        try:
            buf = self.rsock.recv(MAX_RECV)
        except CSocketError as cse:
            if cse.errno == EBADF:
                self.error(reactor, u"Can't read from invalidated socket")
                return
            elif cse.errno == ECONNRESET:
                self.error(reactor, u"Can't read from reset socket")
                return
            else:
                print "Not prepared to handle errno:", cse.errno
                raise

        if not buf:
            # Looks like we've died. Let's disconnect, right?
            self.error(reactor, u"End of stream")
            return

        for fount in self._founts:
            fount.receive(buf)

    @dont_look_inside
    def write(self, reactor):
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
                self.error(reactor, message)
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
                    self.error(reactor, u"Can't write to already-closed socket")
                    return
                elif cse.errno == EBADF:
                    # Bad file descriptor. The FD of the socket went bad
                    # somehow.
                    self.error(reactor, u"Can't write to invalidated socket")
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
    def error(self, reactor, reason):
        """
        Stop reading and writing, and gracefully clean up.
        """

        # print "Socket terminating:", reason

        if self.closed:
            # print "Socket already closed"
            return

        self.closed = True

        for fount in self._founts:
            fount.terminate(reason)

        self._founts = []

        reactor.dropFD(self.fd)
        self.rsock.close()

    def createFount(self):
        fount = SocketFount(self)
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
                reactor = self.vat._reactor
                self.error(reactor, u"Address is already in use")
                # We haven't gotten started yet, so it'd probably be a mercy
                # to our callers up above to get an error.
                raise userError(u"Address is already in use")
            else:
                raise
        else:
            self.rsock.listen(BACKLOG)
