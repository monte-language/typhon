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


class ListStream(object):

    _counter = 0

    def __init__(self, items):
        self._items = items

    def done(self):
        return self._counter >= len(self._items)

    def nextItem(self):
        if self._counter >= len(self._items):
            raise IndexError("Ran out of arguments to parse")
        rv = self._items[self._counter]
        self._counter += 1
        return rv


class Configuration(object):
    """
    Typhon global configuration.

    Despite being called "global", this object is not meant to be used as a
    singleton. Instantiate with argv and then pass around relevant bits.

    The Law of Demeter is waived for this object; treat it as data.
    """

    # Whether to exit after loading the script file. Useful for testing.
    loadOnly = False

    # Whether to collect precise profiling statistics.
    profile = False

    # Whether to run benchmarks.
    benchmark = False

    # User settings for the JIT.
    jit = "default"

    def __init__(self, argv):
        # Arguments not consumed by Typhon. Will be available to the main
        # script.
        self.argv = []

        # The paths from which to draw imports and the prelude.
        self.libraryPaths = []

        stream = ListStream(argv)
        # argv[0] is always the name that we were invoked with. Always.
        self.argv.append(stream.nextItem())

        while not stream.done():
            item = stream.nextItem()

            if item == "-l":
                self.libraryPaths.append(stream.nextItem())
            elif item == "-load":
                self.loadOnly = True
            elif item == "-p":
                self.profile = True
            elif item == "-b":
                self.benchmark = True
            elif item == "--jit":
                self.jit = stream.nextItem()
            else:
                self.argv.append(item)
