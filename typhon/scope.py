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

    def __init__(self):
        self.scope = [{}]

    def __enter__(self):
        self.push()

    def __exit__(self, *args):
        self.pop()

    def push(self):
        self.scope.append({})

    def pop(self):
        self.scope.pop()

    def get(self, key):
        for d in reversed(self.scope):
            if key in d:
                return d[key]
        return None

    def put(self, key, value):
        self.scope[-1][key] = value

    def size(self):
        return len(self.scope[-1])
