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

from rpython.rlib.rpoll import (POLLERR, POLLHUP, POLLIN, POLLNVAL, POLLOUT,
                                poll)


class Reactor(object):
    """
    An I/O manager.
    """

    def __init__(self):
        self._sockets = {}
        self._pollDict = {}

    def hasObjects(self):
        return bool(self._pollDict)

    def addSocket(self, socket):
        """
        Add a socket to the list of interesting sockets.
        """

        flags = POLLIN | POLLERR | POLLHUP | POLLNVAL
        if socket.wantsWrite():
            flags |= POLLOUT
        self._sockets[socket.fd] = socket
        self._pollDict[socket.fd] = flags

    def dropSocket(self, socket):
        """
        Remove a socket from the list of interesting sockets.
        """

        del self._sockets[socket.fd]
        del self._pollDict[socket.fd]

    def spin(self, setTimeout):
        """
        Perform I/O.
        """

        for fd, socket in self._sockets.iteritems():
            # Only ask about writing to sockets if we actually have a serious
            # desire to write to them.
            if socket.wantsWrite():
                self._pollDict[fd] |= POLLOUT
            else:
                self._pollDict[fd] &= ~POLLOUT

        if setTimeout:
            timeout = 0
        else:
            timeout = -1

        results = poll(self._pollDict, timeout)
        print "Polled", len(self.pollDict), "and got", len(results), "events"
        for fd, event in results:
            socket = self._sockets[fd]
            # Write before reading. This seems like the correct order of
            # operations.
            if event & POLLOUT:
                socket.write()
            if event & POLLIN:
                socket.read()
            if event & (POLLERR | POLLHUP | POLLNVAL):
                # Looks like this socket's met with a bad end. We'll go ahead
                # and discard it.
                self.dropSocket(socket)
