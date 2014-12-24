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


class Scope(object):
    """
    A stack of namespaces.
    """

    index = 0

    def __init__(self):
        self.seen = [(0, {})]
        self.shadows = [{}]

    def __enter__(self):
        self.push()

    def __exit__(self, *args):
        self.pop()

    def push(self):
        self.seen.append((self.index, {}))
        self.shadows.append({})

    def pop(self):
        self.index, _ = self.seen.pop()
        self.shadows.pop()

    def getSeen(self, key):
        for _, d in reversed(self.seen):
            if key in d:
                return d[key]
        return -1

    def getShadow(self, key):
        for d in reversed(self.shadows):
            if key in d:
                return d[key]
        return None

    def putSeen(self, key):
        value = self.index
        print "Setting", key, "to", value
        self.seen[-1][1][key] = value
        self.index += 1
        return value

    def putShadow(self, key, value):
        self.shadows[-1][key] = value

    def size(self):
        return len(self.seen[-1][1])

    def shadowName(self, name):
        shadowed = name + u"_"
        while self.getShadow(shadowed) is not None:
            shadowed += u"_"
        self.putShadow(name, shadowed)
        return shadowed
