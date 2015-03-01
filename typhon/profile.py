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

import time

from rpython.rlib.jit import we_are_jitted
from rpython.rlib.objectmodel import specialize


class CallStackProfiler(object):

    _immutable_fields_ = "enabled?",

    # XXX is this backwards?
    enabled = True

    def __init__(self):
        self.currentStack = []
        self.stacks = {}

    def __enter__(self):
        pass

    def __exit__(self, *args):
        if not self.enabled:
            return

        # End as soon as possible. We can't end before this because we don't
        # want to incur the cost of the syscall before avoiding work.
        end = time.time()

        stack = u";".join([pair[0] for pair in self.currentStack])
        label, start = self.currentStack.pop()
        newTime = self.stacks.get(stack, 0.0) + end - start
        self.stacks[stack] = newTime

    def startCall(self, obj, atom):
        if not self.enabled:
            return self

        label = u"%s.%s/%d" % (obj.displayName, atom.verb, atom.arity)
        # Replace ; with , in names. Semicolons are used to separate stack
        # frames later.
        label = label.replace(u";", u",")
        if we_are_jitted():
            # It's nice to know how much time is spent in the JIT. It's also
            # nice to know which methods have been compiled.
            label += u" (JIT)"

        # Start as late as possible.
        start = time.time()
        self.currentStack.append((label, start))
        return self

    def writeFlames(self, handle):
        for stack, count in self.stacks.items():
            microCount = int(count * 100000)
            if microCount:
                handle.write("%s %d\n" % (stack.encode("utf-8"), microCount))

    def disable(self):
        self.enabled = False


csp = CallStackProfiler()
