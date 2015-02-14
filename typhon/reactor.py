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

from rpython.rlib.rpoll import (POLLERR, POLLHUP, POLLIN, POLLNVAL, POLLOUT,
                                poll)
from rpython.rlib.rsignal import SIGPIPE, pypysig_ignore

from typhon.timers import Alarm


def ltAlarm(left, right):
    lk = left.key()
    rk = right.key()
    return lk[0] < rk[0] or lk[1] < rk[1]


class AlarmQueue(object):

    def __init__(self):
        self.heap = []

    def insert(self, alarm):
        self.heap.append(alarm)
        self.siftdown(0, len(self.heap) - 1)

    def pop(self):
        # raises appropriate IndexError if heap is empty
        lastelt = self.heap.pop()
        if self.heap:
            returnitem = self.heap[0]
            self.heap[0] = lastelt
            self.siftup(0)
        else:
            returnitem = lastelt
        return returnitem

    def siftup(self, position):
        endpos = len(self.heap)
        startpos = position
        newitem = self.heap[position]
        # Bubble up the smaller child until hitting a leaf.
        # leftmost child position
        childpos = 2 * position + 1
        while childpos < endpos:
            # Set childpos to index of smaller child.
            rightpos = childpos + 1
            if (rightpos < endpos
                    and ltAlarm(self.heap[rightpos], self.heap[childpos])):
                childpos = rightpos
            # Move the smaller child up.
            self.heap[position] = self.heap[childpos]
            position = childpos
            childpos = 2 * position + 1
        # The leaf at pos is empty now.  Put newitem there, and bubble it up
        # to its final resting place (by sifting its parents down).
        self.heap[position] = newitem
        self.siftdown(startpos, position)

    def siftdown(self, start, position):
        newitem = self.heap[position]
        # Follow the path to the root, moving parents down until finding a
        # place where newitem fits.
        while position > start:
            parentpos = (position - 1) >> 1
            parent = self.heap[parentpos]
            if ltAlarm(newitem, parent):
                self.heap[position] = parent
                position = parentpos
                continue
            break
        self.heap[position] = newitem


class Reactor(object):
    """
    An I/O manager.
    """

    timerSerial = 0

    def __init__(self):
        self._sockets = {}
        self._pollDict = {}
        self.alarmQueue = AlarmQueue()

    def usurpSignals(self):
        """
        Take control of all signal handling.

        It is expected that SIGTERM will still be respected.
        """

        # SIGPIPE: A pipe of some sort was broken. Normally handled by a more
        # proximate cause of the signal.
        pypysig_ignore(SIGPIPE)

    def hasObjects(self):
        return bool(self._pollDict) or bool(self.alarmQueue.heap)

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

        if socket.fd in self._sockets:
            del self._sockets[socket.fd]
        if socket.fd in self._pollDict:
            del self._pollDict[socket.fd]

    def addTimer(self, duration, resolver):
        timestamp = time.time() + duration
        serial = self.timerSerial
        self.timerSerial += 1
        alarm = Alarm(timestamp, serial, resolver)
        self.alarmQueue.insert(alarm)

    def getSoonestAlarm(self):
        if self.alarmQueue.heap:
            seconds = self.alarmQueue.heap[0].remaining(time.time())
            return int(seconds * 1000)
        return -1

    def fireAlarms(self):
        now = time.time()
        while self.alarmQueue.heap:
            alarm = self.alarmQueue.heap[0]
            if alarm.fire(now):
                self.alarmQueue.pop()
            else:
                break

    def spin(self, setTimeout):
        """
        Perform I/O.

        If setTimeout is set, set a very short timeout and return as soon as
        possible, rather than sleeping and waiting for I/O.
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
            timeout = self.getSoonestAlarm()

        results = poll(self._pollDict, timeout)
        # print "Polled", len(self._pollDict), "and got", len(results), "events"
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

        self.fireAlarms()
