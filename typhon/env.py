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
DEF, VAR = range(2)


def finalize(scope):
    rv = {}
    for key in scope:
        rv[key] = DEF, scope[key]
    return rv


class Environment(object):
    """
    An execution context.
    """

    def __init__(self, baseScope):
        self._frames = [finalize(baseScope)]

    def __enter__(self):
        self.enterFrame()
        return self

    def __exit__(self, *args):
        self.leaveFrame()

    def enterFrame(self):
        self._frames.append({})

    def leaveFrame(self):
        frame = self._frames.pop()

    def _record(self, noun, value):
        try:
            frame = self._findFrame(noun)
        except:
            frame = self._frames[-1]
        frame[noun] = value

    def _findFrame(self, noun):
        i = len(self._frames)
        while i > 0:
            i -= 1
            frame = self._frames[i]
            if noun in frame:
                return frame
        raise KeyError(noun)

    def _find(self, noun):
        i = len(self._frames)
        while i > 0:
            i -= 1
            frame = self._frames[i]
            if noun in frame:
                return frame[noun]
        raise KeyError(noun)

    def final(self, noun, value):
        self._record(noun, (DEF, value))

    def variable(self, noun, value):
        self._record(noun, (VAR, value))

    def update(self, noun, value):
        style, oldValue = self._find(noun)
        if style == VAR:
            # XXX this won't alter outer bindings. A real slot mechanism is
            # needed here!
            self._record(noun, (VAR, value))
        else:
            raise RuntimeError

    def get(self, noun):
        style, value = self._find(noun)
        return value
